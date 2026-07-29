import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.itf14,
      BarcodeFormat.qrCode,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _finalizando = false;
  String? _erro;

  void _detectar(BarcodeCapture captura) {
    if (_finalizando || captura.barcodes.isEmpty) return;
    final codigo = captura.barcodes.first.rawValue?.trim();
    if (codigo == null || codigo.length < 4) {
      setState(
        () =>
            _erro = 'Código inválido. Aponte para um código de barras válido.',
      );
      return;
    }
    _finalizando = true;
    Navigator.pop(context, codigo);
  }

  Future<void> _digitar() async {
    final controller = TextEditingController();
    final codigo = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Digitar código'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Código de barras'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Usar código'),
          ),
        ],
      ),
    );
    if (!mounted || codigo == null) return;
    if (codigo.length < 4) {
      setState(() => _erro = 'Código inválido.');
      return;
    }
    Navigator.pop(context, codigo);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Ler código de barras'),
        actions: [
          IconButton(
            tooltip: 'Lanterna',
            onPressed: _controller.toggleTorch,
            icon: const Icon(Icons.flash_on),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _detectar,
            errorBuilder: (context, error) => _ScannerErro(
              mensagem: switch (error.errorCode) {
                MobileScannerErrorCode.permissionDenied =>
                  'A permissão da câmera foi negada. Libere-a nas configurações do Android ou digite o código.',
                MobileScannerErrorCode.unsupported =>
                  'Este dispositivo não oferece uma câmera compatível.',
                _ => 'A câmera está indisponível. Você pode digitar o código.',
              },
              onDigitar: _digitar,
            ),
          ),
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
                      _erro ?? 'Centralize o código dentro da moldura.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _digitar,
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

class _ScannerErro extends StatelessWidget {
  final String mensagem;
  final VoidCallback onDigitar;
  const _ScannerErro({required this.mensagem, required this.onDigitar});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, color: Colors.white, size: 56),
            const SizedBox(height: 16),
            Text(
              mensagem,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onDigitar,
              icon: const Icon(Icons.keyboard),
              label: const Text('Digitar código'),
            ),
          ],
        ),
      ),
    ),
  );
}
