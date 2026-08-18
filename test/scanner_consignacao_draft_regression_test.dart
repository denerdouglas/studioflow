import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/models/domain/scanner_product_draft.dart';
import 'package:studioflow/repositories/acesso_repository.dart';
import 'package:studioflow/repositories/consignacao_conferencia_repository.dart';
import 'package:studioflow/repositories/consignacao_repository.dart';
import 'package:studioflow/repositories/loja_repository.dart';
import 'package:studioflow/services/bip_context_service.dart';
import 'package:studioflow/services/session_controller.dart';
import 'package:studioflow/services/vision_ocr_service.dart';

typedef ResolveCode =
    Future<ConsignacaoResolveResult> Function(
      String conferenciaId,
      String code,
    );

Future<String?> processContinuousResult(
  ScannerResult result,
  String conferenciaId,
  ResolveCode resolveCode,
) async {
  final draft = result.draft ?? const ScannerProductDraft();
  final code =
      draft.referenciaComercial?.value ?? draft.gtin?.value ?? draft.qr?.value;
  if (code == null) return 'Código inválido.';

  final resolved = await resolveCode(conferenciaId, code);
  return switch (resolved.state) {
    ConsignacaoResolveState.naoEncontrada => 'Produto não encontrado.',
    ConsignacaoResolveState.outraRemessa => 'Item não pertence a esta remessa.',
    ConsignacaoResolveState.jaConferida => 'Item já conferido.',
    ConsignacaoResolveState.statusInvalido =>
      'Peça não está disponível (status: ${resolved.peca?['status']}).',
    ConsignacaoResolveState.multiplas ||
    ConsignacaoResolveState.encontrada => null,
  };
}

void main() {
  sqfliteFfiInit();

  test('ScannerResult.existente preserva produto e draft simultaneamente', () {
    final product = Object();
    const draft = ScannerProductDraft(
      referenciaComercial: ScannerField('526839', source: 'manual'),
    );

    final result = ScannerResult.existente(product, draft: draft);

    expect(result.produto, same(product));
    expect(result.draft, same(draft));
    expect(result.draft!.referenciaComercial!.value, '526839');
  });

  group('regressão 526839 no scanner contínuo de consignação', () {
    late Database db;
    late UsuarioAcesso user;
    late LojaRepository lojaRepository;
    late ConsignacaoConferenciaRepository conferenceRepository;
    late String remessaId;
    late String outraRemessaId;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 40,
          onCreate: DatabaseSchemaLatest.criar,
        ),
      );
      user = await AcessoRepository(databaseProvider: () async => db)
          .cadastrarComercio(
            const CadastroComercioEntrada(
              nomeComercio: 'Consignação Scanner',
              nomeExibicao: 'Consignação Scanner',
              responsavel: 'Responsável',
              telefone: '11999999999',
              email: 'scanner-consignacao@teste.local',
              senha: 'Senha@123',
              permanecerConectado: false,
            ),
          );
      SessionController.instance.entrar(user);
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('fornecedores', {
        'id': 'fornecedor_scanner',
        'comercio_id': user.comercioId,
        'nome': 'Fornecedor Scanner',
        'ativo': 1,
        'criado_em': now,
        'atualizado_em': now,
      });

      final consignacaoRepository = ConsignacaoRepository(
        databaseProvider: () async => db,
      );
      remessaId = await consignacaoRepository.receberMaleta(
        fornecedorId: 'fornecedor_scanner',
        nomeLote: 'Remessa 526839',
        pecas: const [
          {
            'codigo': '526839',
            'nome': 'Brinco',
            'preco': 19.0,
            'quantidade': 1,
          },
          {
            'codigo': 'DUPLICADO',
            'nome': 'Brinco duplicado',
            'preco': 20.0,
            'quantidade': 2,
          },
        ],
      );
      outraRemessaId = await consignacaoRepository.receberMaleta(
        fornecedorId: 'fornecedor_scanner',
        nomeLote: 'Outra remessa',
        pecas: const [
          {
            'codigo': 'OUTRA-REMESSA',
            'nome': 'Colar',
            'preco': 30.0,
            'quantidade': 1,
          },
        ],
      );
      lojaRepository = LojaRepository(databaseProvider: () async => db);
      conferenceRepository = ConsignacaoConferenciaRepository(
        databaseProvider: () async => db,
        comercioId: user.comercioId,
        usuarioId: user.id,
      );
    });

    tearDown(() async {
      await db.close();
    });

    Future<ScannerResult> resolveAsVisionScanner(
      ScannerProductDraft draft,
    ) async {
      final resolved = await BipContextService(
        repository: lojaRepository,
      ).resolve(draft);
      expect(resolved.kind, BipItemKind.pecaConsignada);
      expect(resolved.product, isNotNull);
      return ScannerResult.existente(resolved.product!, draft: draft);
    }

    test(
      'BipContextService mantém 526839 no resultado existente e na Nova Venda',
      () async {
        const draft = ScannerProductDraft(
          referenciaComercial: ScannerField('526839', source: 'manual'),
        );

        final result = await resolveAsVisionScanner(draft);

        expect(result.produto, isNotNull);
        expect(result.draft, isNotNull);
        expect(result.draft!.referenciaComercial!.value, '526839');
        expect(result.produto.nome, 'Brinco');
        expect(result.produto.precoVenda, 19.0);
      },
    );

    test('manual, OCR e barcode entregam 526839 ao modo contínuo', () async {
      final ocr = VisionOcrService.parseText('526839\nBrinco\nR\$ 19,00');
      final drafts = <ScannerProductDraft>[
        const ScannerProductDraft(
          referenciaComercial: ScannerField('526839', source: 'manual'),
        ),
        ScannerProductDraft(
          referenciaComercial: ScannerField(ocr.codigo, source: 'ocr'),
        ),
        const ScannerProductDraft(
          referenciaComercial: ScannerField('526839', source: 'barcode'),
        ),
      ];
      final conferenceId = await conferenceRepository.iniciar(
        remessaId: remessaId,
        finalidade: 'inventario',
      );

      for (final draft in drafts) {
        final result = await resolveAsVisionScanner(draft);
        String? receivedCode;
        final message = await processContinuousResult(result, conferenceId, (
          id,
          code,
        ) {
          receivedCode = code;
          return conferenceRepository.resolverCodigo(id, code);
        });

        expect(result.produto, isNotNull);
        expect(result.draft, isNotNull);
        expect(result.draft!.referenciaComercial!.value, '526839');
        expect(receivedCode, '526839');
        expect(message, isNull);
        expect(message, isNot('Código inválido.'));
      }
    });

    test(
      'já conferido, outra remessa e múltiplas peças mantêm os resultados',
      () async {
        final conferenceId = await conferenceRepository.iniciar(
          remessaId: remessaId,
          finalidade: 'inventario',
        );
        const draft = ScannerProductDraft(
          referenciaComercial: ScannerField('526839', source: 'barcode'),
        );
        final result = await resolveAsVisionScanner(draft);
        final firstResolve = await conferenceRepository.resolverCodigo(
          conferenceId,
          '526839',
        );
        await conferenceRepository.conferirPeca(
          conferenciaId: conferenceId,
          pecaId: firstResolve.peca!['id'] as String,
          leituraOriginal: '526839',
        );

        expect(
          await processContinuousResult(
            result,
            conferenceId,
            conferenceRepository.resolverCodigo,
          ),
          'Item já conferido.',
        );

        const otherDraft = ScannerProductDraft(
          referenciaComercial: ScannerField('OUTRA-REMESSA', source: 'manual'),
        );
        final otherResult = await resolveAsVisionScanner(otherDraft);
        expect(
          await processContinuousResult(
            otherResult,
            conferenceId,
            conferenceRepository.resolverCodigo,
          ),
          'Item não pertence a esta remessa.',
        );

        final multiple = await conferenceRepository.resolverCodigo(
          conferenceId,
          'DUPLICADO',
        );
        expect(multiple.state, ConsignacaoResolveState.multiplas);
        expect(multiple.multiplasOpcoes, hasLength(2));

        expect(outraRemessaId, isNot(remessaId));
      },
    );
  });
}
