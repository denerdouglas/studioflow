import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image/image.dart' as img;
import 'package:audioplayers/audioplayers.dart';

import '../services/scanner/scanner_coordinator.dart';
import '../services/scanner/mlkit_vision_provider.dart';
import '../models/domain/scanner_product_draft.dart';
import 'scanner_draft_page.dart';
import '../services/session_controller.dart';
import '../core/validation/gtin_validator.dart';
import '../models/domain/universal_reader.dart';
import '../services/bip_context_service.dart';

Future<Uint8List?> _cropImage(Uint8List jpegBytes) async {
  return compute((bytes) {
    final original = img.decodeImage(bytes);
    if (original == null) return null;
    final cropW = (original.width * 0.8).toInt();
    final cropH = (cropW * (150 / 290)).toInt();
    final cropX = (original.width - cropW) ~/ 2;
    final cropY = (original.height - cropH) ~/ 2;
    final cropped = img.copyCrop(
      original,
      x: cropX,
      y: cropY,
      width: cropW,
      height: cropH,
    );
    return Uint8List.fromList(img.encodeJpg(cropped));
  }, jpegBytes);
}

class VisionScannerPage extends StatefulWidget {
  final ReaderContextPolicy? policy;
  final bool returnList;
  final Future<bool> Function(ScannerResult)? onContinuousItem;

  const VisionScannerPage({
    super.key,
    this.policy,
    this.returnList = false,
    this.onContinuousItem,
  });

  @override
  State<VisionScannerPage> createState() => _VisionScannerPageState();
}

class _VisionScannerPageState extends State<VisionScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    returnImage: true,
  );
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _processando = false;
  String? _erro;
  final BipSessionController bipSession = BipSessionController();

  DateTime _ultimoTempoOcr = DateTime.fromMillisecondsSinceEpoch(0);
  bool _ocrEmExecucao = false;

  bool get continuous => widget.policy?.continuous ?? widget.returnList;

  @override
  void initState() {
    super.initState();
    _audioPlayer.setSource(AssetSource('sounds/beep.ogg'));
  }

  void _tocarBip() {
    HapticFeedback.heavyImpact();
    _audioPlayer.resume();
  }

  @override
  void dispose() {
    _controller.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _executarOcrFrame(Uint8List jpegBytes) async {
    if (_ocrEmExecucao || _processando) return;
    try {
      _ocrEmExecucao = true;
      final cropped = await _cropImage(jpegBytes);
      if (cropped == null) return;
      if (!mounted) return;

      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/ocr_frame_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(cropped);

      final coordinator = ScannerCoordinator(
        externalProviders: [MlKitVisionProvider()],
      );
      final draft = await coordinator.analyzeImages(file.path);

      if (!mounted) return;
      final resolved = await BipContextService().resolve(draft);
      if (resolved.kind != BipItemKind.desconhecido) {
        await _processarCodigo(
          draft.referenciaComercial?.value ?? draft.gtin?.value ?? '',
          isOcrResult: true,
          draftOcr: draft,
        );
        return;
      }

      if (draft.referenciaComercial != null || draft.gtin != null) {
        await _processarCodigo(
          draft.referenciaComercial?.value ?? draft.gtin?.value ?? '',
          isOcrResult: true,
          draftOcr: draft,
        );
      }
    } catch (_) {
    } finally {
      _ocrEmExecucao = false;
    }
  }

  Future<void> _acceptResult(dynamic result) async {
    if (result is! ScannerResult) {
      if (!continuous) {
        if (mounted) Navigator.pop(context, result);
        return;
      }
      return;
    }

    final sResult = result;

    if (!continuous) {
      if (mounted) Navigator.pop(context, sResult);
      return;
    }

    if (sResult.tipo == ScannerResultType.cancelado) {
      setState(() => _processando = false);
      _controller.start();
      return;
    }

    final draft = sResult.draft ?? ScannerProductDraft();
    dynamic resolvedItem = sResult.produto;

    // Em modo contínuo, resolvemos e adicionamos à sessão.
    if (widget.onContinuousItem != null) {
      final success = await widget.onContinuousItem!(sResult);
      if (success && mounted) {
        _adicionarASessao(draft, resolvedItem);
      } else if (mounted) {
        setState(() => _processando = false);
        _controller.start();
      }
      return;
    }

    if (resolvedItem != null && mounted) {
      _adicionarASessao(draft, resolvedItem);
      return;
    }

    final resolved = await BipContextService().resolve(draft);
    if (resolved.kind != BipItemKind.desconhecido && mounted) {
      _adicionarASessao(draft, resolved.product);
      return;
    }

    if (mounted) _adicionarASessao(draft, null);
  }

  void _adicionarASessao(ScannerProductDraft draft, dynamic produto) {
    final key =
        draft.gtin?.value ??
        draft.qr?.value ??
        draft.referenciaComercial?.value ??
        '${draft.nome?.value}_${bipSession.items.length}';
    final added = bipSession.add(
      BipSessionItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        deduplicationKey: key,
        draft: draft,
        confirmed: true,
      ),
    );
    if (mounted) {
      setState(() {
        _processando = false;
        _erro = added
            ? 'Item adicionado: ${produto?.nome ?? draft.nome?.value ?? key}'
            : 'Item já lido.';
      });
      _controller.start();
    }
  }

  String? _ultimoCodigoLido;
  DateTime? _ultimoTempoLeitura;

  Future<void> _processarCodigo(
    String codigo, {
    bool isQr = false,
    bool isOcrResult = false,
    ScannerProductDraft? draftOcr,
    Uint8List? rawImage,
  }) async {
    if (_processando) return;

    final agora = DateTime.now();
    if (_ultimoCodigoLido == codigo && _ultimoTempoLeitura != null) {
      if (agora.difference(_ultimoTempoLeitura!).inMilliseconds < 2000) {
        return; // Debounce de 2s
      }
    }
    _ultimoCodigoLido = codigo;
    _ultimoTempoLeitura = agora;

    setState(() {
      _processando = true;
      _erro = null;
    });

    await _controller.stop();
    if (!mounted) return;

    final normalized = GtinValidator.normalize(codigo);
    if (codigo.trim().isEmpty) {
      setState(() {
        _processando = false;
        _erro = 'Código inválido. Confira a etiqueta ou preencha manualmente.';
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

    ScannerProductDraft draft =
        draftOcr ??
        (isQr
            ? ScannerProductDraft(
                qr: ScannerField(
                  codigo,
                  source: 'qr',
                  confidence: ScannerConfidence.alta,
                ),
                rawSignals: [codigo],
              )
            : GtinValidator.isValid(normalized)
            ? (await coordinator.searchExternalBarcode(normalized)) ??
                  ScannerProductDraft(
                    gtin: ScannerField(
                      normalized,
                      source: 'barcode',
                      confidence: ScannerConfidence.baixa,
                      reviewReason:
                          'GTIN válido, mas sem correspondência exata.',
                    ),
                  )
            : ScannerProductDraft(
                referenciaComercial: ScannerField(
                  codigo.trim(),
                  source: 'barcode',
                  confidence: ScannerConfidence.alta,
                ),
                reviewReasons: const ['Confirme o código comercial.'],
                rawSignals: [codigo],
              ));

    if (!mounted) return;

    final resolved = await BipContextService().resolve(draft);
    if (resolved.kind != BipItemKind.desconhecido && resolved.product != null) {
      _tocarBip();
      await _acceptResult(ScannerResult.existente(resolved.product!));
      return;
    }

    if (!mounted) return;

    // Tentativa rápida de OCR complementar se for barcode novo e temos a imagem
    ScannerProductDraft draftFinal = draft;
    if (rawImage != null && !isOcrResult && !isQr) {
      try {
        final cropped = await _cropImage(rawImage);
        if (cropped != null) {
          final tempDir = await getTemporaryDirectory();
          final file = File(
            '${tempDir.path}/ocr_complemento_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          await file.writeAsBytes(cropped);
          final draftOcrComp = await ScannerCoordinator(
            externalProviders: [MlKitVisionProvider()],
          ).analyzeImages(file.path);
          draftFinal = ScannerCoordinator.mergeDrafts(draftFinal, draftOcrComp);
        }
      } catch (_) {}
    }

    if (!mounted) return;

    _tocarBip(); // Bipa para produto novo/rascunho

    if (continuous) {
      // Em inventario, podemos apenas aceitar o rascunho
      await _acceptResult(ScannerResult.draft(draftFinal));
      return;
    }

    final result = await Navigator.push<ScannerResult?>(
      context,
      MaterialPageRoute(builder: (_) => ScannerDraftPage(draft: draftFinal)),
    );

    if (!mounted) return;

    if (result != null) {
      await _acceptResult(result);
    } else {
      setState(() => _processando = false);
      _controller.start();
    }
  }

  Future<void> _detectar(BarcodeCapture captura) async {
    final image = captura.image;
    if (image != null && !_ocrEmExecucao && !_processando) {
      final agora = DateTime.now();
      if (agora.difference(_ultimoTempoOcr).inMilliseconds > 1500) {
        _ultimoTempoOcr = agora;
        _executarOcrFrame(image);
      }
    }

    if (_processando || captura.barcodes.isEmpty) return;

    final raw = captura.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;

    if (raw == null) return;

    final detected = captura.barcodes.firstWhere(
      (barcode) => barcode.rawValue == raw,
      orElse: () => captura.barcodes.first,
    );
    await _processarCodigo(
      raw.trim(),
      isQr: detected.format == BarcodeFormat.qrCode,
      rawImage: image,
    );
  }

  Future<void> _digitarCodigo() async {
    String localCodigo = '';
    final codigo = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Digitar código'),
        content: TextField(
          autofocus: true,
          onChanged: (val) => localCodigo = val,
          decoration: const InputDecoration(labelText: 'Código ou referência'),
        ),
        actions: [
          if (continuous)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.pop(
                  context,
                  bipSession.items,
                ); // Retorna a lista e fecha o scanner!
              },
              child: Text('Conferir tudo e Sair'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, localCodigo.trim()),
            child: Text('Aplicar código'),
          ),
        ],
      ),
    );
    if (codigo != null && codigo.trim().isNotEmpty && mounted) {
      await _processarCodigo(codigo.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          continuous
              ? 'Lendo lote (${bipSession.items.length})'
              : 'Ler Etiqueta / Código',
        ),
        actions: [
          if (continuous)
            FilledButton(
              onPressed: () => Navigator.pop(context, bipSession.items),
              child: Text('Finalizar (${bipSession.items.length})'),
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
                    Icon(Icons.no_photography, color: Colors.white, size: 56),
                    SizedBox(height: 16),
                    Text(
                      'Não foi possível acessar a câmera para o código de barras.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
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
            Container(
              color: const Color(0x99000000),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      _erro ?? 'Processando...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
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
                  color: Theme.of(context).colorScheme.onSurface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _erro ?? 'Centralize o código ou texto na moldura.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                    SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _processando ? null : _digitarCodigo,
                      icon: Icon(Icons.keyboard),
                      label: Text('Digitar código manualmente'),
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
