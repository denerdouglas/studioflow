import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ExtractedTagData {
  final String? codigo;
  final String? nome;
  final String? fornecedor;
  final String? descricao;
  final String? material;
  final double? preco;

  ExtractedTagData({
    this.codigo,
    this.nome,
    this.fornecedor,
    this.descricao,
    this.material,
    this.preco,
  });
}

class VisionOcrService {
  static Future<ExtractedTagData> processImage(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    
    try {
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      final text = recognizedText.text;
      
      // Simple regex based parsing for demonstration/extraction.
      // Can be enhanced based on typical tag formats.
      String? codigo;
      String? nome;
      String? fornecedor;
      String? descricao;
      String? material;
      double? preco;

      final lines = text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

      for (int i = 0; i < lines.length; i++) {
        final lower = lines[i].toLowerCase();
        
        if (lower.contains('código') || lower.contains('codigo') || lower.contains('ref') || RegExp(r'^\d{8,14}$').hasMatch(lower)) {
          if (codigo == null) {
             if (lower.contains(':')) {
                codigo = lines[i].split(':').last.trim();
             } else if (RegExp(r'^\d{8,14}$').hasMatch(lower)) {
                codigo = lines[i];
             } else if (i + 1 < lines.length) {
                codigo = lines[i+1];
             }
          }
        }
        
        if (lower.contains('rs') || lower.contains(r'r$') || lower.contains(r'$')) {
           if (preco == null) {
              final match = RegExp(r'[\d.,]+').firstMatch(lower);
              if (match != null) {
                 final valStr = match.group(0)!.replaceAll('.', '').replaceAll(',', '.');
                 preco = double.tryParse(valStr);
              }
           }
        }
        
        if (lower.contains('marca') || lower.contains('fornecedor')) {
           if (fornecedor == null) {
              if (lower.contains(':')) {
                fornecedor = lines[i].split(':').last.trim();
              } else if (i + 1 < lines.length) {
                fornecedor = lines[i+1];
              }
           }
        }

        if (lower.contains('material') || lower.contains('comp')) {
           if (material == null) {
              if (lower.contains(':')) {
                material = lines[i].split(':').last.trim();
              } else if (i + 1 < lines.length) {
                material = lines[i+1];
              }
           }
        }
      }

      // Fallbacks
      if (lines.isNotEmpty) {
         // Assume first line that is not a code or price is the name
         for (final line in lines) {
           final l = line.toLowerCase();
           if (!l.contains(r'r$') && !l.contains('código') && !RegExp(r'^\d+$').hasMatch(l)) {
              nome = line;
              break;
           }
         }
      }

      return ExtractedTagData(
        codigo: codigo,
        nome: nome,
        fornecedor: fornecedor,
        descricao: descricao,
        material: material,
        preco: preco,
      );
    } finally {
      textRecognizer.close();
    }
  }
}
