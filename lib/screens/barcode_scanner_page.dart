import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/product_lookup_service.dart';
import '../core/validation/gtin_validator.dart';

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
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _finalizando = false;
  bool _processando = false;
  String? _ultimoCodigo;
  String? _erro;

  static String normalizeBarcode(String input) {
    final trimmed = input.trim();
    if (RegExp(r'^[\d\s-]+$').hasMatch(trimmed)) {
      return ProductLookupService.normalizeGtin(trimmed);
    }
    return trimmed.replaceAll(RegExp(r'\s+'), '');
  }

  static bool isSupportedBarcode(String input) {
    final value = normalizeBarcode(input);
    if (value.isEmpty || value.length > 80) return false;
    if (RegExp(r'^\d+$').hasMatch(value)) {
      return GtinValidator.isValid(value);
    }
    return value.length >= 4;
  }

  Future<void> _detectar(BarcodeCapture captura) async {
    if (_finalizando || _processando || captura.barcodes.isEmpty) return;
    final raw = captura.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (raw == null) return;
    final codigo = normalizeBarcode(raw);
    if (_ultimoCodigo == codigo) return;
    if (!isSupportedBarcode(codigo)) {
      setState(
        () =>
            _erro = 'Código inválido. Aponte para um código de barras válido.',
      );
      return;
    }
    _ultimoCodigo = codigo;
    setState(() {
      _processando = true;
      _erro = null;
    });
    await _controller.stop();
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    _finalizando = true;
    Navigator.pop(context, codigo);
  }

  Future<void> _digitar() async {
    await _controller.stop();
    if (!mounted) return;
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
    controller.dispose();
    if (!mounted) return;
    if (codigo == null) {
      await _retomarLeitura();
      return;
    }
    final normalizado = normalizeBarcode(codigo);
    if (!isSupportedBarcode(normalizado)) {
      setState(() => _erro = 'Código inválido.');
      await _retomarLeitura();
      return;
    }
    setState(() => _processando = true);
    _finalizando = true;
    Navigator.pop(context, normalizado);
  }

  Future<void> _retomarLeitura() async {
    if (_finalizando) return;
    _ultimoCodigo = null;
    setState(() => _processando = false);
    try {
      await _controller.start();
    } catch (_) {
      if (mounted) setState(() => _erro = 'Não foi possível reabrir a câmera.');
    }
  }

  Future<void> _abrirConfiguracoes() async {
    final opened = await openAppSettings();
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir as configurações do aparelho.'),
        ),
      );
    }
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
        leading: IconButton(
          tooltip: 'Fechar',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        actions: [
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, state, _) => IconButton(
              tooltip: state.torchState == TorchState.on
                  ? 'Desligar lanterna'
                  : 'Ligar lanterna',
              onPressed: state.isInitialized && !_processando
                  ? _controller.toggleTorch
                  : null,
              icon: Icon(
                state.torchState == TorchState.on
                    ? Icons.flash_on
                    : Icons.flash_off,
              ),
            ),
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
                  'A permissão da câmera foi negada. Libere-a nas configurações do aparelho ou digite o código.',
                MobileScannerErrorCode.unsupported =>
                  'Este dispositivo não oferece uma câmera compatível.',
                _ => 'A câmera está indisponível. Você pode digitar o código.',
              },
              onDigitar: _digitar,
              onConfiguracoes:
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? _abrirConfiguracoes
                  : null,
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
                      'Código lido. Pesquisando produto...',
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
                      _erro ?? 'Centralize o código dentro da moldura.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _processando ? null : _digitar,
                      icon: const Icon(Icons.keyboard),
                      label: const Text('Digitar código manualmente'),
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
  final VoidCallback? onConfiguracoes;
  const _ScannerErro({
    required this.mensagem,
    required this.onDigitar,
    this.onConfiguracoes,
  });

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
            if (onConfiguracoes != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onConfiguracoes,
                icon: const Icon(Icons.settings),
                label: const Text('Abrir configurações'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
