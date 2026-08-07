import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/core/enums/tipo_modalidade.dart';
import 'package:studioflow/core/utils/id_generator.dart';
import 'package:studioflow/models/domain/negocio_modalidade.dart';
import 'package:studioflow/models/domain/segmento_template.dart';
import 'package:studioflow/repositories/negocio_modalidades_repository.dart';
import 'package:studioflow/services/segmentos/segment_installer.dart';
import 'package:studioflow/services/segmentos/segment_registry.dart';

class FakeNegocioModalidadesRepository implements NegocioModalidadesRepository {
  NegocioModalidade? principalActive;
  final List<NegocioModalidade> saved = [];

  @override
  Future<NegocioModalidade?> getPrincipalActive(String businessId) async {
    return principalActive;
  }

  @override
  Future<void> save(NegocioModalidade modalidade) async {
    // Simula a falha de constraint UNIQUE se ID já existe
    if (saved.any((m) => m.id == modalidade.id)) {
      throw Exception('UNIQUE constraint failed: id');
    }
    saved.add(modalidade);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSegmentRegistry implements SegmentRegistry {
  final Map<String, SegmentoTemplate> templates = {};

  @override
  Future<SegmentoTemplate?> getTemplate(String slug) async {
    return templates[slug];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('IdGenerator', () {
    test('UuidIdGenerator gera IDs diferentes em chamadas sucessivas', () {
      final generator = const UuidIdGenerator();
      final id1 = generator.generate();
      final id2 = generator.generate();
      expect(id1, isNot(equals(id2)));
    });

    test('UuidIdGenerator possui formato válido de UUID v4', () {
      final generator = const UuidIdGenerator();
      final id = generator.generate();
      final regex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(regex.hasMatch(id), isTrue);
    });

    test(
      'FixedIdGenerator retorna sempre o mesmo ID (teste determinístico)',
      () {
        final generator = const FixedIdGenerator('fake-id-123');
        expect(generator.generate(), 'fake-id-123');
        expect(generator.generate(), 'fake-id-123');
      },
    );
  });

  group('SegmentInstaller com IdGenerator injetado', () {
    late FakeNegocioModalidadesRepository modalidadesRepo;
    late FakeSegmentRegistry registry;
    late SegmentInstaller installer;

    setUp(() {
      modalidadesRepo = FakeNegocioModalidadesRepository();
      registry = FakeSegmentRegistry();
      registry.templates['salao'] = SegmentoTemplate(
        slug: 'salao',
        nome: 'Salão',
        grupo: 'Beleza',
        payloadConfigJson: {},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      registry.templates['barbearia'] = SegmentoTemplate(
        slug: 'barbearia',
        nome: 'Barbearia',
        grupo: 'Beleza',
        payloadConfigJson: {},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    });

    test('SegmentInstaller usa o gerador injetado', () async {
      installer = SegmentInstaller(
        modalidadesRepository: modalidadesRepo,
        registry: registry,
        idGenerator: const FixedIdGenerator('id-injetado-999'),
      );

      final result = await installer.install(
        businessId: 'biz1',
        modalidadeSlug: 'salao',
        tipo: TipoModalidade.principal,
        createdBy: 'user1',
      );

      expect(result.id, 'id-injetado-999');
    });

    test(
      'Duas modalidades instaladas não colidem (SequentialIdGenerator)',
      () async {
        installer = SegmentInstaller(
          modalidadesRepository: modalidadesRepo,
          registry: registry,
          idGenerator: SequentialIdGenerator('seq-'),
        );

        final result1 = await installer.install(
          businessId: 'biz1',
          modalidadeSlug: 'salao',
          tipo: TipoModalidade.principal,
          createdBy: 'user1',
        );

        final result2 = await installer.install(
          businessId: 'biz1',
          modalidadeSlug: 'barbearia',
          tipo: TipoModalidade.secundaria,
          createdBy: 'user1',
        );

        expect(result1.id, 'seq-1');
        expect(result2.id, 'seq-2');
        expect(result1.id, isNot(equals(result2.id)));
        expect(modalidadesRepo.saved.length, 2);
      },
    );

    test(
      'Operação repetida não duplica modalidade por falha de ID (FixedIdGenerator)',
      () async {
        installer = SegmentInstaller(
          modalidadesRepository: modalidadesRepo,
          registry: registry,
          idGenerator: const FixedIdGenerator('colisao-id'),
        );

        await installer.install(
          businessId: 'biz1',
          modalidadeSlug: 'salao',
          tipo: TipoModalidade.principal,
          createdBy: 'user1',
        );

        // A segunda instalação falhará no DB simulado pois terá o mesmo ID e violará o mock.
        expect(
          () => installer.install(
            businessId: 'biz1',
            modalidadeSlug: 'barbearia',
            tipo: TipoModalidade.secundaria,
            createdBy: 'user1',
          ),
          throwsException,
        );

        expect(modalidadesRepo.saved.length, 1);
      },
    );
  });
}
