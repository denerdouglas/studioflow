import 'package:postgres/postgres.dart';
import 'marketplace.dart';

final class MarketplacePostgresStore implements MarketplaceBackendStore {
  final Pool _pool;

  MarketplacePostgresStore(this._pool);

  @override
  Future<List<MarketplacePartner>> listActivePartners() async {
    final result = await _pool.execute(
      Sql.named('SELECT * FROM marketplace_partners WHERE status = @status'),
      parameters: {'status': 'active'},
    );
    return result.map(_mapPartner).toList();
  }

  @override
  Future<List<MarketplacePartner>> listAllPartners() async {
    final result = await _pool.execute('SELECT * FROM marketplace_partners');
    return result.map(_mapPartner).toList();
  }

  @override
  Future<MarketplacePartner?> findPartnerById(String id) async {
    final result = await _pool.execute(
      Sql.named('SELECT * FROM marketplace_partners WHERE id = @id'),
      parameters: {'id': id},
    );
    if (result.isEmpty) return null;
    return _mapPartner(result.single);
  }

  @override
  Future<void> savePartner(MarketplacePartner partner) async {
    await _pool.execute(
      Sql.named('''
        INSERT INTO marketplace_partners (
          id, slug, name, logo, partner_type, status, priority, affiliate_identifier, 
          url_template, supports_search, supports_deep_link, supports_conversion, 
          secret_encrypted, secret_key_version, public_config, notes, created_at
        ) VALUES (
          @id, @slug, @name, @logo, @type, @status, @priority, @affiliateId, 
          @template, @search, @deepLink, @conversion, @secret, @version, 
          @config, @notes, @createdAt
        )
        ON CONFLICT (id) DO UPDATE SET
          slug = EXCLUDED.slug,
          name = EXCLUDED.name,
          logo = EXCLUDED.logo,
          partner_type = EXCLUDED.partner_type,
          status = EXCLUDED.status,
          priority = EXCLUDED.priority,
          affiliate_identifier = EXCLUDED.affiliate_identifier,
          url_template = EXCLUDED.url_template,
          supports_search = EXCLUDED.supports_search,
          supports_deep_link = EXCLUDED.supports_deep_link,
          supports_conversion = EXCLUDED.supports_conversion,
          secret_encrypted = EXCLUDED.secret_encrypted,
          secret_key_version = EXCLUDED.secret_key_version,
          public_config = EXCLUDED.public_config,
          notes = EXCLUDED.notes
      '''),
      parameters: {
        'id': partner.id,
        'slug': partner.slug,
        'name': partner.name,
        'logo': partner.logo,
        'type': partner.partnerType,
        'status': partner.status,
        'priority': partner.priority,
        'affiliateId': partner.affiliateIdentifier,
        'template': partner.urlTemplate,
        'search': partner.supportsSearch,
        'deepLink': partner.supportsDeepLink,
        'conversion': partner.supportsConversion,
        'secret': partner.secretEncrypted,
        'version': partner.secretKeyVersion,
        'config': partner.publicConfig,
        'notes': partner.notes,
        'createdAt': partner.createdAt,
      },
    );
  }

  @override
  Future<List<MarketplacePartnerDomain>> listDomainsForPartner(
    String partnerId,
  ) async {
    final result = await _pool.execute(
      Sql.named(
        'SELECT * FROM marketplace_partner_domains WHERE partner_id = @id',
      ),
      parameters: {'id': partnerId},
    );
    return result.map((row) {
      final m = row.toColumnMap();
      return MarketplacePartnerDomain(
        id: m['id'] as String,
        partnerId: m['partner_id'] as String,
        hostname: m['hostname'] as String,
        allowSubdomains: m['allow_subdomains'] as bool,
        active: m['active'] as bool,
        createdAt: m['created_at'] as DateTime,
      );
    }).toList();
  }

  @override
  Future<void> saveDomain(MarketplacePartnerDomain domain) async {
    await _pool.execute(
      Sql.named('''
        INSERT INTO marketplace_partner_domains (id, partner_id, hostname, allow_subdomains, active, created_at)
        VALUES (@id, @partnerId, @hostname, @allow, @active, @createdAt)
        ON CONFLICT (id) DO UPDATE SET
          hostname = EXCLUDED.hostname,
          allow_subdomains = EXCLUDED.allow_subdomains,
          active = EXCLUDED.active
      '''),
      parameters: {
        'id': domain.id,
        'partnerId': domain.partnerId,
        'hostname': domain.hostname,
        'allow': domain.allowSubdomains,
        'active': domain.active,
        'createdAt': domain.createdAt,
      },
    );
  }

  @override
  Future<void> logSearch({
    required String? businessId,
    required String userId,
    required String query,
    required String source,
    required bool cacheHit,
    required int resultsCount,
    required int responseTimeMs,
  }) async {
    await _pool.execute(
      Sql.named('''
        INSERT INTO marketplace_search_logs (business_id, user_id, query, source, cache_hit, results_count, response_time_ms)
        VALUES (@business, @user, @query, @source, @cache, @results, @time)
      '''),
      parameters: {
        'business': businessId,
        'user': userId,
        'query': query,
        'source': source,
        'cache': cacheHit,
        'results': resultsCount,
        'time': responseTimeMs,
      },
    );
  }

  @override
  Future<void> recordClick(MarketplaceClick click) async {
    await _pool.execute(
      Sql.named('''
        INSERT INTO marketplace_clicks (
          id, business_id, user_id, partner_id, destination_url, click_status, source, 
          campaign_id, user_agent_hash, ip_hash, ranking_position, ranking_reason, clicked_at, expires_at
        ) VALUES (
          @id, @business, @user, @partner, @url, @status, @source, 
          @campaign, @ua, @ip, @rankPos, @rankReas, @clicked, @expires
        )
      '''),
      parameters: {
        'id': click.id,
        'business': click.businessId,
        'user': click.userId,
        'partner': click.partnerId,
        'url': click.destinationUrl,
        'status': click.clickStatus,
        'source': click.source,
        'campaign': click.campaignId,
        'ua': click.userAgentHash,
        'ip': click.ipHash,
        'rankPos': click.rankingPosition,
        'rankReas': click.rankingReason,
        'clicked': click.clickedAt,
        'expires': click.expiresAt,
      },
    );
  }

  @override
  Future<MarketplaceClick?> findClick(String id) async {
    final result = await _pool.execute(
      Sql.named('SELECT * FROM marketplace_clicks WHERE id = @id'),
      parameters: {'id': id},
    );
    if (result.isEmpty) return null;
    final m = result.single.toColumnMap();
    return MarketplaceClick(
      id: m['id'] as String,
      businessId: m['business_id'] as String?,
      userId: m['user_id'] as String,
      partnerId: m['partner_id'] as String,
      destinationUrl: m['destination_url'] as String,
      clickStatus: m['click_status'] as String,
      source: m['source'] as String?,
      campaignId: m['campaign_id'] as String?,
      userAgentHash: m['user_agent_hash'] as String?,
      ipHash: m['ip_hash'] as String?,
      rankingPosition: m['ranking_position'] as int?,
      rankingReason: m['ranking_reason'] as String?,
      clickedAt: m['clicked_at'] as DateTime,
      redirectedAt: m['redirected_at'] as DateTime?,
      expiresAt: m['expires_at'] as DateTime?,
    );
  }

  @override
  Future<void> updateClickStatus(
    String id,
    String status, {
    DateTime? redirectedAt,
  }) async {
    await _pool.execute(
      Sql.named('''
        UPDATE marketplace_clicks 
        SET click_status = @status, 
            redirected_at = COALESCE(@redirected, redirected_at) 
        WHERE id = @id
      '''),
      parameters: {'id': id, 'status': status, 'redirected': redirectedAt},
    );
  }

  @override
  Future<void> auditAdminAction({
    required String platformAdminId,
    required String action,
    required String entity,
    required String entityId,
    Map<String, dynamic>? beforeState,
    Map<String, dynamic>? afterState,
    String? reason,
    String? ipAddressHash,
  }) async {
    await _pool.execute(
      Sql.named('''
        INSERT INTO marketplace_admin_audit (platform_admin_id, action, entity, entity_id, before_state, after_state, reason, ip_address_hash)
        VALUES (@admin, @action, @entity, @entityId, @before, @after, @reason, @ip)
      '''),
      parameters: {
        'admin': platformAdminId,
        'action': action,
        'entity': entity,
        'entityId': entityId,
        'before': beforeState,
        'after': afterState,
        'reason': reason,
        'ip': ipAddressHash,
      },
    );
  }

  MarketplacePartner _mapPartner(ResultRow row) {
    final m = row.toColumnMap();
    return MarketplacePartner(
      id: m['id'] as String,
      slug: m['slug'] as String,
      name: m['name'] as String,
      logo: m['logo'] as String?,
      partnerType: m['partner_type'] as String,
      status: m['status'] as String,
      priority: m['priority'] as int,
      affiliateIdentifier: m['affiliate_identifier'] as String?,
      urlTemplate: m['url_template'] as String?,
      supportsSearch: m['supports_search'] as bool,
      supportsDeepLink: m['supports_deep_link'] as bool,
      supportsConversion: m['supports_conversion'] as bool,
      secretEncrypted: m['secret_encrypted'] as String?,
      secretKeyVersion: m['secret_key_version'] as String?,
      publicConfig: m['public_config'] as Map<String, dynamic>? ?? {},
      notes: m['notes'] as String?,
      createdAt: m['created_at'] as DateTime,
    );
  }
}
