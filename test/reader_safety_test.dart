import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/core/validation/gtin_validator.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/scanner_product_draft.dart';
import 'package:studioflow/services/product_lookup_service.dart';
import 'package:studioflow/services/scanner/mlkit_vision_provider.dart';
import 'package:studioflow/services/scanner/scanner_coordinator.dart';
import 'package:studioflow/services/vision_ocr_service.dart';

void main() {
  sqfliteFfiInit();

  group('GTIN centralizado', () {
    const valid = <String>[
      '96385074',
      '036000291452',
      '7894900011517',
      '12345678901231',
    ];
    const invalid = <String>[
      '96385075',
      '036000291453',
      '7894900011518',
      '12345678901232',
    ];

    test('valida EAN-8, GTIN-12, EAN-13 e GTIN-14 pelo dígito', () {
      for (final code in valid) {
        expect(GtinValidator.isValid(code), isTrue, reason: code);
      }
      for (final code in invalid) {
        expect(GtinValidator.isValid(code), isFalse, reason: code);
      }
      expect(GtinValidator.isValid('12345678'), isFalse);
    });

    test('correspondência exige GTIN válido e idêntico', () {
      expect(
        GtinValidator.isExactMatch('7894900011517', '7894900011517'),
        isTrue,
      );
      expect(
        GtinValidator.isExactMatch('7894900011517', '036000291452'),
        isFalse,
      );
      expect(GtinValidator.isExactMatch('7894900011517', ''), isFalse);
    });
  });

  group('catálogo seguro', () {
    late Database db;
    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 40,
          onCreate: DatabaseSchemaLatest.criar,
        ),
      );
    });
    tearDown(() => db.close());

    Future<ProductLookupResult> lookup(CatalogProduct? product) {
      return ProductLookupService(
        databaseProvider: () async => db,
        providers: [
          MockProductCatalogProvider(
            product == null ? const {} : {'7894900011517': product},
          ),
        ],
      ).lookup('7894900011517', commerceId: 'commerce');
    }

    test('aceita somente retorno com GTIN exato', () async {
      final result = await lookup(
        const CatalogProduct(
          gtin: '7894900011517',
          name: 'Produto exato',
          source: 'test',
        ),
      );
      expect(result.product?.name, 'Produto exato');
    });

    test('rejeita GTIN diferente, ausente, aproximado e inexistente', () async {
      final different = await lookup(
        const CatalogProduct(
          gtin: '036000291452',
          name: 'Produto errado',
          source: 'test',
        ),
      );
      expect(different.product, isNull);

      final missing = await lookup(
        const CatalogProduct(gtin: '', name: 'Sem GTIN', source: 'test'),
      );
      expect(missing.product, isNull);

      final approximate = await lookup(
        const CatalogProduct(
          gtin: '7894900011517',
          name: 'Aproximado',
          source: 'test',
          exactMatch: false,
        ),
      );
      expect(approximate.product, isNull);
      expect((await lookup(null)).product, isNull);
    });
  });

  group('OCR revisável', () {
    test('converte preços brasileiros sem deslocar casas decimais', () {
      expect(VisionOcrService.parseText('R\$ 89,00').preco, 89.0);
      expect(VisionOcrService.parseText('R\$ 1.299,90').preco, 1299.90);
    });

    test('separa quantidade e volume para revisão', () {
      final draft = MlKitVisionProvider.parseRecognizedText('500 ml');
      expect(draft.quantidadeEmbalagem?.value, 500);
      expect(draft.unidade?.value, 'ml');
      expect(draft.exigeRevisaoHumana, isTrue);
    });

    test('preserva referência alfanumérica sem transformá-la em GTIN', () {
      final draft = MlKitVisionProvider.parseRecognizedText(
        'REF: R00018\nProduto teste',
      );
      expect(draft.gtin, isNull);
      expect(draft.referenciaComercial?.value, 'R00018');
      expect(draft.exigeRevisaoHumana, isTrue);
    });

    test('sequência inválida não vira GTIN e GTIN real é reconhecido', () {
      final invalid = MlKitVisionProvider.parseRecognizedText('12345678');
      expect(invalid.gtin, isNull);
      final valid = MlKitVisionProvider.parseRecognizedText('7894900011517');
      expect(valid.gtin?.value, '7894900011517');
    });

    test('caracteres ambíguos são preservados e exigem revisão', () {
      for (final value in ['R00O18', 'R00I18', 'R00S18', 'R00B18', 'R00Z18']) {
        final draft = MlKitVisionProvider.parseRecognizedText('REF: $value');
        expect(draft.referenciaComercial?.value, value);
        expect(draft.exigeRevisaoHumana, isTrue);
      }
    });

    test('merge complementa vazios e não perde campos', () {
      final merged = ScannerCoordinator.mergeDrafts(
        const ScannerProductDraft(
          nome: ScannerField('Produto', confidence: ScannerConfidence.alta),
          quantidadeEmbalagem: ScannerField(
            500,
            confidence: ScannerConfidence.alta,
          ),
        ),
        const ScannerProductDraft(
          marca: ScannerField('Marca', confidence: ScannerConfidence.alta),
          unidade: ScannerField('ml', confidence: ScannerConfidence.alta),
        ),
      );
      expect(merged.nome?.value, 'Produto');
      expect(merged.marca?.value, 'Marca');
      expect(merged.quantidadeEmbalagem?.value, 500);
      expect(merged.unidade?.value, 'ml');
    });

    test('merge preserva frente e sinaliza conflito', () {
      final merged = ScannerCoordinator.mergeDrafts(
        const ScannerProductDraft(
          nome: ScannerField('Frente', confidence: ScannerConfidence.alta),
        ),
        const ScannerProductDraft(
          nome: ScannerField('Verso', confidence: ScannerConfidence.alta),
        ),
      );
      expect(merged.nome?.value, 'Frente');
      expect(
        merged.reviewReasons,
        contains('Nome diverge entre frente e verso.'),
      );
      expect(merged.exigeRevisaoHumana, isTrue);
    });
  });
}
