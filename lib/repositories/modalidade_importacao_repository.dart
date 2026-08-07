import 'package:sqflite/sqflite.dart';
import '../database/database_service.dart';
import '../services/session_controller.dart';
import '../core/utils/id_generator.dart';
import 'segmento_templates_repository.dart';

class ModalidadeImportacaoRepository {
  final DatabaseService _databaseService;
  final SegmentoTemplatesRepository _templatesRepository;

  ModalidadeImportacaoRepository({
    DatabaseService? databaseService,
    SegmentoTemplatesRepository? templatesRepository,
  }) : _databaseService = databaseService ?? DatabaseService.instance,
       _templatesRepository =
           templatesRepository ?? SegmentoTemplatesRepository();

  String get _comercioId => SessionController.instance.usuario!.comercioId;

  Future<void> importar(String slug) async {
    final template = await _templatesRepository.getBySlug(slug);
    if (template == null) throw Exception('Template não encontrado');

    final db = await _databaseService.database;
    final agora = DateTime.now().toUtc().toIso8601String();
    final config = template.payloadConfigJson;

    await db.transaction((txn) async {
      // 1. Cria a modalidade
      final modalidadeId = 'mod_${IdGenerator.temporal()}';
      await txn.insert('modalidades_estabelecimento', {
        'id': modalidadeId,
        'comercio_id': _comercioId,
        'nome': template.nome,
        'nome_normalizado': template.nome.toLowerCase().replaceAll(' ', '_'),
        'ativa': 1,
        'exibir_home': 1,
        'created_at': agora,
        'updated_at': agora,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      // 2. Importa profissionais (mantido por retrocompatibilidade se a config possuir)
      final profissionais = config['profissionais'] as List? ?? [];
      if (profissionais.isNotEmpty) {
        final existingProfsRows = await txn.query(
          'profissionais',
          where: 'comercio_id = ?',
          whereArgs: [_comercioId],
        );
        final existingProfs = {
          for (var row in existingProfsRows)
            (row['nome'] as String).toLowerCase().replaceAll(
              RegExp(r'\s+'),
              '_',
            ): row['id'] as String,
        };
        for (final p in profissionais) {
          final normalizedName = (p['nome'] as String).toLowerCase().replaceAll(
            RegExp(r'\s+'),
            '_',
          );
          String profId;
          if (existingProfs.containsKey(normalizedName)) {
            profId = existingProfs[normalizedName]!;
          } else {
            profId = 'prof_${IdGenerator.temporal()}';
            await txn.insert('profissionais', {
              'id': profId,
              'comercio_id': _comercioId,
              'nome': p['nome'],
              'whatsapp': '',
              'cargo': p['cargo'],
              'percentual_comissao': p['comissao'],
              'ativo': 1,
              'data_cadastro': agora,
            });
          }
          await txn.insert(
            'modalidade_profissionais',
            {
              'comercio_id': _comercioId,
              'profissional_id': profId,
              'modalidade_id': modalidadeId,
              'criado_em': agora,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      // 3. Importa serviços usando nome normalizado para deduplicação
      final servicos = config['servicos'] as List? ?? [];
      final existingServicosRows = await txn.query(
        'servicos',
        where: 'comercio_id = ?',
        whereArgs: [_comercioId],
      );
      final existingServicos = {
        for (var row in existingServicosRows)
          (row['nome'] as String).toLowerCase().replaceAll(RegExp(r'\s+'), '_'):
              row['id'] as String,
      };

      for (final s in servicos) {
        final normalizedName = (s['nome'] as String).toLowerCase().replaceAll(
          RegExp(r'\s+'),
          '_',
        );
        String servId;

        if (existingServicos.containsKey(normalizedName)) {
          servId = existingServicos[normalizedName]!;
        } else {
          servId = 'serv_${IdGenerator.temporal()}';
          await txn.insert('servicos', {
            'id': servId,
            'comercio_id': _comercioId,
            'nome': s['nome'],
            'categoria': s['categoria'],
            'preco': s['preco'],
            'duracao_minutos': s['duracao_minutos'],
            'ativo': 1,
            'data_cadastro': agora,
          });
        }

        await txn.insert('modalidade_servicos', {
          'comercio_id': _comercioId,
          'servico_id': servId,
          'modalidade_id': modalidadeId,
          'criado_em': agora,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }
}
