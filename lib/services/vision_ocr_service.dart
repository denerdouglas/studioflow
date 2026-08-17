import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../core/validation/gtin_validator.dart';

enum ExtractedCodeKind { gtin, referenciaComercial, codigoInterno }

class ExtractedTagData {
  final String? codigo;
  final String? nome;
  final String? fornecedor;
  final String? descricao;
  final String? material;
  final double? preco;
  final ExtractedCodeKind? codigoTipo;
  final bool precisaRevisao;

  const ExtractedTagData({
    this.codigo,
    this.nome,
    this.fornecedor,
    this.descricao,
    this.material,
    this.preco,
    this.codigoTipo,
    this.precisaRevisao = false,
  });
}

class VisionOcrService {
  static Future<String> recognizeText(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      return result.text;
    } finally {
      await recognizer.close();
    }
  }

  static Future<ExtractedTagData> processImage(String imagePath) async {
    return parseText(await recognizeText(imagePath));
  }

  static ExtractedTagData parseText(String text) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    String? codigo;
    double? preco;
    String? nome;
    String? fornecedor;
    String? descricao;
    String? material;
    ExtractedCodeKind? codigoTipo;
    var precisaRevisao = false;

    final pricePattern = RegExp(
      r'(?:R\$|RS|\$)\s*([0-9]{1,3}(?:[.,][0-9]{3})+(?:[,.][0-9]{2})?|[0-9]{1,6}(?:[,.][0-9]{2})?)',
      caseSensitive: false,
    );
    final plainMoneyPattern = RegExp(r'^([0-9]{1,3}(?:[.,][0-9]{3})*)[,.]([0-9]{2})$');
    final codePattern = RegExp(r'^[A-Z0-9]{4,20}$', caseSensitive: false);
    final materialPattern = RegExp(
      r'\b(prata|ouro|aço|aco|folheado|banhado|algodão|algodao|couro|seda)\b',
      caseSensitive: false,
    );

    for (final line in lines) {
      final price = pricePattern.firstMatch(line);
      final plainPrice = plainMoneyPattern.firstMatch(line);
      if (preco == null && (price != null || plainPrice != null)) {
        String rawVal = (price?.group(1) ?? plainPrice?.group(0) ?? line).replaceAll(RegExp(r'[^\d.,]'), '');
        rawVal = rawVal.replaceAll(',', '.');
        final lastDot = rawVal.lastIndexOf('.');
        if (lastDot != -1 && rawVal.length - lastDot <= 3) {
           final whole = rawVal.substring(0, lastDot).replaceAll('.', '');
           final decimal = rawVal.substring(lastDot + 1);
           preco = double.tryParse('$whole.$decimal');
        } else {
           preco = double.tryParse(rawVal.replaceAll('.', ''));
        }
        continue;
      }
      final compact = line.replaceAll(RegExp(r'[\s-]'), '');
      if (codigo == null && codePattern.hasMatch(compact)) {
        codigo = compact;
        codigoTipo = GtinValidator.isValid(compact)
            ? ExtractedCodeKind.gtin
            : ExtractedCodeKind.referenciaComercial;
        precisaRevisao = codigoTipo != ExtractedCodeKind.gtin;
        continue;
      }
      final lower = line.toLowerCase();
      if ((lower.startsWith('código:') ||
              lower.startsWith('codigo:') ||
              lower.startsWith('ref:') ||
              lower.startsWith('referência:')) &&
          codigo == null) {
        final candidate = line.split(':').last.trim().replaceAll(' ', '');
        if (codePattern.hasMatch(candidate)) {
          codigo = candidate;
          codigoTipo = GtinValidator.isValid(candidate)
              ? ExtractedCodeKind.gtin
              : ExtractedCodeKind.referenciaComercial;
          precisaRevisao = codigoTipo != ExtractedCodeKind.gtin;
        }
        continue;
      }
      if ((lower.startsWith('marca:') || lower.startsWith('fornecedor:')) &&
          fornecedor == null) {
        fornecedor = line.split(':').last.trim();
        continue;
      }
      if ((lower.startsWith('material:') ||
              lower.startsWith('descrição:') ||
              lower.startsWith('descricao:')) &&
          descricao == null) {
        descricao = line.split(':').last.trim();
        material = materialPattern.firstMatch(descricao)?.group(0);
        continue;
      }
      if (nome == null) {
        nome = line;
        if (materialPattern.hasMatch(line)) {
          descricao = line;
          material = materialPattern.firstMatch(line)?.group(0);
        }
      } else if (material == null && materialPattern.hasMatch(line)) {
        descricao = line;
        material = materialPattern.firstMatch(line)?.group(0);
      } else {
        fornecedor ??= line;
      }
    }

    return ExtractedTagData(
      codigo: codigo,
      nome: nome,
      fornecedor: fornecedor,
      descricao: descricao,
      material: material,
      preco: preco,
      codigoTipo: codigoTipo,
      precisaRevisao: precisaRevisao,
    );
  }
}
