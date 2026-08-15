import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:read_pdf_text/read_pdf_text.dart';

import '../models/domain/consignment_document_import.dart';
import 'consignment_sheet_parser.dart';
import 'vision_ocr_service.dart';

typedef EmbeddedPdfTextExtractor = Future<String> Function(String path);
typedef PdfOcrExtractor = Future<String> Function(String path);
typedef ImageTextRecognizer = Future<String> Function(String path);

class ConsignmentImportException implements Exception {
  final String message;
  const ConsignmentImportException(this.message);

  @override
  String toString() => message;
}

class ConsignmentDocumentImportService {
  final EmbeddedPdfTextExtractor _embeddedExtractor;
  final PdfOcrExtractor _pdfOcrExtractor;
  final ImageTextRecognizer _imageRecognizer;

  ConsignmentDocumentImportService({
    EmbeddedPdfTextExtractor? embeddedExtractor,
    PdfOcrExtractor? pdfOcrExtractor,
    ImageTextRecognizer? imageRecognizer,
  }) : _embeddedExtractor = embeddedExtractor ?? ReadPdfText.getPDFtext,
       _pdfOcrExtractor = pdfOcrExtractor ?? _ocrPdf,
       _imageRecognizer = imageRecognizer ?? VisionOcrService.recognizeText;

  Future<ConsignmentDocumentImport> importPdf(String path) async {
    String embedded = '';
    try {
      embedded = await _embeddedExtractor(path);
    } catch (_) {
      // PDFs sem camada textual ou incompatíveis seguem para OCR real.
    }
    final hasUsefulText = _hasUsefulText(embedded);
    var text = embedded;
    var usedOcr = false;
    if (!hasUsefulText) {
      try {
        text = await _pdfOcrExtractor(path);
        usedOcr = true;
      } catch (_) {
        throw const ConsignmentImportException(
          'Não foi possível extrair os itens deste PDF.',
        );
      }
    }
    if (!_hasUsefulText(text)) {
      throw const ConsignmentImportException(
        'Não foi possível extrair os itens deste PDF.',
      );
    }
    final parsed = ConsignmentSheetParser.parse(
      text,
    ).copyWith(usedOcr: usedOcr);
    if (parsed.itens.isEmpty && parsed.linhasPendentes.isEmpty) {
      throw const ConsignmentImportException(
        'Nenhum produto identificado. Nenhuma estratégia (Texto/OCR) conseguiu extrair dados utilizáveis deste documento.',
      );
    }
    return parsed;
  }

  Future<ConsignmentDocumentImport> importImage(String path) async {
    final text = await _imageRecognizer(path);
    final parsed = ConsignmentSheetParser.parse(text).copyWith(usedOcr: true);
    if (parsed.itens.isNotEmpty) return parsed;

    // Mantém compatibilidade com a leitura anterior de uma etiqueta individual.
    final tag = VisionOcrService.parseText(text);
    if (tag.codigo == null || tag.nome == null || tag.preco == null) {
      throw const ConsignmentImportException(
        'Documento lido, mas nenhum produto foi identificado.',
      );
    }
    return ConsignmentDocumentImport(
      representante: tag.fornecedor,
      itens: [
        ConsignmentImportItem(
          codigo: tag.codigo!,
          categoria: '',
          material: tag.material ?? '',
          quantidade: 1,
          valorUnitario: tag.preco!,
          descricao: tag.nome!,
          observacao: tag.descricao ?? '',
        ),
      ],
      usedOcr: true,
    );
  }

  static bool _hasUsefulText(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    return compact.length >= 20 && RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(compact);
  }

  static Future<String> _ocrPdf(String path) async {
    final document = await PdfDocument.openFile(path);
    final temporary = await getTemporaryDirectory();
    final buffer = StringBuffer();
    try {
      for (
        var pageNumber = 1;
        pageNumber <= document.pagesCount;
        pageNumber++
      ) {
        final page = await document.getPage(pageNumber);
        File? imageFile;
        try {
          const width = 2000.0;
          final rendered = await page.render(
            width: width,
            height: width * page.height / page.width,
            format: PdfPageImageFormat.png,
            backgroundColor: '#FFFFFF',
            forPrint: true,
          );
          if (rendered == null) continue;
          imageFile = File(
            '${temporary.path}${Platform.pathSeparator}studioflow_consignacao_${DateTime.now().microsecondsSinceEpoch}_$pageNumber.png',
          );
          await imageFile.writeAsBytes(rendered.bytes, flush: true);
          final pageText = await VisionOcrService.recognizeText(imageFile.path);
          if (pageText.trim().isNotEmpty) buffer.writeln(pageText);
        } finally {
          await page.close();
          if (imageFile != null && await imageFile.exists()) {
            await imageFile.delete();
          }
        }
      }
    } finally {
      await document.close();
    }
    return buffer.toString();
  }
}
