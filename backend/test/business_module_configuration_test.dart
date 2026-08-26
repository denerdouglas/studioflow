import 'package:studioflow_backend/src/memory_store.dart';
import 'package:test/test.dart';

void main() {
  test(
    'segmento e configuração de módulos sobrevivem a cadastro e login',
    () async {
      final store = MemoryBackendStore();
      const manicureJson =
          '{"version":1,"modules":["agenda","servicos","clientes"]}';
      final created = await store.createBusinessOwner(
        businessId: 'business-manicure',
        businessName: 'Manicure',
        segment: 'nailDesigner',
        userId: 'owner',
        ownerName: 'Dona',
        phone: '11999999999',
        login: 'dona@studioflow.test',
        passwordHash: 'hash',
        moduloLojaAtivo: false,
        moduloServicosAtivo: true,
        moduleConfiguration: manicureJson,
      );

      expect(created.segment, 'nailDesigner');
      expect(created.moduleConfiguration, manicureJson);
      expect(created.moduloLojaAtivo, isFalse);

      final login = (await store.findAccountsByLogin(
        'dona@studioflow.test',
      )).single;
      expect(login.moduleConfiguration, manicureJson);

      const expandedJson =
          '{"version":1,"modules":["agenda","servicos","clientes","loja"]}';
      await store.updateBusinessModules(
        businessId: created.businessId,
        moduloLojaAtivo: true,
        moduloServicosAtivo: true,
        moduleConfiguration: expandedJson,
      );
      final updated = (await store.findAccountsByLogin(
        'dona@studioflow.test',
      )).single;
      expect(updated.moduleConfiguration, expandedJson);
      expect(updated.moduloLojaAtivo, isTrue);
    },
  );
}
