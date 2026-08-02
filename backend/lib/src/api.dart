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
import 'marketplace_admin_service.dart';
import 'models.dart';
import 'admin.dart';
import 'security.dart';
import 'store.dart';
import 'academy.dart';

final class StudioFlowApi {
  final BackendStore store;
  final BackendConfig config;
  final PasswordSecurity passwords;
  final TokenSecurity tokens;
  final PasswordResetNotifier resetNotifier;
  final MarketplaceService marketplace;
  final MarketplaceAdminService adminService;
  final MessageAutomationStore? automations;
  final CatalogLookupService? catalog;
  final AcademyService academy;
  final SecureRedirectService secureRedirect;
  final Uuid _uuid;

  StudioFlowApi({
    required this.store,
    required this.config,
    required this.marketplace,
    required this.adminService,
    required this.academy,
    required this.secureRedirect,
    PasswordSecurity? passwords,
    TokenSecurity? tokens,
    PasswordResetNotifier? resetNotifier,
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
      ..get('/v1/marketplace/search', _marketplaceSearch)
      ..get('/r/<clickId>', _marketplaceRedirect)
      ..get('/v1/platform-admin/partners', _adminListPartners)
      ..post('/v1/platform-admin/partners', _adminCreatePartner)
      ..get('/v1/messages/history', _messageHistory)
      ..get('/v1/catalog/gtin/<gtin>', _catalogGtin)
      ..get('/products/barcode/<barcode>', _catalogGtin)
      ..post('/v1/webhooks/messages', _messageWebhook)
      ..get('/v1/webhooks/whatsapp', _whatsappVerify)
      ..post('/v1/webhooks/whatsapp', _whatsappWebhook)
      ..get('/v1/academy/search', _academySearch)
      ..get('/v1/academy/categories', _academyCategories)
      ..get('/v1/academy/courses', _academySearch)
      ..get('/academy/r/<clickId>', _academyRedirect)
      ..get('/v1/subscriptions/status', _subscriptionStatus)
      ..post('/v1/scanner/scan', _scannerScan);
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
      businessId: actor.businessId!,
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
            businessId: actor.businessId!,
            appointmentId: mutation.entityId,
            reason:
                mutation.payload['cancelamento_motivo']?.toString() ??
                mutation.payload['exclusao_motivo']?.toString() ??
                'Agendamento cancelado no StudioFlow.',
          );
        }
      }
    }
    final catalogService = catalog;
    if (catalogService != null) {
      for (final result in results.where((item) => item.status == 'applied')) {
        final mutation = operations.firstWhere(
          (item) => item.operationId == result.operationId,
        );
        if (mutation.entity != 'catalogo_sugestao' ||
            mutation.operation == 'excluir') {
          continue;
        }
        try {
          await catalogService.contribute(
            businessId: actor.businessId!,
            userId: actor.userId,
            product: CatalogProductData.fromJson(mutation.payload),
          );
        } on FormatException {
          // A sincronização do comércio permanece válida; uma sugestão pública
          // malformada apenas deixa de alimentar o catálogo compartilhado.
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
      businessId: actor.businessId!,
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
        businessId: actor.businessId!,
        userId: actor.userId,
        gtin: gtin,
      );
      return _json(200, {
        'found': product != null,
        'source': product?.source,
        'barcode': gtin,
        'product': product?.toJson(),
        'cachePolicy': '30 dias para encontrados; 24 horas para ausentes',
        if (product?.source == 'external')
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

  Future<Response> _marketplaceSearch(Request request) async {
    final actor = _authenticate(request);
    final query = (request.url.queryParameters['q'] ?? '').trim();
    if (query.length < 2 || query.length > 120) {
      throw const FormatException('Informe uma busca entre 2 e 120 caracteres.');
    }
    await marketplace.logSearch(
      businessId: actor.businessId!,
      userId: actor.userId,
      query: query,
      source: 'app',
      cacheHit: false,
      resultsCount: 0,
      responseTimeMs: 50,
    );
    return _json(200, {
      'results': [],
      'message': 'Pesquisa de marketplace ainda em homologação na etapa 3B.3'
    });
  }

  Future<Response> _marketplaceRedirect(Request request, String clickId) async {
    try {
      final finalUrl = await marketplace.resolveRedirect(clickId);
      return Response.found(finalUrl);
    } catch (e) {
      return _error(400, 'redirect_failed', e.toString());
    }
  }

  Future<Response> _adminListPartners(Request request) async {
    await _authenticatePlatformAdmin(request);
    final partners = await marketplace.listAllPartners();
    return _json(200, {'partners': partners.map((p) => p.toJson()).toList()});
  }

  Future<Response> _adminCreatePartner(Request request) async {
    final actor = await _authenticatePlatformAdmin(request, requiredRole: 'platform_super_admin');
    final body = await _body(request);
    final p = MarketplacePartner(
      id: _uuid.v4(),
      slug: _requiredText(body, 'slug', max: 50),
      name: _requiredText(body, 'name', max: 100),
      partnerType: body['partnerType'] as String? ?? 'retailer',
      status: 'draft',
      priority: 0,
      supportsSearch: false,
      supportsDeepLink: false,
      supportsConversion: false,
      publicConfig: {},
      createdAt: DateTime.now().toUtc(),
    );
    await adminService.createPartner(actor.userId, p, ipAddressHash: 'dummy_hash');
    return _json(201, p.toJson());
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
    final messages = await automation.history(actor.businessId!, limit: limit);
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
        'Token de acesso obrigatário.',
      );
    }
    try {
      final context = tokens.verifyAccessToken(header.substring(7).trim());
      if (context.isPlatformAdmin) {
         // Fallback if a platform admin accesses regular endpoints:
         // Depending on business rules, we might allow it or block it. 
         // For now, let it pass, but typically platform admins don't use the standard app.
      }
      return context;
    } on Object {
      throw const ApiException(
        401,
        'invalid_token',
        'Token inválido ou expirado.',
      );
    }
  }

  Future<AuthContext> _authenticatePlatformAdmin(Request request, {String? requiredRole}) async {
    final context = _authenticate(request);
    
    if (!context.isPlatformAdmin) {
      throw const ApiException(403, 'forbidden', 'Acesso negado: Requer elevação administrativa.');
    }
    
    // Validate against database for active status and existence
    final admin = await (store as AdminBackendStore).findPlatformAdminByUserId(context.userId);
    if (admin == null || !admin.active) {
      throw const ApiException(403, 'forbidden', 'Conta administrativa inativa ou inexistente.');
    }
    
    if (requiredRole != null && admin.role != requiredRole && admin.role != 'platform_super_admin') {
      throw const ApiException(403, 'forbidden', 'Acesso negado: Papel insuficiente.');
    }
    
    return context;
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

  Future<Response> _academySearch(Request request) async {
    try {
      final auth = _authenticate(request);
      final query = request.url.queryParameters['q'];
      final category = request.url.queryParameters['category'];
      final pageStr = request.url.queryParameters['page'] ?? '1';
      final pageSizeStr = request.url.queryParameters['pageSize'] ?? '20';
      
      int page = int.tryParse(pageStr) ?? 1;
      int pageSize = int.tryParse(pageSizeStr) ?? 20;
      if (page < 1) page = 1;

      final results = await academy.search(auth, query, category, page, pageSize);
      return _json(200, results);
    } catch (e) {
      return _error(500, 'internal_error', 'Erro ao buscar cursos: $e');
    }
  }

  Future<Response> _academyCategories(Request request) async {
    try {
      _authenticate(request);
      final categories = await academy.store.getCategories();
      return _json(200, {
        'categories': categories.map((c) => c.toJson()).toList(),
      });
    } catch (e) {
      return _error(500, 'internal_error', 'Erro ao buscar categorias: $e');
    }
  }

  Future<Response> _academyRedirect(Request request, String clickId) async {
    try {
      final destination = await secureRedirect.processRedirect(clickId);
      return Response.found(destination);
    } on RedirectException catch (e) {
      return _error(400, 'invalid_link', e.message);
    } catch (e) {
      return _error(500, 'internal_error', 'Erro ao processar redirecionamento.');
    }
  }

  Future<Response> _subscriptionStatus(Request request) async {
    _authenticate(request);
    return _json(200, {
      'status': 'active',
      'plan': 'premium_homologation',
      'expiresAt': DateTime.now().add(const Duration(days: 365)).toUtc().toIso8601String(),
    });
  }

  Future<Response> _scannerScan(Request request) async {
    _authenticate(request);
    await _body(request);
    return _json(200, {
      'status': 'ok',
      'message': 'Scanner endpoint mocked for Sprint 1 homologation',
    });
  }
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
