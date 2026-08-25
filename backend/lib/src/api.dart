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
import 'public_booking.dart';

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
  final Map<String, List<DateTime>> _publicRateLimits = {};

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
      ..get('/v1/public/app-config', _appConfig)
      ..post('/v1/auth/register-business', _registerBusiness)
      ..patch('/v1/auth/business/modules', _updateBusinessModules)
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
      ..get('/v1/platform-admin/offers', _adminListOffers)
      ..post('/v1/platform-admin/offers', _adminSaveOffer)
      ..post('/v1/platform-admin/offers/import-csv', _adminImportOffers)
      ..get('/v1/platform-admin/offers/export-csv', _adminExportOffers)
      ..get('/v1/platform-admin/affiliate-clicks', _adminAffiliateClicks)
      ..get('/v1/platform-admin/affiliate-demands', _adminAffiliateDemands)
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
      ..post('/v1/scanner/scan', _scannerScan)
      ..get('/v1/public/booking/<slug>', _publicBooking)
      ..get('/v1/public/booking/<slug>/services', _publicServices)
      ..get('/v1/public/booking/<slug>/professionals', _publicProfessionals)
      ..get('/v1/public/booking/<slug>/availability', _publicAvailability)
      ..post('/v1/public/booking/<slug>/appointments', _publicCreateAppointment)
      ..get('/v1/public/appointments/<token>', _publicAppointment)
      ..post(
        '/v1/public/appointments/<token>/confirm',
        _publicConfirmAppointment,
      )
      ..post('/v1/public/appointments/<token>/cancel', _publicCancelAppointment)
      ..post(
        '/v1/public/appointments/<token>/reschedule',
        _publicRescheduleAppointment,
      );
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

  Future<Response> _appConfig(Request request) async {
    return _json(200, {
      'android': {
        'latest_build': config.appLatestBuild,
        'latest_version': config.appLatestVersion,
        'min_build': config.appMinBuild,
        'force_update': config.appForceUpdate,
        'store_url': config.appStoreUrl,
        'message': config.appUpdateMessage,
      },
    });
  }

  Future<Response> _updateBusinessModules(Request request) async {
    final body = await _body(request);
    final actor = _authenticate(request);
    if (actor.businessId == null) {
      return _error(403, 'forbidden', 'Nenhum negócio associado.');
  }

    final moduloLojaAtivo = body['moduloLojaAtivo'] as bool? ?? true;
    final moduloServicosAtivo = body['moduloServicosAtivo'] as bool? ?? true;

    await store.updateBusinessModules(
      businessId: actor.businessId!,
      moduloLojaAtivo: moduloLojaAtivo,
      moduloServicosAtivo: moduloServicosAtivo,
    );

    return _json(200, {'success': true});
  }

  Future<Response> _registerBusiness(Request request) async {
    final body = await _body(request);
    final businessName = _requiredText(body, 'businessName', max: 160);
    final ownerName = _requiredText(body, 'ownerName', max: 160);
    final phone = _requiredText(body, 'phone', max: 32);
    final login = _normalizeLogin(_requiredText(body, 'login', max: 254));
    final password = _requiredText(body, 'password', max: 128);
    final segment = (body['segment'] as String? ?? 'salao').trim();
    final moduloLojaAtivo = body['moduloLojaAtivo'] as bool? ?? true;
    final moduloServicosAtivo = body['moduloServicosAtivo'] as bool? ?? true;
    final account = await store.createBusinessOwner(
      businessId: _optionalIdentifier(body['businessId']) ?? _uuid.v4(),
      businessName: businessName,
      segment: segment,
      moduloLojaAtivo: moduloLojaAtivo,
      moduloServicosAtivo: moduloServicosAtivo,
      userId: _optionalIdentifier(body['userId']) ?? _uuid.v4(),
      ownerName: ownerName,
      phone: phone,
      login: login,
      passwordHash: passwords.hash(password),
    );
    if (store case final PublicBookingStore bookingStore) {
      await bookingStore.ensurePublicBooking(
        businessId: account.businessId,
        businessName: account.businessName,
      );
    }
    await store.audit(
      event: 'auth.business_registered',
      businessId: account.businessId,
      userId: account.userId,
      success: true,
      details: const {},
    );
    return _issueSession(account, statusCode: 201);
  }

  PublicBookingStore get _bookingStore {
    final current = store;
    if (current is! PublicBookingStore) {
      throw StateError('Agendamento pÃƒÂºblico indisponÃƒÂ­vel.');
    }
    return current as PublicBookingStore;
  }

  Future<PublicBookingBusiness?> _enabledBooking(String slug) async {
    final normalized = PublicBookingSlug.normalize(slug);
    if (normalized != slug || PublicBookingSlug.reserved.contains(slug)) {
      return null;
    }
    return _bookingStore.findPublicBooking(slug);
  }

  Future<Response> _publicBooking(Request request, String slug) async {
    if (!_allowPublic(request)) {
      return _error(429, 'rate_limited', 'Tente novamente em instantes.');
    }
    final booking = await _enabledBooking(slug);
    if (booking == null) {
      return _error(
        404,
        'booking_not_found',
        'Estabelecimento nÃƒÂ£o encontrado.',
      );
    }
    return _json(200, {
      ...booking.toJson(),
      if (!booking.enabled)
        'message':
            'Agendamento online temporariamente indisponÃƒÂ­vel. Entre em contato com o estabelecimento.',
    });
  }

  Future<Response> _publicServices(Request request, String slug) =>
      _publicEntityResponse(request, slug, 'servicos');
  Future<Response> _publicProfessionals(Request request, String slug) =>
      _publicEntityResponse(request, slug, 'profissionais');

  Future<Response> _publicEntityResponse(
    Request request,
    String slug,
    String entity,
  ) async {
    if (!_allowPublic(request)) {
      return _error(429, 'rate_limited', 'Tente novamente em instantes.');
    }
    final booking = await _enabledBooking(slug);
    if (booking == null) {
      return _error(
        404,
        'booking_not_found',
        'Estabelecimento nÃƒÂ£o encontrado.',
      );
    }
    if (!booking.enabled) {
      return _error(
        503,
        'booking_disabled',
        'Agendamento online temporariamente indisponÃƒÂ­vel.',
      );
    }
    return _json(200, {
      'results': await _bookingStore.publicEntities(
        businessId: booking.businessId,
        entity: entity,
      ),
    });
  }

  Future<Response> _publicAvailability(Request request, String slug) async {
    final booking = await _enabledBooking(slug);
    if (booking == null) {
      return _error(
        404,
        'booking_not_found',
        'Estabelecimento nÃƒÂ£o encontrado.',
      );
    }
    if (!booking.enabled) {
      return _error(
        503,
        'booking_disabled',
        'Agendamento online temporariamente indisponÃƒÂ­vel.',
      );
    }
    final date = DateTime.tryParse(request.url.queryParameters['date'] ?? '');
    if (date == null) {
      return _error(400, 'invalid_date', 'Informe uma data vÃƒÂ¡lida.');
    }
    final now = DateTime.now();
    if (date.isBefore(DateTime(now.year, now.month, now.day))) {
      return _error(400, 'past_date', 'A data nÃƒÂ£o pode estar no passado.');
    }
    final serviceId = request.url.queryParameters['serviceId']?.trim();
    final professionalId = request.url.queryParameters['professionalId']
        ?.trim();
    final unitId = request.url.queryParameters['unitId']?.trim();
    if (serviceId == null || serviceId.isEmpty) {
      return _error(400, 'invalid_service', 'Informe o serviÃƒÂ§o.');
    }
    final rows = await _bookingStore.publicSchedulingRecords(
      businessId: booking.businessId,
      entities: const {
        'servicos',
        'profissionais',
        'profissional_servicos',
        'horarios_profissionais',
        'agendamentos',
        'bloqueios_agenda',
        'folgas_profissionais',
        'ferias_profissionais',
      },
    );
    final services = rows.where(
      (r) =>
          r['_entity'] == 'servicos' &&
          r['id'] == serviceId &&
          r['ativo'] != false &&
          r['ativo'] != 0,
    );
    if (services.isEmpty) {
      return _error(400, 'invalid_service', 'ServiÃƒÂ§o indisponÃƒÂ­vel.');
    }
    final duration = ((services.first['duracao_minutos'] as num?)?.toInt() ?? 0)
        .clamp(1, 480);
    DateTime? clock(Object? value) {
      final p = value?.toString().split(':');
      if (p == null || p.length < 2) return null;
      final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
      return h == null || m == null
          ? null
          : DateTime(date.year, date.month, date.day, h, m);
    }

    DateTime? stamp(Map<String, Object?> r, List<String> keys) {
      for (final k in keys) {
        final value = DateTime.tryParse(r[k]?.toString() ?? '');
        if (value != null) return value;
      }
      return null;
    }

    final professionals = rows.where((r) {
      if (r['_entity'] != 'profissionais' ||
          r['ativo'] == false ||
          r['ativo'] == 0) {
        return false;
      }
      if (professionalId?.isNotEmpty == true && r['id'] != professionalId) {
        return false;
      }
      if (unitId?.isNotEmpty == true &&
          r['unidade_id'] != null &&
          r['unidade_id'] != unitId) {
        return false;
      }
      final links = rows.where(
        (l) =>
            l['_entity'] == 'profissional_servicos' &&
            l['profissional_id'] == r['id'],
      );
      return links.isEmpty || links.any((l) => l['servico_id'] == serviceId);
    });
    final slots = <String>{};
    for (final pro in professionals) {
      for (final work in rows.where(
        (r) =>
            r['_entity'] == 'horarios_profissionais' &&
            r['profissional_id'] == pro['id'] &&
            (r['dia_semana'] as num?)?.toInt() == date.weekday &&
            (unitId?.isNotEmpty != true ||
                r['unidade_id'] == null ||
                r['unidade_id'] == unitId),
      )) {
        final open = clock(
          work['inicio'] ?? work['hora_inicio'] ?? work['horario_inicio'],
        );
        final close = clock(
          work['fim'] ?? work['hora_fim'] ?? work['horario_fim'],
        );
        if (open == null || close == null) continue;
        final pauseA = clock(work['intervalo_inicio']),
            pauseB = clock(work['intervalo_fim']);
        for (
          var slot = open;
          !slot.add(Duration(minutes: duration)).isAfter(close);
          slot = slot.add(const Duration(minutes: 15))
        ) {
          final end = slot.add(Duration(minutes: duration));
          if (slot.isBefore(now) ||
              (pauseA != null &&
                  pauseB != null &&
                  slot.isBefore(pauseB) &&
                  end.isAfter(pauseA))) {
            continue;
          }
          final busy = rows.any((r) {
            if (!const {
              'agendamentos',
              'bloqueios_agenda',
              'folgas_profissionais',
              'ferias_profissionais',
            }.contains(r['_entity'])) {
              return false;
            }
            if (r['profissional_id'] != null &&
                r['profissional_id'] != pro['id']) {
              return false;
            }
            if (unitId?.isNotEmpty == true &&
                r['unidade_id'] != null &&
                r['unidade_id'] != unitId) {
              return false;
            }
            if (r['_entity'] == 'agendamentos' &&
                (r['status'] == 'cancelado' ||
                    r['excluido'] == 1 ||
                    r['excluido'] == true)) {
              return false;
            }
            final a = stamp(r, const ['inicio', 'data_inicio', 'inicio_em']);
            final b = stamp(r, const ['fim', 'termino', 'data_fim', 'fim_em']);
            return a != null && b != null && slot.isBefore(b) && end.isAfter(a);
          });
          if (!busy) slots.add(slot.toIso8601String());
        }
      }
    }
    final result = slots.toList()..sort();
    return _json(200, {
      'date': date.toIso8601String().split('T').first,
      'serviceId': serviceId,
      'durationMinutes': duration,
      if (unitId?.isNotEmpty == true) 'unitId': unitId,
      if (professionalId?.isNotEmpty == true) 'professionalId': professionalId,
      'timezone':
          request.url.queryParameters['timezone'] ?? 'America/Sao_Paulo',
      'slots': result,
      if (result.isEmpty) 'message': 'Nenhum horÃƒÂ¡rio disponÃƒÂ­vel.',
    });
  }

  Future<Response> _publicCreateAppointment(
    Request request,
    String slug,
  ) async {
    if (!_allowPublic(request, limit: 10)) {
      return _error(
        429,
        'rate_limited',
        'Muitas tentativas. Aguarde um momento.',
      );
    }
    final booking = await _enabledBooking(slug);
    if (booking == null) {
      return _error(
        404,
        'booking_not_found',
        'Estabelecimento nÃƒÂ£o encontrado.',
      );
    }
    if (!booking.enabled) {
      return _error(
        503,
        'booking_disabled',
        'Agendamento online temporariamente indisponÃƒÂ­vel.',
      );
    }
    final body = await _body(request);
    final serviceId = _requiredText(body, 'serviceId', max: 100);
    final name = _requiredText(body, 'name', max: 160);
    final phone = _requiredText(
      body,
      'phone',
      max: 32,
    ).replaceAll(RegExp(r'\D'), '');
    if (phone.length < 10 || phone.length > 15) {
      return _error(400, 'invalid_phone', 'Informe um WhatsApp vÃƒÂ¡lido.');
    }
    final startsAt = DateTime.tryParse(
      _requiredText(body, 'startsAt', max: 40),
    );
    final endsAt = DateTime.tryParse(_requiredText(body, 'endsAt', max: 40));
    if (startsAt == null ||
        endsAt == null ||
        !endsAt.isAfter(startsAt) ||
        endsAt.difference(startsAt) > const Duration(hours: 8)) {
      return _error(400, 'invalid_slot', 'HorÃƒÂ¡rio invÃƒÂ¡lido.');
    }
    final services = await _bookingStore.publicEntities(
      businessId: booking.businessId,
      entity: 'servicos',
    );
    if (!services.any((item) => item['id'] == serviceId)) {
      return _error(400, 'invalid_service', 'ServiÃƒÂ§o indisponÃƒÂ­vel.');
    }
    final service = services.firstWhere((item) => item['id'] == serviceId);
    final duration = ((service['duracao_minutos'] as num?)?.toInt() ?? 0).clamp(
      1,
      480,
    );
    final calculatedEnd = startsAt.add(Duration(minutes: duration));
    final availabilityQuery = <String, String>{
      'date': startsAt.toIso8601String().split('T').first,
      'serviceId': serviceId,
      if ((body['professionalId'] as String?)?.trim().isNotEmpty == true)
        'professionalId': (body['professionalId'] as String).trim(),
      if ((body['unitId'] as String?)?.trim().isNotEmpty == true)
        'unitId': (body['unitId'] as String).trim(),
    };
    final idempotency = request.headers['idempotency-key']?.trim();
    if (idempotency == null ||
        idempotency.length < 8 ||
        idempotency.length > 100) {
      return _error(
        400,
        'invalid_idempotency_key',
        'Identificador da solicitaÃƒÂ§ÃƒÂ£o invÃƒÂ¡lido.',
      );
    }
    final availabilityResponse = await _publicAvailability(
      Request(
        'GET',
        Uri(
          scheme: 'http',
          host: 'localhost',
          path: '/v1/public/booking/$slug/availability',
          queryParameters: availabilityQuery,
        ),
      ),
      slug,
    );
    if (availabilityResponse.statusCode != 200) return availabilityResponse;
    final availabilityBody =
        jsonDecode(await availabilityResponse.readAsString()) as Map;
    final availableSlots = List<String>.from(availabilityBody['slots'] as List);
    // Os slots da agenda são gerados no horário local de São Paulo,
    // enquanto o navegador envia startsAt em UTC via toISOString().
    final startsAtLocal = startsAt.toUtc().subtract(const Duration(hours: 3));

    final slotDisponivel = availableSlots.any((slot) {
      final parsed = DateTime.tryParse(slot);
      if (parsed == null) return false;

      return parsed.year == startsAtLocal.year &&
          parsed.month == startsAtLocal.month &&
          parsed.day == startsAtLocal.day &&
          parsed.hour == startsAtLocal.hour &&
          parsed.minute == startsAtLocal.minute;
    });

    if (!slotDisponivel) {
      final previous = await _bookingStore.findPublicAppointmentByIdempotency(
        businessId: booking.businessId,
        idempotencyKey: idempotency,
      );
      if (previous != null) return _json(201, previous.toJson());
      return _error(
        409,
        'slot_conflict',
        'Este horÃƒÂ¡rio nÃƒÂ£o estÃƒÂ¡ mais disponÃƒÂ­vel.',
      );
    }
    final publicToken =
        _uuid.v4().replaceAll('-', '') + _uuid.v4().replaceAll('-', '');
    final tokenHash = sha256.convert(utf8.encode(publicToken)).toString();
    try {
      final appointment = await _bookingStore.createPublicAppointment(
        businessId: booking.businessId,
        idempotencyKey: idempotency,
        tokenHash: tokenHash,
        publicToken: publicToken,
        serviceId: serviceId,
        professionalId: body['professionalId'] as String?,
        unitId: body['unitId'] as String?,
        clientName: name,
        clientPhone: phone,
        notes: (body['notes'] as String?)?.trim(),
        startsAt: startsAt,
        endsAt: calculatedEnd,
      );
      await store.audit(
        event: 'public_booking.created',
        businessId: booking.businessId,
        success: true,
        details: {
          'serviceId': serviceId,
          'startsAt': startsAt.toUtc().toIso8601String(),
        },
      );
      return _json(201, appointment.toJson());
    } on StateError {
      return _error(
        409,
        'slot_conflict',
        'Este horÃƒÂ¡rio nÃƒÂ£o estÃƒÂ¡ mais disponÃƒÂ­vel.',
      );
    }
  }

  Future<Response> _publicAppointment(Request request, String token) async {
    final appointment = await _bookingStore.findPublicAppointment(
      sha256.convert(utf8.encode(token)).toString(),
    );
    return appointment == null
        ? _error(404, 'appointment_not_found', 'Agendamento nÃƒÂ£o encontrado.')
        : _json(200, appointment.toJson());
  }

  Future<Response> _publicConfirmAppointment(Request request, String token) =>
      _changePublicAppointment(token, 'confirmado');
  Future<Response> _publicCancelAppointment(Request request, String token) =>
      _changePublicAppointment(token, 'cancelado');

  Future<Response> _publicRescheduleAppointment(
    Request request,
    String token,
  ) async {
    final body = await _body(request);
    final startsAt = DateTime.tryParse(
      _requiredText(body, 'startsAt', max: 40),
    );
    final endsAt = DateTime.tryParse(_requiredText(body, 'endsAt', max: 40));
    if (startsAt == null || endsAt == null || !endsAt.isAfter(startsAt)) {
      return _error(400, 'invalid_slot', 'HorÃƒÂ¡rio invÃƒÂ¡lido.');
    }
    final value = await _bookingStore.updatePublicAppointment(
      tokenHash: sha256.convert(utf8.encode(token)).toString(),
      status: 'reagendado',
      startsAt: startsAt,
      endsAt: endsAt,
    );
    return value == null
        ? _error(404, 'appointment_not_found', 'Agendamento nÃƒÂ£o encontrado.')
        : _json(200, value.toJson());
  }

  Future<Response> _changePublicAppointment(String token, String status) async {
    final value = await _bookingStore.updatePublicAppointment(
      tokenHash: sha256.convert(utf8.encode(token)).toString(),
      status: status,
    );
    return value == null
        ? _error(404, 'appointment_not_found', 'Agendamento nÃƒÂ£o encontrado.')
        : _json(200, value.toJson());
  }

  bool _allowPublic(Request request, {int limit = 30}) {
    final key =
        request.headers['x-forwarded-for']?.split(',').first.trim() ??
        request.context['shelf.io.connection_info']?.toString() ??
        'unknown';
    final now = DateTime.now();
    final entries = _publicRateLimits.putIfAbsent(
      key,
      () => <DateTime>[],
    )..removeWhere((item) => now.difference(item) > const Duration(minutes: 1));
    if (entries.length >= limit) return false;
    entries.add(now);
    return true;
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
      return _error(401, 'invalid_credentials', 'Login ou senha invÃƒÂ¡lidos.');
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
        'O estabelecimento selecionado nÃƒÂ£o pertence a esta conta.',
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
        'SessÃƒÂ£o expirada ou invÃƒÂ¡lida.',
      );
    }
    final account = await store.findAccount(session.userId, session.businessId);
    if (account == null || !account.active) {
      return _error(401, 'inactive_account', 'Conta indisponÃƒÂ­vel.');
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
        'RecuperaÃƒÂ§ÃƒÂ£o por $channel ainda nÃƒÂ£o foi configurada no servidor.',
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
          'Se a conta existir, as instruÃƒÂ§ÃƒÂµes serÃƒÂ£o enviadas pelo canal escolhido.',
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
      return _error(
        400,
        'invalid_reset_token',
        'Token invÃƒÂ¡lido ou expirado.',
      );
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
      throw const FormatException('Envie de 0 a 100 operaÃƒÂ§ÃƒÂµes.');
    }
    final operations = rawOperations.map((raw) {
      if (raw is! Map) {
        throw const FormatException('OperaÃƒÂ§ÃƒÂ£o invÃƒÂ¡lida.');
      }
      final map = Map<String, dynamic>.from(raw);
      final operation = _requiredText(map, 'operation', max: 16);
      if (!const {'criar', 'atualizar', 'excluir'}.contains(operation)) {
        throw const FormatException('Tipo de operaÃƒÂ§ÃƒÂ£o invÃƒÂ¡lido.');
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
        if (mutation.entity == 'whatsapp_fila' &&
            mutation.operation == 'criar') {
          final payload = mutation.payload;
          try {
            await automation.enqueue(
              OutboundMessage(
                id: _uuid.v4(),
                businessId: actor.businessId!,
                kind: payload['template_id']?.toString() ?? 'whatsapp_fila',
                dedupeKey:
                    payload['idempotency_key']?.toString() ?? mutation.entityId,
                channel: 'whatsapp',
                destination: payload['destinatario']?.toString() ?? '',
                body: payload['payload'] is String
                    ? payload['payload'] as String
                    : jsonEncode(payload['payload']),
                scheduledAt: DateTime.now().toUtc(),
                status: 'queued',
                attempts: 0,
                appointmentId: payload['agendamento_id']?.toString(),
                clientId: payload['cliente_id']?.toString(),
                metadata: {'whatsapp_fila_id': mutation.entityId},
              ),
            );
          } catch (e) {
            print('Erro ao enfileirar whatsapp_fila: $e');
          }
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
          // A sincronizaÃƒÂ§ÃƒÂ£o do comÃƒÂ©rcio permanece vÃƒÂ¡lida; uma sugestÃƒÂ£o pÃƒÂºblica
          // malformada apenas deixa de alimentar o catÃƒÂ¡logo compartilhado.
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
        'CatÃƒÂ¡logo externo ainda nÃƒÂ£o foi configurado no servidor.',
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
        'A fonte externa estÃƒÂ¡ temporariamente indisponÃƒÂ­vel. Tente novamente ou cadastre manualmente.',
      );
    }
  }

  Future<Response> _marketplaceSearch(Request request) async {
    final actor = _authenticate(request);
    final query = (request.url.queryParameters['q'] ?? '').trim();
    if (query.length < 2 || query.length > 120) {
      throw const FormatException(
        'Informe uma busca entre 2 e 120 caracteres.',
      );
    }
    final started = DateTime.now();
    final offers = await marketplace.searchOffers(query);
    final results = <Map<String, Object?>>[];
    for (var index = 0; index < offers.length; index++) {
      final offer = offers[index];
      try {
        final redirect = await marketplace.generateRedirectUrl(
          userId: actor.userId,
          businessId: actor.businessId,
          partnerId: offer.partnerId,
          destinationUrl: offer.destinationUrl,
          source: request.url.queryParameters['source'] ?? 'app',
          rankingPosition: index + 1,
          rankingReason: 'catalog_match',
        );
        results.add({...offer.toJson(), 'destinationUrl': redirect});
      } on Object {
        // Links invÃ¡lidos ou fora da allowlist nunca sÃ£o exibidos.
      }
    }
    await marketplace.logSearch(
      businessId: actor.businessId!,
      userId: actor.userId,
      query: query,
      source: request.url.queryParameters['source'] ?? 'app',
      cacheHit: false,
      resultsCount: results.length,
      responseTimeMs: DateTime.now().difference(started).inMilliseconds,
    );
    if (results.isEmpty) {
      return _error(
        503,
        'affiliate_catalog_not_configured',
        'Nenhuma oferta parceira estÃ¡ cadastrada para esta pesquisa. A demanda foi registrada.',
      );
    }
    return _json(200, {'query': query, 'offers': results});
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
    final actor = await _authenticatePlatformAdmin(
      request,
      requiredRole: 'platform_super_admin',
    );
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
    await adminService.createPartner(
      actor.userId,
      p,
      ipAddressHash: 'dummy_hash',
    );
    return _json(201, p.toJson());
  }

  Future<Response> _adminListOffers(Request request) async {
    await _authenticatePlatformAdmin(request);
    final offers = await marketplace.listOffers();
    return _json(200, {
      'offers': offers.map((offer) => offer.toJson()).toList(),
    });
  }

  Future<Response> _adminSaveOffer(Request request) async {
    await _authenticatePlatformAdmin(
      request,
      requiredRole: 'marketplace_admin',
    );
    final body = await _body(request);
    final uri = Uri.tryParse(_requiredText(body, 'destinationUrl', max: 2048));
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      throw const FormatException('Link afiliado invÃ¡lido.');
    }
    final offer = MarketplaceOffer(
      id: body['id'] as String? ?? _uuid.v4(),
      partnerId: _requiredText(body, 'partnerId', max: 100),
      title: _requiredText(body, 'title', max: 200),
      seller: _requiredText(body, 'seller', max: 160),
      destinationUrl: uri.toString(),
      priceCents: (body['priceCents'] as num?)?.toInt(),
      active: body['active'] as bool? ?? true,
      verifiedAt: DateTime.now().toUtc(),
      brand: body['brand'] as String?,
      category: body['category'] as String?,
      gtin: body['gtin'] as String?,
      productCode: body['productCode'] as String?,
      keywords:
          (body['keywords'] as List?)?.whereType<String>().toList() ?? const [],
    );
    await marketplace.saveOffer(offer);
    return _json(200, offer.toJson());
  }

  Future<Response> _adminImportOffers(Request request) async {
    await _authenticatePlatformAdmin(
      request,
      requiredRole: 'marketplace_admin',
    );
    final body = await _body(request);
    final lines = const LineSplitter().convert(
      _requiredText(body, 'csv', max: 1024 * 1024),
    );
    if (lines.length < 2) throw const FormatException('CSV sem dados.');
    final header = lines.first.split(',').map((item) => item.trim()).toList();
    var imported = 0;
    for (final line in lines.skip(1).where((line) => line.trim().isNotEmpty)) {
      final values = line.split(',').map((item) => item.trim()).toList();
      final row = <String, String>{};
      for (var i = 0; i < header.length && i < values.length; i++) {
        row[header[i]] = values[i];
      }
      final uri = Uri.tryParse(row['destination_url'] ?? '');
      if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
        continue;
      }
      await marketplace.saveOffer(
        MarketplaceOffer(
          id: row['id']?.isNotEmpty == true ? row['id']! : _uuid.v4(),
          partnerId: row['partner_id'] ?? '',
          title: row['title'] ?? '',
          seller: row['seller'] ?? '',
          destinationUrl: uri.toString(),
          priceCents: int.tryParse(row['price_cents'] ?? ''),
          active: row['active'] != 'false',
          verifiedAt: DateTime.now().toUtc(),
          brand: row['brand'],
          category: row['category'],
          gtin: row['gtin'],
          productCode: row['product_code'],
          keywords: (row['keywords'] ?? '')
              .split('|')
              .where((item) => item.isNotEmpty)
              .toList(),
        ),
      );
      imported++;
    }
    return _json(200, {'imported': imported});
  }

  Future<Response> _adminExportOffers(Request request) async {
    await _authenticatePlatformAdmin(request);
    final offers = await marketplace.listOffers();
    final buffer = StringBuffer(
      'id,partner_id,title,seller,destination_url,price_cents,active\n',
    );
    for (final offer in offers) {
      String csv(String value) => '"${value.replaceAll('"', '""')}"';
      buffer.writeln(
        [
          csv(offer.id),
          csv(offer.partnerId),
          csv(offer.title),
          csv(offer.seller),
          csv(offer.destinationUrl),
          offer.priceCents ?? '',
          offer.active,
        ].join(','),
      );
    }
    return Response.ok(
      buffer.toString(),
      headers: {
        'content-type': 'text/csv; charset=utf-8',
        'content-disposition': 'attachment; filename="affiliate-products.csv"',
      },
    );
  }

  Future<Response> _adminAffiliateClicks(Request request) async {
    await _authenticatePlatformAdmin(request);
    final clicks = await marketplace.listClicks();
    return _json(200, {
      'clicks': clicks
          .map(
            (click) => {
              'id': click.id,
              'businessId': click.businessId,
              'userId': click.userId,
              'partnerId': click.partnerId,
              'status': click.clickStatus,
              'source': click.source,
              'clickedAt': click.clickedAt.toIso8601String(),
              'redirectedAt': click.redirectedAt?.toIso8601String(),
            },
          )
          .toList(),
    });
  }

  Future<Response> _adminAffiliateDemands(Request request) async {
    await _authenticatePlatformAdmin(request);
    return _json(200, {'demands': await marketplace.listSearchDemands()});
  }

  Future<Response> _messageHistory(Request request) async {
    final actor = _authenticate(request);
    final automation = automations;
    if (automation == null) {
      return _error(
        503,
        'automation_unavailable',
        'AutomaÃƒÂ§ÃƒÂ£o de mensagens nÃƒÂ£o configurada neste servidor.',
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
      return _error(403, 'invalid_verify_token', 'VerificaÃƒÂ§ÃƒÂ£o recusada.');
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
        'Webhook WhatsApp indisponÃƒÂ­vel.',
      );
    }
    final raw = await request.readAsString();
    if (raw.length > 1024 * 1024) {
      return _error(413, 'payload_too_large', 'Corpo muito grande.');
    }
    final received = request.headers['x-hub-signature-256'] ?? '';
    final digest = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(raw));
    if (!_constantEquals(received, 'sha256=$digest')) {
      return _error(
        401,
        'invalid_meta_signature',
        'Assinatura Meta invÃƒÂ¡lida.',
      );
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
        'AutomaÃƒÂ§ÃƒÂ£o de mensagens nÃƒÂ£o configurada neste servidor.',
      );
    }
    final expected = config.automationWebhookToken;
    final received = request.headers['x-automation-webhook-token'];
    if (expected == null || received == null || received != expected) {
      return _error(401, 'invalid_webhook_token', 'Webhook nÃƒÂ£o autorizado.');
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
        'Token de acesso obrigatÃƒÂ¡rio.',
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
        'Token invÃƒÂ¡lido ou expirado.',
      );
    }
  }

  Future<AuthContext> _authenticatePlatformAdmin(
    Request request, {
    String? requiredRole,
  }) async {
    final context = _authenticate(request);

    if (!context.isPlatformAdmin) {
      throw const ApiException(
        403,
        'forbidden',
        'Acesso negado: Requer elevaÃƒÂ§ÃƒÂ£o administrativa.',
      );
    }

    // Validate against database for active status and existence
    final admin = await (store as AdminBackendStore).findPlatformAdminByUserId(
      context.userId,
    );
    if (admin == null || !admin.active) {
      throw const ApiException(
        403,
        'forbidden',
        'Conta administrativa inativa ou inexistente.',
      );
    }

    if (requiredRole != null &&
        admin.role != requiredRole &&
        admin.role != 'platform_super_admin') {
      throw const ApiException(
        403,
        'forbidden',
        'Acesso negado: Papel insuficiente.',
      );
    }

    return context;
  }

  static Future<Map<String, dynamic>> _body(Request request) async {
    final content = await request.readAsString();
    if (content.length > 1024 * 1024) {
      throw const ApiException(413, 'payload_too_large', 'Corpo muito grande.');
    }
    final decoded = jsonDecode(content);
    if (decoded is! Map) throw const FormatException('JSON invÃƒÂ¡lido.');
    return Map<String, dynamic>.from(decoded);
  }

  static String _requiredText(
    Map<String, dynamic> body,
    String key, {
    required int max,
  }) {
    final value = body[key];
    if (value is! String || value.trim().isEmpty || value.length > max) {
      throw FormatException('Campo obrigatÃƒÂ³rio invÃƒÂ¡lido: $key.');
    }
    return value.trim();
  }

  static String? _optionalIdentifier(Object? raw) {
    if (raw == null) return null;
    if (raw is! String || !RegExp(r'^[A-Za-z0-9_-]{8,128}$').hasMatch(raw)) {
      throw const FormatException('Identificador externo invÃƒÂ¡lido.');
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

      final results = await academy.search(
        auth,
        query,
        category,
        page,
        pageSize,
      );
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
      return _error(
        500,
        'internal_error',
        'Erro ao processar redirecionamento.',
      );
    }
  }

  Future<Response> _subscriptionStatus(Request request) async {
    _authenticate(request);
    return _error(
      503,
      'billing_not_configured',
      'Assinaturas indisponÃƒÂ­veis: configuraÃƒÂ§ÃƒÂ£o da Google Play pendente.',
    );
  }

  Future<Response> _scannerScan(Request request) async {
    _authenticate(request);
    await _body(request);
    return _error(
      503,
      'scanner_http_unavailable',
      'O scanner funciona localmente no aplicativo; processamento HTTP nÃƒÂ£o estÃƒÂ¡ configurado.',
    );
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
          'NÃƒÂ£o foi possÃƒÂ­vel concluir a solicitaÃƒÂ§ÃƒÂ£o.',
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
