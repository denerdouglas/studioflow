import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/vision_ocr_service.dart';
import 'vision_scanner_preview_page.dart';

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

    // Navigate to preview page with the code
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VisionScannerPreviewPage(
          data: ExtractedTagData(), // No extra info extracted from pure barcode
          scannedCode: codigo,
        ),
      ),
    );

    if (!mounted) return;
    
    if (result != null) {
      // Saved successfully
      Navigator.pop(context, result);
    } else {
      // Cancelled, resume scanner
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

  Future<void> _usarOcr() async {
    final picker = ImagePicker();
    final xfile = await showDialog<XFile?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Capturar Etiqueta'),
        content: const Text('Deseja usar a câmera ou escolher da galeria?'),
        actions: [
          TextButton(
            onPressed: () async {
              final file = await picker.pickImage(source: ImageSource.gallery);
              if (context.mounted) Navigator.pop(context, file);
            },
            child: const Text('Galeria'),
          ),
          FilledButton(
            onPressed: () async {
              final file = await picker.pickImage(source: ImageSource.camera);
              if (context.mounted) Navigator.pop(context, file);
            },
            child: const Text('Câmera'),
          ),
        ],
      ),
    );

    if (xfile == null) return;

    setState(() {
      _processando = true;
      _erro = null;
    });

    try {
      final ExtractedTagData data = await VisionOcrService.processImage(xfile.path);
      
      if (!mounted) return;
      
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VisionScannerPreviewPage(data: data),
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
          _erro = 'Falha ao ler texto da imagem: $e';
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
                    const Icon(Icons.no_photography, color: Colors.white, size: 56),
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
