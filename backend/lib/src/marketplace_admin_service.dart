import 'marketplace.dart';

class MarketplaceAdminService {
  final MarketplaceBackendStore _store;

  MarketplaceAdminService(this._store);

  Future<void> createPartner(
    String platformAdminId,
    MarketplacePartner partner, {
    String? ipAddressHash,
  }) async {
    // Basic validation
    if (partner.slug.isEmpty || partner.name.isEmpty) {
      throw Exception('Nome e slug são obrigatórios.');
    }

    // Save
    await _store.savePartner(partner);

    // Audit
    await _store.auditAdminAction(
      platformAdminId: platformAdminId,
      action: 'create_partner',
      entity: 'marketplace_partners',
      entityId: partner.id,
      afterState: partner.toJson(),
      ipAddressHash: ipAddressHash,
    );
  }

  Future<void> addDomain(
    String platformAdminId,
    MarketplacePartnerDomain domain, {
    String? ipAddressHash,
  }) async {
    if (domain.hostname.isEmpty) throw Exception('Hostname inválido.');

    await _store.saveDomain(domain);

    await _store.auditAdminAction(
      platformAdminId: platformAdminId,
      action: 'add_domain',
      entity: 'marketplace_partner_domains',
      entityId: domain.id,
      afterState: {
        'id': domain.id,
        'partnerId': domain.partnerId,
        'hostname': domain.hostname,
        'allowSubdomains': domain.allowSubdomains,
        'active': domain.active,
      },
      ipAddressHash: ipAddressHash,
    );
  }
}
