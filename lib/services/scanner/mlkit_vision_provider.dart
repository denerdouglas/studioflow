import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../models/domain/scanner_product_draft.dart';
import '../../core/validation/gtin_validator.dart';
import 'scanner_coordinator.dart';

class MlKitVisionProvider implements ScannerProvider {
  @override
  Future<ScannerProductDraft?> searchBarcode(String gtin) async {
    return null; // Apenas IA/Visão, não pesquisa em banco externo
  }

  @override
  Future<ScannerProductDraft?> analyzeImage(
    String imagePath, {
    bool isFront = true,
  }) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );

      return parseRecognizedText(result.text, isFront: isFront);
    } catch (e) {
      return null;
    } finally {
      await recognizer.close();
    }
  }

  static ScannerProductDraft parseRecognizedText(
    String text, {
    bool isFront = true,
  }) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    String? codigo;
    String? referencia;
    String? nome;
    String? marca;
    double? quantidade;
    String? unidade;

    // Uma referência comercial precisa conter ao menos um dígito. Isso evita
    // classificar palavras em caixa alta (marca/material) como código.
    final referencePattern = RegExp(r'^(?=.*\d)[A-Z][A-Z0-9]{2,19}$');

    for (final line in lines) {
      final quantityMatch = RegExp(
        r'^(?:QTD(?:ADE)?\s*[:\-]?\s*)?(\d+(?:[.,]\d+)?)\s*(ML|L|G|KG|UN)?$',
        caseSensitive: false,
      ).firstMatch(line);
      if (quantityMatch != null && quantityMatch.group(2) != null) {
        quantidade ??= double.tryParse(
          quantityMatch.group(1)!.replaceAll(',', '.'),
        );
        unidade ??= quantityMatch.group(2)!.toLowerCase();
        continue;
      }
      final compact = line.replaceAll(RegExp(r'[\s-]'), '');
      if (codigo == null && GtinValidator.isValid(compact)) {
        codigo = compact;
        continue;
      }
      final lower = line.toLowerCase();
      if ((lower.startsWith('código:') ||
              lower.startsWith('codigo:') ||
              lower.startsWith('ref:') ||
              lower.startsWith('referência:')) &&
          codigo == null) {
        final candidate = line.split(':').last.trim().replaceAll(' ', '');
        if (GtinValidator.isValid(candidate)) {
          codigo = GtinValidator.normalize(candidate);
        } else if (referencePattern.hasMatch(candidate.toUpperCase())) {
          referencia = candidate;
        }
        continue;
      }
      if (referencia == null &&
          referencePattern.hasMatch(compact.toUpperCase())) {
        referencia = compact;
        continue;
      }
      if ((lower.startsWith('marca:') || lower.startsWith('fornecedor:')) &&
          marca == null) {
        marca = line.split(':').last.trim();
        continue;
      }
      if (nome == null) {
        nome = line;
      } else {
        marca ??= line;
      }
    }

    return ScannerProductDraft(
      gtin: codigo != null
          ? ScannerField(
              codigo,
              source: 'mlkit_ocr',
              confidence: ScannerConfidence.baixa,
            )
          : null,
      referenciaComercial: referencia != null
          ? ScannerField(
              referencia,
              source: 'mlkit_ocr',
              confidence: ScannerConfidence.baixa,
              reviewReason:
                  'Referência reconhecida por OCR; confira caracteres ambíguos.',
            )
          : null,
      nome: nome != null
          ? ScannerField(
              nome,
              source: 'mlkit_ocr',
              confidence: ScannerConfidence.baixa,
            )
          : null,
      marca: marca != null
          ? ScannerField(
              marca,
              source: 'mlkit_ocr',
              confidence: ScannerConfidence.baixa,
            )
          : null,
      quantidadeEmbalagem: quantidade == null
          ? null
          : ScannerField(
              quantidade,
              source: 'mlkit_ocr',
              confidence: ScannerConfidence.baixa,
              reviewReason: 'Quantidade reconhecida por OCR.',
            ),
      unidade: unidade == null
          ? null
          : ScannerField(
              unidade,
              source: 'mlkit_ocr',
              confidence: ScannerConfidence.baixa,
              reviewReason: 'Unidade reconhecida por OCR.',
            ),
    );
  }
}
