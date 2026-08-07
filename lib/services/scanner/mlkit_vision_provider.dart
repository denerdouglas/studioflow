import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../models/domain/scanner_product_draft.dart';
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

      return _parseText(result.text, isFront);
    } catch (e) {
      return null;
    } finally {
      await recognizer.close();
    }
  }

  ScannerProductDraft _parseText(String text, bool isFront) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    String? codigo;
    String? nome;
    String? marca;

    final codePattern = RegExp(r'^\d{4,14}$');

    for (final line in lines) {
      final compact = line.replaceAll(RegExp(r'[\s-]'), '');
      if (codigo == null && codePattern.hasMatch(compact)) {
        codigo = compact;
        continue;
      }
      final lower = line.toLowerCase();
      if ((lower.startsWith('código:') ||
              lower.startsWith('codigo:') ||
              lower.startsWith('ref:') ||
              lower.startsWith('referência:')) &&
          codigo == null) {
        final candidate = line.split(':').last.replaceAll(RegExp(r'\D'), '');
        if (codePattern.hasMatch(candidate)) codigo = candidate;
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
    );
  }
}
