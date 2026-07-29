import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import 'automations.dart';
import 'config.dart';
import 'catalog.dart';
import 'integrations.dart';
import 'marketplace.dart';
import 'models.dart';
import 'security.dart';
import 'store.dart';

final class StudioFlowApi {
  final BackendStore store;
  final BackendConfig config;
  final PasswordSecurity passwords;
  final TokenSecurity tokens;
  final PasswordResetNotifier resetNotifier;
  final MarketplaceBackendStore marketplace;
  final MessageAutomationStore? automations;
  final CatalogLookupService? catalog;
  final Uuid _uuid;

  StudioFlowApi({
    required this.store,
    required this.config,
    PasswordSecurity? passwords,
    TokenSecurity? tokens,
    PasswordResetNotifier? resetNotifier,
    MarketplaceBackendStore? marketplace,
    this.automations,
    this.catalog,
    Uuid? uuid,
  }) : passwords = passwords ?? const PasswordSecurity(),
       tokens =
           tokens ??
           TokenSecurity(
             secret: config.jwtSecret,
             accessDuration: config.accessTokenDuration,
           ),
       resetNotifier =
           resetNotifier ??
           (config.emailProviderUrl != null || config.smsProviderUrl != null
               ? HttpPasswordResetNotifier(config)
               : const DisabledPasswordResetNotifier()),
       marketplace = marketplace ?? store as MarketplaceBackendStore,
       _uuid = uuid ?? const Uuid();

  Handler get handler {
    final router = Router()
      ..get('/health', _health)
      ..post('/v1/auth/register-business', _registerBusiness)
      ..post('/v1/auth/login', _login)
      ..post('/v1/auth/refresh', _refresh)
      ..post('/v1/auth/logout', _logout)
      ..post('/v1/auth/password/request', _requestPasswordReset)
      ..post('/v1/auth/password/reset', _resetPassword)
      ..post('/v1/sync/push', _push)
      ..get('/v1/sync/pull', _pull)
      ..get('/v1/marketplace/offers', _searchOffers)
      ..post('/v1/marketplace/offers/<id>/click', _clickOffer)
      ..get('/v1/admin/affiliate/programs', _adminPrograms)
      ..put('/v1/admin/affiliate/programs/<id>', _adminSaveProgram)
      ..put('/v1/admin/marketplace/offers/<id>', _adminSaveOffer)
      ..post('/v1/admin/affiliate/conversions', _adminConversion)
      ..get('/v1/admin/affiliate/metrics', _adminMetrics)
      ..get('/v1/messages/history', _messageHistory)
      ..get('/v1/catalog/gtin/<gtin>', _catalogGtin)
      ..post('/v1/webhooks/messages', _messageWebhook)
      ..get('/v1/webhooks/whatsapp', _whatsappVerify)
      ..post('/v1/webhooks/whatsapp', _whatsappWebhook);
    return const Pipeline()
        .addMiddleware(_securityHeaders())
        .addMiddleware(_errorBoundary())
        .addMiddleware(logRequests())
        .addHandler(router.call);
  }

  Future<Response> _health(Request request) async {
    await store.ping();
    return _json(200, {
      'status': 'ok',
      'service': 'studioflow-api',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<Response> _registerBusiness(Request request) async {
    final body = await _body(request);
    final businessName = _requiredText(body, 'businessName', max: 160);
    final ownerName = _requiredText(body, 'ownerName', max: 160);
    final phone = _requiredText(body, 'phone', max: 32);
    final login = _normalizeLogin(_requiredText(body, 'login', max: 254));
    final password = _requiredText(body, 'password', max: 128);
    final segment = (body['segment'] as String? ?? 'salao').trim();
    final account = await store.createBusinessOwner(
      businessId: _optionalIdentifier(body['businessId']) ?? _uuid.v4(),
      businessName: businessName,
      segment: segment,
      userId: _optionalIdentifier(body['userId']) ?? _uuid.v4(),
      ownerName: ownerName,
      phone: phone,
      login: login,
      passwordHash: passwords.hash(password),
    );
    await store.audit(
      event: 'auth.business_registered',
      businessId: account.businessId,
      userId: account.userId,
      success: true,
      details: const {},
    );
    return _issueSession(account, statusCode: 201);
  }

  Future<Response> _login(Request request) async {
    final body = await _body(request);
    final login = _normalizeLogin(_requiredText(body, 'login', max: 254));
    final password = _requiredText(body, 'password', max: 128);
    final selectedBusinessId = (body['businessId'] as String?)?.trim();
    final accounts = await store.findAccountsByLogin(login);
    final valid = accounts
        .where((account) => passwords.verify(password, account.passwordHash))
        .toList();
    if (valid.isEmpty) {
      await store.audit(
        event: 'auth.login',
        success: false,
        details: {'loginHash': tokens.hashOpaqueToken(login)},
      );
      return _error(401, 'invalid_credentials', 'Login ou senha inválidos.');
    }
    if (selectedBusinessId == null && valid.length > 1) {
      return _json(200, {
        'selectionRequired': true,
        'accounts': valid.map((account) => account.toPublicJson()).toList(),
      });
    }
    final account = selectedBusinessId == null
        ? valid.single
        : valid
              .where((item) => item.businessId == selectedBusinessId)
              .firstOrNull;
    if (account == null) {
      return _error(
        400,
        'invalid_business',
        'O estabelecimento selecionado não pertence a esta conta.',
      );
    }
    return _issueSession(account);
  }

  Future<Response> _issueSession(
    AccountIdentity account, {
    int statusCode = 200,
  }) async {
    final sessionId = _uuid.v4();
    final refreshToken = tokens.createOpaqueToken();
    final expiresAt = DateTime.now().toUtc().add(config.refreshTokenDuration);
    await store.createSession(
      SessionRecord(
        id: sessionId,
        userId: account.userId,
        businessId: account.businessId,
        refreshTokenHash: tokens.hashOpaqueToken(refreshToken),
        expiresAt: expiresAt,
        revoked: false,
      ),
    );
    final context = AuthContext(
      userId: account.userId,
      businessId: account.businessId,
      role: account.role,
      sessionId: sessionId,
    );
    await store.audit(
      event: 'auth.login',
      businessId: account.businessId,
      userId: account.userId,
      sessionId: sessionId,
      success: true,
      details: const {},
    );
    return _json(statusCode, {
      'selectionRequired': false,
      'account': account.toPublicJson(),
      'accessToken': tokens.createAccessToken(context),
      'accessTokenExpiresIn': config.accessTokenDuration.inSeconds,
      'refreshToken': refreshToken,
      'refreshTokenExpiresAt': expiresAt.toIso8601String(),
    });
  }

  Future<Response> _refresh(Request request) async {
    final body = await _body(request);
    final refresh = _requiredText(body, 'refreshToken', max: 512);
    final session = await store.findSessionByRefreshHash(
      tokens.hashOpaqueToken(refresh),
    );
    if (session == null ||
        session.revoked ||
        !session.expiresAt.isAfter(DateTime.now().toUtc())) {
      return _error(
        401,
        'invalid_refresh_token',
        'Sessão expirada ou inválida.',
      );
    }
    final account = await store.findAccount(session.userId, session.businessId);
    if (account == null || !account.active) {
      return _error(401, 'inactive_account', 'Conta indisponível.');
    }
    final newRefresh = tokens.createOpaqueToken();
    final expiresAt = DateTime.now().toUtc().add(config.refreshTokenDuration);
    await store.rotateSession(
      sessionId: session.id,
      refreshHash: tokens.hashOpaqueToken(newRefresh),
      expiresAt: expiresAt,
    );
    final context = AuthContext(
      userId: account.userId,
      businessId: account.businessId,
      role: account.role,
      sessionId: session.id,
    );
    return _json(200, {
      'accessToken': tokens.createAccessToken(context),
      'accessTokenExpiresIn': config.accessTokenDuration.inSeconds,
      'refreshToken': newRefresh,
      'refreshTokenExpiresAt': expiresAt.toIso8601String(),
    });
  }

  Future<Response> _logout(Request request) async {
    final actor = _authenticate(request);
    await store.revokeSession(actor.sessionId);
    await store.audit(
      event: 'auth.logout',
      businessId: actor.businessId,
      userId: actor.userId,
      sessionId: actor.sessionId,
      success: true,
      details: const {},
    );
    return Response(204);
  }

  Future<Response> _requestPasswordReset(Request request) async {
    final body = await _body(request);
    final login = _normalizeLogin(_requiredText(body, 'login', max: 254));
    final channel = (body['channel'] as String? ?? 'email').trim();
    if (!const {'email', 'sms'}.contains(channel)) {
      throw const FormatException('Canal deve ser email ou sms.');
    }
    if (!resetNotifier.supports(channel)) {
      return _error(
        503,
        'provider_not_configured',
        'Recuperação por $channel ainda não foi configurada no servidor.',
      );
    }
    final selectedBusinessId = (body['businessId'] as String?)?.trim();
    final accounts = await store.findAccountsByLogin(login);
    final selected = selectedBusinessId == null
        ? accounts
        : accounts
              .where((account) => account.businessId == selectedBusinessId)
              .toList();
    for (final account in selected) {
      final opaque = tokens.createOpaqueToken();
      await store.createPasswordReset(
        id: _uuid.v4(),
        userId: account.userId,
        businessId: account.businessId,
        tokenHash: tokens.hashOpaqueToken(opaque),
        channel: channel,
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
      );
      final base =
          config.passwordResetBaseUrl ?? config.publicBaseUrl.toString();
      final resetUri = Uri.parse(
        base,
      ).replace(path: '/reset-password', queryParameters: {'token': opaque});
      await resetNotifier.send(
        channel: channel,
        account: account,
        resetUri: resetUri,
      );
    }
    return _json(202, {
      'message':
          'Se a conta existir, as instruções serão enviadas pelo canal escolhido.',
    });
  }

  Future<Response> _resetPassword(Request request) async {
    final body = await _body(request);
    final token = _requiredText(body, 'token', max: 512);
    final password = _requiredText(body, 'newPassword', max: 128);
    final account = await store.consumePasswordReset(
      tokenHash: tokens.hashOpaqueToken(token),
      newPasswordHash: passwords.hash(password),
    );
    if (account == null) {
      return _error(400, 'invalid_reset_token', 'Token inválido ou expirado.');
    }
    await store.audit(
      event: 'auth.password_reset',
      businessId: account.businessId,
      userId: account.userId,
      success: true,
      details: const {},
    );
    return _json(200, {'message': 'Senha atualizada. Entre novamente.'});
  }

  Future<Response> _push(Request request) async {
    final actor = _authenticate(request);
    final body = await _body(request);
    final rawOperations = body['operations'];
    if (rawOperations is! List || rawOperations.length > 100) {
      throw const FormatException('Envie de 0 a 100 operações.');
    }
    final operations = rawOperations.map((raw) {
      if (raw is! Map) throw const FormatException('Operação inválida.');
      final map = Map<String, dynamic>.from(raw);
      final operation = _requiredText(map, 'operation', max: 16);
      if (!const {'criar', 'atualizar', 'excluir'}.contains(operation)) {
        throw const FormatException('Tipo de operação inválido.');
      }
      final payload = map['payload'];
      return SyncMutation(
        operationId: _requiredText(map, 'operationId', max: 128),
        entity: _requiredText(map, 'entity', max: 80),
        entityId: _requiredText(map, 'entityId', max: 128),
        operation: operation,
        localVersion: (map['localVersion'] as num?)?.toInt() ?? 0,
        payload: payload is Map ? Map<String, Object?>.from(payload) : const {},
      );
    }).toList();
    final results = await store.applyMutations(
      actor: actor,
      mutations: operations,
    );
    final automation = automations;
    if (automation != null) {
      for (final result in results.where((item) => item.status == 'applied')) {
        final mutation = operations.firstWhere(
          (item) => item.operationId == result.operationId,
        );
        final cancelled =
            mutation.entity == 'agendamentos' &&
            (mutation.operation == 'excluir' ||
                mutation.payload['status'] == 'cancelado' ||
                mutation.payload['excluido'] == 1);
        if (cancelled) {
          await automation.cancelAppointment(
            businessId: actor.businessId,
            appointmentId: mutation.entityId,
            reason:
                mutation.payload['cancelamento_motivo']?.toString() ??
                mutation.payload['exclusao_motivo']?.toString() ??
                'Agendamento cancelado no StudioFlow.',
          );
        }
      }
    }
    return _json(200, {
      'results': results.map((result) => result.toJson()).toList(),
    });
  }

  Future<Response> _pull(Request request) async {
    final actor = _authenticate(request);
    final cursor =
        int.tryParse(request.url.queryParameters['cursor'] ?? '') ?? 0;
    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 200;
    final changes = await store.pullChanges(
      businessId: actor.businessId,
      afterCursor: cursor,
      limit: limit,
    );
    return _json(200, {
      'changes': changes.map((change) => change.toJson()).toList(),
      'nextCursor': changes.isEmpty ? cursor : changes.last.cursor,
    });
  }

  Future<Response> _catalogGtin(Request request, String gtin) async {
    final actor = _authenticate(request);
    final service = catalog;
    if (service == null) {
      return _error(
        503,
        'catalog_not_configured',
        'Catálogo externo ainda não foi configurado no servidor.',
      );
    }
    try {
      final product = await service.lookup(
        businessId: actor.businessId,
        userId: actor.userId,
        gtin: gtin,
      );
      return _json(200, {
        'found': product != null,
        'product': product?.toJson(),
        'cachePolicy': '30 dias para encontrados; 24 horas para ausentes',
        'attribution':
            'Dados: Open Beauty Facts / Open Products Facts (ODbL 1.0)',
      });
    } on FormatException catch (error) {
      return _error(400, 'invalid_gtin', error.message);
    } on Object {
      return _error(
        503,
        'catalog_temporarily_unavailable',
        'A fonte externa está temporariamente indisponível. Tente novamente ou cadastre manualmente.',
      );
    }
  }

  Future<Response> _searchOffers(Request request) async {
    _authenticate(request);
    final query = (request.url.queryParameters['q'] ?? '').trim();
    if (query.length < 2 || query.length > 120) {
      throw const FormatException(
        'Informe uma busca entre 2 e 120 caracteres.',
      );
    }
    final offers = await marketplace.searchMarketplaceOffers(query);
    return _json(200, {
      'offers': offers.map((offer) => offer.toJson()).toList(),
      'sorting': 'menor custo total; prazo como desempate',
      'disclosure':
          'Alguns links podem gerar comissão ao StudioFlow, sem alterar o preço.',
      'message': offers.isEmpty
          ? 'Nenhuma oferta real disponível. Cadastre um fornecedor ou configure um provedor autorizado.'
          : null,
    });
  }

  Future<Response> _clickOffer(Request request, String id) async {
    final actor = _authenticate(request);
    final offer = await marketplace.findMarketplaceOffer(id);
    if (offer == null) {
      throw const ApiException(404, 'offer_not_found', 'Oferta indisponível.');
    }
    final programs = await marketplace.listAffiliatePrograms();
    final program = programs
        .where((item) => item.id == offer.programId)
        .firstOrNull;
    if (program == null || !program.enabled) {
      throw const ApiException(
        409,
        'program_disabled',
        'Programa de afiliados indisponível.',
      );
    }
    final uri = Uri.tryParse(offer.url);
    if (uri == null ||
        uri.scheme != 'https' ||
        !program.allowedDomains.any(
          (domain) => uri.host == domain || uri.host.endsWith('.$domain'),
        )) {
      throw const ApiException(
        409,
        'unsafe_destination',
        'Destino da oferta não autorizado.',
      );
    }
    final clickId = _uuid.v4();
    await marketplace.recordAffiliateClick(
      id: clickId,
      businessId: actor.businessId,
      userId: actor.userId,
      offer: offer,
      destinationUrl: offer.url,
    );
    return _json(200, {
      'clickId': clickId,
      'url': offer.url,
      'affiliate': program.partnerId?.isNotEmpty == true,
      'disclosure': program.disclosure,
    });
  }

  Future<Response> _adminPrograms(Request request) async {
    _requireRolgAdmin(request);
    final programs = await marketplace.listAffiliatePrograms();
    return _json(200, {
      'programs': programs.map((item) => item.toJson()).toList(),
    });
  }

  Future<Response> _adminSaveProgram(Request request, String id) async {
    _requireRolgAdmin(request);
    final body = await _body(request);
    final domains = body['allowedDomains'];
    if (domains is! List || domains.any((item) => item is! String)) {
      throw const FormatException(
        'allowedDomains deve ser uma lista de domínios.',
      );
    }
    final cleanDomains = domains
        .cast<String>()
        .map((item) => item.trim().toLowerCase())
        .where((item) => RegExp(r'^[a-z0-9.-]+$').hasMatch(item))
        .toList();
    if (cleanDomains.length != domains.length) {
      throw const FormatException('Domínio autorizado inválido.');
    }
    final program = AffiliateProgram(
      id: id,
      name: _requiredText(body, 'name', max: 100),
      enabled: body['enabled'] == true,
      partnerId: (body['partnerId'] as String?)?.trim(),
      secretReference: (body['secretReference'] as String?)?.trim(),
      allowedDomains: cleanDomains,
      disclosure: _requiredText(body, 'disclosure', max: 300),
    );
    await marketplace.saveAffiliateProgram(program);
    return _json(200, program.toJson());
  }

  Future<Response> _adminSaveOffer(Request request, String id) async {
    _requireRolgAdmin(request);
    final body = await _body(request);
    final url = Uri.tryParse(_requiredText(body, 'url', max: 2000));
    if (url == null || url.scheme != 'https') {
      throw const FormatException('A oferta exige URL HTTPS válida.');
    }
    final price = (body['priceCents'] as num?)?.toInt() ?? -1;
    final shipping = (body['shippingCents'] as num?)?.toInt() ?? 0;
    if (price < 0 || shipping < 0) {
      throw const FormatException('Preço e frete não podem ser negativos.');
    }
    final offer = MarketplaceOffer(
      id: id,
      programId: _requiredText(body, 'programId', max: 80),
      title: _requiredText(body, 'title', max: 240),
      seller: _requiredText(body, 'seller', max: 160),
      url: url.toString(),
      priceCents: price,
      shippingCents: shipping,
      deliveryDays: (body['deliveryDays'] as num?)?.toInt(),
      currency: (body['currency'] as String? ?? 'BRL').trim().toUpperCase(),
      active: body['active'] != false,
      verifiedAt: DateTime.now().toUtc(),
    );
    await marketplace.saveMarketplaceOffer(offer);
    return _json(200, offer.toJson());
  }

  Future<Response> _adminConversion(Request request) async {
    _requireRolgAdmin(request);
    final body = await _body(request);
    final status = _requiredText(body, 'status', max: 12);
    if (!const {'estimada', 'confirmada', 'cancelada'}.contains(status)) {
      throw const FormatException('Status de comissão inválido.');
    }
    final sale = (body['saleCents'] as num?)?.toInt() ?? -1;
    final commission = (body['commissionCents'] as num?)?.toInt() ?? -1;
    if (sale < 0 || commission < 0) {
      throw const FormatException('Valores da conversão são inválidos.');
    }
    await marketplace.recordAffiliateConversion(
      id: (body['id'] as String?)?.trim() ?? _uuid.v4(),
      programId: _requiredText(body, 'programId', max: 80),
      externalId: _requiredText(body, 'externalId', max: 160),
      clickId: (body['clickId'] as String?)?.trim(),
      saleCents: sale,
      commissionCents: commission,
      status: status,
    );
    return _json(200, {'status': status});
  }

  Future<Response> _adminMetrics(Request request) async {
    _requireRolgAdmin(request);
    return _json(200, await marketplace.affiliateMetrics());
  }

  void _requireRolgAdmin(Request request) {
    final expected = config.rolgAdminKey;
    if (expected == null) {
      throw const ApiException(
        503,
        'admin_not_configured',
        'Painel ROLG não configurado no servidor.',
      );
    }
    final received = request.headers['x-rolg-admin-key'];
    if (received == null || !_constantTimeEquals(received, expected)) {
      throw const ApiException(
        403,
        'admin_forbidden',
        'Acesso administrativo negado.',
      );
    }
  }

  static bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }

  Future<Response> _messageHistory(Request request) async {
    final actor = _authenticate(request);
    final automation = automations;
    if (automation == null) {
      return _error(
        503,
        'automation_unavailable',
        'Automação de mensagens não configurada neste servidor.',
      );
    }
    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 100;
    final messages = await automation.history(actor.businessId, limit: limit);
    return _json(200, {'messages': messages.map((m) => m.toJson()).toList()});
  }

  Response _whatsappVerify(Request request) {
    final query = request.url.queryParameters;
    final valid =
        query['hub.mode'] == 'subscribe' &&
        config.whatsappVerifyToken != null &&
        query['hub.verify_token'] == config.whatsappVerifyToken;
    if (!valid) {
      return _error(403, 'invalid_verify_token', 'Verificação recusada.');
    }
    return Response.ok(
      query['hub.challenge'] ?? '',
      headers: {'content-type': 'text/plain; charset=utf-8'},
    );
  }

  Future<Response> _whatsappWebhook(Request request) async {
    final automation = automations;
    final secret = config.metaAppSecret;
    if (automation == null || secret == null) {
      return _error(
        503,
        'whatsapp_not_configured',
        'Webhook WhatsApp indisponível.',
      );
    }
    final raw = await request.readAsString();
    if (raw.length > 1024 * 1024) {
      return _error(413, 'payload_too_large', 'Corpo muito grande.');
    }
    final received = request.headers['x-hub-signature-256'] ?? '';
    final digest = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(raw));
    if (!_constantEquals(received, 'sha256=$digest')) {
      return _error(401, 'invalid_meta_signature', 'Assinatura Meta inválida.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return Response(204);
    final entries = decoded['entry'];
    if (entries is! List) return Response(204);
    for (final entry in entries.whereType<Map>()) {
      final changes = entry['changes'];
      if (changes is! List) continue;
      for (final change in changes.whereType<Map>()) {
        final value = change['value'];
        if (value is! Map) continue;
        final statuses = value['statuses'];
        if (statuses is! List) continue;
        for (final rawStatus in statuses.whereType<Map>()) {
          final id = rawStatus['id']?.toString();
          final metaStatus = rawStatus['status']?.toString();
          if (id == null || metaStatus == null) continue;
          final status = metaStatus == 'failed' ? 'error' : metaStatus;
          if (!const {'sent', 'delivered', 'read', 'error'}.contains(status)) {
            continue;
          }
          final errors = rawStatus['errors'];
          final error = errors is List && errors.isNotEmpty
              ? jsonEncode(errors.first)
              : null;
          await automation.updateDelivery(
            externalId: id,
            status: status,
            error: error,
          );
        }
      }
    }
    return Response(204);
  }

  static bool _constantEquals(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }

  Future<Response> _messageWebhook(Request request) async {
    final automation = automations;
    if (automation == null) {
      return _error(
        503,
        'automation_unavailable',
        'Automação de mensagens não configurada neste servidor.',
      );
    }
    final expected = config.automationWebhookToken;
    final received = request.headers['x-automation-webhook-token'];
    if (expected == null || received == null || received != expected) {
      return _error(401, 'invalid_webhook_token', 'Webhook não autorizado.');
    }
    final body = await _body(request);
    final externalId = _requiredText(body, 'externalId', max: 256);
    final status = _requiredText(body, 'status', max: 32);
    await automation.updateDelivery(
      externalId: externalId,
      status: status,
      error: body['error'] as String?,
    );
    return Response(204);
  }

  AuthContext _authenticate(Request request) {
    final header = request.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) {
      throw const ApiException(
        401,
        'missing_token',
        'Token de acesso obrigatório.',
      );
    }
    try {
      return tokens.verifyAccessToken(header.substring(7).trim());
    } on Object {
      throw const ApiException(
        401,
        'invalid_token',
        'Token inválido ou expirado.',
      );
    }
  }

  static Future<Map<String, dynamic>> _body(Request request) async {
    final content = await request.readAsString();
    if (content.length > 1024 * 1024) {
      throw const ApiException(413, 'payload_too_large', 'Corpo muito grande.');
    }
    final decoded = jsonDecode(content);
    if (decoded is! Map) throw const FormatException('JSON inválido.');
    return Map<String, dynamic>.from(decoded);
  }

  static String _requiredText(
    Map<String, dynamic> body,
    String key, {
    required int max,
  }) {
    final value = body[key];
    if (value is! String || value.trim().isEmpty || value.length > max) {
      throw FormatException('Campo obrigatório inválido: $key.');
    }
    return value.trim();
  }

  static String? _optionalIdentifier(Object? raw) {
    if (raw == null) return null;
    if (raw is! String || !RegExp(r'^[A-Za-z0-9_-]{8,128}$').hasMatch(raw)) {
      throw const FormatException('Identificador externo inválido.');
    }
    return raw;
  }

  static String _normalizeLogin(String value) => value.trim().toLowerCase();
}

final class ApiException implements Exception {
  final int status;
  final String code;
  final String message;

  const ApiException(this.status, this.code, this.message);
}

Middleware _securityHeaders() {
  return (innerHandler) {
    return (request) async {
      final response = await innerHandler(request);
      return response.change(
        headers: {
          ...response.headers,
          'x-content-type-options': 'nosniff',
          'x-frame-options': 'DENY',
          'referrer-policy': 'no-referrer',
          'cache-control': 'no-store',
        },
      );
    };
  };
}

Middleware _errorBoundary() {
  return (innerHandler) {
    return (request) async {
      try {
        return await innerHandler(request);
      } on ApiException catch (error) {
        return _error(error.status, error.code, error.message);
      } on FormatException catch (error) {
        return _error(400, 'invalid_request', error.message);
      } on ArgumentError catch (error) {
        return _error(400, 'invalid_argument', error.message);
      } on Object catch (error, stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
        return _error(
          500,
          'internal_error',
          'Não foi possível concluir a solicitação.',
        );
      }
    };
  };
}

Response _json(int status, Object body) {
  return Response(
    status,
    body: jsonEncode(body),
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

Response _error(int status, String code, String message) {
  return _json(status, {
    'error': {'code': code, 'message': message},
  });
}
