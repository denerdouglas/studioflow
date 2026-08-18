import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:audioplayers/audioplayers.dart';

import '../services/scanner/scanner_coordinator.dart';
import '../models/domain/scanner_product_draft.dart';
import 'scanner_draft_page.dart';
import '../services/session_controller.dart';
import '../core/validation/gtin_validator.dart';
import '../models/domain/universal_reader.dart';
import '../services/bip_context_service.dart';
import '../services/vision_ocr_service.dart';
import '../services/scanner/mlkit_utils.dart';

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

class _VisionScannerPageState extends State<VisionScannerPage> with WidgetsBindingObserver {
  CameraController? _cameraController;
  final AudioPlayer _audioPlayer = AudioPlayer();

  final BarcodeScanner _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.all]);
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  bool _isCameraInitialized = false;
  bool _processandoFrame = false;
  bool _processandoAtividade = false;
  String? _erro;
  
  final BipSessionController bipSession = BipSessionController();

  DateTime _ultimoTempoOcr = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _ultimoTempoBarcode = DateTime.fromMillisecondsSinceEpoch(0);
  
  String? _ultimoCodigoLido;
  DateTime? _ultimoTempoLeitura;

  bool get continuous => widget.policy?.continuous ?? widget.returnList;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audioPlayer.setSource(AssetSource('sounds/beep.ogg'));
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _erro = 'Nenhuma câmera encontrada.');
        return;
      }
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid 
            ? ImageFormatGroup.nv21 
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
      });

      _cameraController!.startImageStream(_processarFrameCamera);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Erro ao iniciar câmera: $e');
    }
  }

  void _tocarBip() {
    HapticFeedback.heavyImpact();
    _audioPlayer.resume();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _barcodeScanner.close();
    _textRecognizer.close();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      cameraController.stopImageStream();
      cameraController.dispose();
      _cameraController = null;
      if (mounted) setState(() => _isCameraInitialized = false);
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _processarFrameCamera(CameraImage image) async {
    if (_processandoFrame || _processandoAtividade || !mounted) return;

    final agora = DateTime.now();
    final podeBarcode = agora.difference(_ultimoTempoBarcode).inMilliseconds > 400;
    final podeOcr = agora.difference(_ultimoTempoOcr).inMilliseconds > 1500;

    if (!podeBarcode && !podeOcr) return;

    final inputImage = convertCameraImageToInputImage(image, _cameraController!);
    if (inputImage == null) return;

    _processandoFrame = true;

    try {
      ScannerProductDraft draftFinal = ScannerProductDraft();

      // 1. Barcode
      if (podeBarcode) {
        _ultimoTempoBarcode = agora;
        final barcodes = await _barcodeScanner.processImage(inputImage);
        
        if (barcodes.isNotEmpty) {
          final barcode = barcodes.first.displayValue ?? barcodes.first.rawValue;
          if (barcode != null && barcode.trim().isNotEmpty) {
            final format = barcodes.first.format;
            final isQr = format == BarcodeFormat.qrCode;
            
            final normalized = GtinValidator.normalize(barcode);
            
            draftFinal = isQr
                ? ScannerProductDraft(
                    qr: ScannerField(
                      barcode,
                      source: 'qr',
                      confidence: ScannerConfidence.alta,
                    ),
                    rawSignals: [barcode],
                  )
                : ScannerProductDraft(
                    referenciaComercial: ScannerField(
                      barcode.trim(),
                      source: 'barcode',
                      confidence: ScannerConfidence.alta,
                    ),
                    gtin: GtinValidator.isValid(normalized) 
                        ? ScannerField(normalized, source: 'barcode', confidence: ScannerConfidence.baixa) 
                        : null,
                    rawSignals: [barcode],
                  );
          }
        }
      }

      if (podeOcr) {
        _ultimoTempoOcr = DateTime.now();
        final recognizedText = await _textRecognizer.processImage(inputImage);
        final draftOcrData = VisionOcrService.parseText(recognizedText.text);
        final draftOcr = ScannerProductDraft(
          referenciaComercial: draftOcrData.codigo != null ? ScannerField(draftOcrData.codigo!, source: 'ocr', confidence: ScannerConfidence.baixa) : null,
          nome: draftOcrData.nome != null ? ScannerField(draftOcrData.nome!, source: 'ocr', confidence: ScannerConfidence.baixa) : null,
          descricao: draftOcrData.descricao != null ? ScannerField(draftOcrData.descricao!, source: 'ocr', confidence: ScannerConfidence.baixa) : null,
          preco: draftOcrData.preco != null ? ScannerField(draftOcrData.preco!, source: 'ocr', confidence: ScannerConfidence.baixa) : null,
          material: draftOcrData.material != null ? ScannerField(draftOcrData.material!, source: 'ocr', confidence: ScannerConfidence.baixa) : null,
        );
        
        if (draftOcrData.codigo != null || draftOcrData.nome != null) {
          draftFinal = ScannerCoordinator.mergeDrafts(draftFinal, draftOcr);
        }
      }

      // 3. Processar resultado combinado
      final rawCode = draftFinal.referenciaComercial?.value ?? draftFinal.gtin?.value;
      if (rawCode != null && rawCode.isNotEmpty) {
        if (!mounted) return;
        await _processarCodigo(
          rawCode,
          isQr: draftFinal.qr != null,
          draftMontado: draftFinal,
        );
      }
    } catch (e) {
      debugPrint('Erro processando frame: $e');
    } finally {
      if (mounted) {
        _processandoFrame = false;
      }
    }
  }

  Future<void> _acceptResult(ScannerResult sResult) async {
    if (!continuous) {
      if (mounted) Navigator.pop(context, sResult);
      return;
    }

    if (sResult.tipo == ScannerResultType.cancelado) {
      if (mounted) setState(() => _processandoAtividade = false);
      return;
    }

    final draft = sResult.draft ?? ScannerProductDraft();
    dynamic resolvedItem = sResult.produto;

    // Em modo contínuo, enviamos ao chamador para validação de negócio
    if (widget.onContinuousItem != null) {
      try {
        final success = await widget.onContinuousItem!(sResult);
        if (success && mounted) {
          _adicionarASessao(draft, resolvedItem);
        } else if (mounted) {
          setState(() {
            _processandoAtividade = false;
            _erro = 'Falha ao registrar item.';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _processandoAtividade = false;
            _erro = 'Erro: $e';
          });
        }
      }
      return;
    }

    // Se não há callback customizado, apenas adiciona local
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
        _processandoAtividade = false;
        _erro = added
            ? 'Item adicionado: ${produto?.nome ?? draft.nome?.value ?? key}'
            : 'Item já lido.';
      });
    }
  }

  Future<void> _processarCodigo(
    String codigo, {
    bool isQr = false,
    bool isManual = false,
    ScannerProductDraft? draftMontado,
  }) async {
    if (_processandoAtividade) return;

    final agora = DateTime.now();
    if (_ultimoCodigoLido == codigo && _ultimoTempoLeitura != null) {
      if (agora.difference(_ultimoTempoLeitura!).inMilliseconds < 2000) {
        return; // Debounce de 2s
      }
    }
    _ultimoCodigoLido = codigo;
    _ultimoTempoLeitura = agora;

    setState(() {
      _processandoAtividade = true;
      _erro = null;
    });

    final normalized = GtinValidator.normalize(codigo);
    if (codigo.trim().isEmpty) {
      setState(() {
        _processandoAtividade = false;
        _erro = 'Código inválido. Confira a etiqueta ou preencha manualmente.';
      });
      return;
    }

    final commerceId = SessionController.instance.usuario?.comercioId;
    final coordinator = ScannerCoordinator(
      externalProviders: [
        if (commerceId != null)
          ProductLookupScannerProvider(commerceId: commerceId),
      ],
    );

    ScannerProductDraft draft = draftMontado ?? ScannerProductDraft();
    
    if (isManual || draftMontado == null) {
      draft = ScannerProductDraft(
        referenciaComercial: ScannerField(
          codigo.trim(),
          source: isManual ? 'manual' : 'barcode',
          confidence: ScannerConfidence.alta,
        ),
        gtin: GtinValidator.isValid(normalized) 
            ? ScannerField(normalized, source: isManual ? 'manual' : 'barcode', confidence: ScannerConfidence.baixa)
            : null,
        rawSignals: [codigo],
      );
      if (draft.gtin != null) {
        final prod = await coordinator.searchExternalBarcode(normalized);
        if (prod != null) {
           draft = ScannerCoordinator.mergeDrafts(draft, prod);
        }
      }
    } else if (!isQr && GtinValidator.isValid(normalized)) {
      final prod = await coordinator.searchExternalBarcode(normalized);
      if (prod != null) {
         draft = ScannerCoordinator.mergeDrafts(draft, prod);
      }
    }

    if (!mounted) return;

    final resolved = await BipContextService().resolve(draft);
    if (resolved.kind != BipItemKind.desconhecido && resolved.product != null) {
      _tocarBip();
      await _acceptResult(ScannerResult.existente(resolved.product!));
      return;
    }

    if (!mounted) return;

    _tocarBip(); // Bipa para produto novo/rascunho

    if (continuous) {
      await _acceptResult(ScannerResult.draft(draft));
      return;
    }

    final result = await Navigator.push<ScannerResult?>(
      context,
      MaterialPageRoute(builder: (_) => ScannerDraftPage(draft: draft)),
    );

    if (!mounted) return;

    if (result != null) {
      await _acceptResult(result);
    } else {
      setState(() => _processandoAtividade = false);
    }
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
                Navigator.pop(context, bipSession.items); // Retorna a lista e fecha
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
      await _processarCodigo(codigo.trim(), isManual: true);
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
          if (_isCameraInitialized && _cameraController != null)
            CameraPreview(_cameraController!)
          else if (_erro != null && _cameraController == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography, color: Colors.white, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      _erro ?? 'Erro na câmera.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),
            
          if (!_processandoAtividade)
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
            
          if (_processandoAtividade)
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
                      onPressed: _processandoAtividade ? null : _digitarCodigo,
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
