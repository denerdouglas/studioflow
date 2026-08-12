import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/scanner/scanner_coordinator.dart';
import '../services/scanner/mlkit_vision_provider.dart';
import '../models/domain/scanner_product_draft.dart';
import 'scanner_draft_page.dart';
import 'vision_ocr_capture_page.dart';
import '../services/session_controller.dart';
import '../core/validation/gtin_validator.dart';

class VisionScannerPage extends StatefulWidget {
  const VisionScannerPage({super.key});

  @override
  State<VisionScannerPage> createState() => _VisionScannerPageState();
}

class _VisionScannerPageState extends State<VisionScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _processando = false;
  String? _erro;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _processarCodigo(String codigo) async {
    if (_processando) return;

    setState(() {
      _processando = true;
      _erro = null;
    });

    await _controller.stop();
    if (!mounted) return;

    final normalized = GtinValidator.normalize(codigo);
    if (!GtinValidator.isValid(normalized)) {
      setState(() {
        _processando = false;
        _erro = 'GTIN inválido. Confira o código ou preencha manualmente.';
      });
      await _controller.start();
      return;
    }
    final commerceId = SessionController.instance.usuario?.comercioId;
    final coordinator = ScannerCoordinator(
      externalProviders: [
        if (commerceId != null)
          ProductLookupScannerProvider(commerceId: commerceId),
      ],
    );
    final draft =
        await coordinator.searchExternalBarcode(normalized) ??
        ScannerProductDraft(
          gtin: ScannerField(
            normalized,
            source: 'barcode',
            confidence: ScannerConfidence.baixa,
            reviewReason:
                'GTIN válido, mas sem correspondência exata no catálogo.',
          ),
          reviewReasons: const [
            'Produto não encontrado; revise ou cadastre manualmente.',
          ],
        );

    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ScannerDraftPage(draft: draft)),
    );

    if (!mounted) return;

    if (result != null) {
      Navigator.pop(context, result);
    } else {
      setState(() => _processando = false);
      _controller.start();
    }
  }

  Future<void> _detectar(BarcodeCapture captura) async {
    if (_processando || captura.barcodes.isEmpty) return;
    final raw = captura.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;

    if (raw == null) return;
    await _processarCodigo(raw.trim());
  }

  Future<void> _digitarCodigo() async {
    final controller = TextEditingController();
    final codigo = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Digitar código'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Código ou referência'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Revisar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (codigo != null && codigo.trim().isNotEmpty) {
      await _processarCodigo(codigo.trim());
    }
  }

  Future<void> _usarOcr() async {
    final resultPaths = await Navigator.push<Map<String, String?>>(
      context,
      MaterialPageRoute(builder: (_) => const VisionOcrCapturePage()),
    );

    if (resultPaths == null || resultPaths['front'] == null) return;

    final frontPath = resultPaths['front']!;
    final backPath = resultPaths['back'];

    setState(() {
      _processando = true;
      _erro = null;
    });

    try {
      final coordinator = ScannerCoordinator(
        externalProviders: [MlKitVisionProvider()],
      );
      final draft = await coordinator.analyzeImages(
        frontPath,
        backPath: backPath,
      );

      if (!mounted) return;

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScannerDraftPage(
            draft: draft,
            frontImagePath: frontPath,
            backImagePath: backPath,
          ),
        ),
      );

      if (!mounted) return;

      if (result != null) {
        Navigator.pop(context, result);
      } else {
        setState(() => _processando = false);
        _controller.start();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = 'Falha ao processar imagem: $e';
          _processando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Ler Etiqueta / Código'),
        actions: [
          IconButton(
            icon: const Icon(Icons.document_scanner),
            tooltip: 'Usar OCR na imagem',
            onPressed: _processando ? null : _usarOcr,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _detectar,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.no_photography,
                      color: Colors.white,
                      size: 56,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Não foi possível acessar a câmera para o código de barras.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _usarOcr,
                      child: const Text('Usar Leitura de Texto (OCR)'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!_processando)
            Center(
              child: Container(
                width: 290,
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          if (_processando)
            const ColoredBox(
              color: Color(0x99000000),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Processando...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _erro ?? 'Centralize o código na moldura ou use o OCR.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _processando ? null : _usarOcr,
                      icon: const Icon(Icons.text_fields),
                      label: const Text('Ler Textos / Extrair Etiqueta (OCR)'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _processando ? null : _digitarCodigo,
                      icon: const Icon(Icons.keyboard),
                      label: const Text('Digitar manualmente'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
