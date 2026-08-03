import 'package:flutter/material.dart';
import '../services/vision_ocr_service.dart';

class VisionScannerPreviewPage extends StatefulWidget {
  final ExtractedTagData data;
  final String? scannedCode;

  const VisionScannerPreviewPage({
    super.key,
    required this.data,
    this.scannedCode,
  });

  @override
  State<VisionScannerPreviewPage> createState() =>
      _VisionScannerPreviewPageState();
}

class _VisionScannerPreviewPageState extends State<VisionScannerPreviewPage> {
  late final TextEditingController _codigoController;
  late final TextEditingController _nomeController;
  late final TextEditingController _fornecedorController;
  late final TextEditingController _descricaoController;
  late final TextEditingController _materialController;
  late final TextEditingController _precoController;

  String? _erro;

  @override
  void initState() {
    super.initState();
    _codigoController = TextEditingController(
      text: widget.scannedCode ?? widget.data.codigo ?? '',
    );
    _nomeController = TextEditingController(text: widget.data.nome ?? '');
    _fornecedorController = TextEditingController(
      text: widget.data.fornecedor ?? '',
    );
    _descricaoController = TextEditingController(
      text: widget.data.descricao ?? '',
    );
    _materialController = TextEditingController(
      text: widget.data.material ?? '',
    );
    _precoController = TextEditingController(
      text: widget.data.preco != null
          ? widget.data.preco!.toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    _codigoController.dispose();
    _nomeController.dispose();
    _fornecedorController.dispose();
    _descricaoController.dispose();
    _materialController.dispose();
    _precoController.dispose();
    super.dispose();
  }

  void _confirmar() {
    final codigo = _codigoController.text.trim();
    if (codigo.isEmpty) {
      setState(() => _erro = 'O código é obrigatório.');
      return;
    }
    final preco = double.tryParse(
      _precoController.text.trim().replaceAll('.', '').replaceAll(',', '.'),
    );
    Navigator.pop(
      context,
      ExtractedTagData(
        codigo: codigo,
        nome: _nomeController.text.trim().isEmpty
            ? null
            : _nomeController.text.trim(),
        fornecedor: _fornecedorController.text.trim().isEmpty
            ? null
            : _fornecedorController.text.trim(),
        descricao: _descricaoController.text.trim().isEmpty
            ? null
            : _descricaoController.text.trim(),
        material: _materialController.text.trim().isEmpty
            ? null
            : _materialController.text.trim(),
        preco: preco,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro Assistido')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Confirme os dados extraídos. Marque ou corrija campos incorretos.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_erro != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.red.shade100,
                child: Text(_erro!, style: const TextStyle(color: Colors.red)),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _codigoController,
              decoration: const InputDecoration(
                labelText: 'Código / Código de Barras *',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nomeController,
              decoration: const InputDecoration(labelText: 'Nome do Produto *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _fornecedorController,
              decoration: const InputDecoration(
                labelText: 'Fornecedor / Marca',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descricaoController,
              decoration: const InputDecoration(labelText: 'Descrição'),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _materialController,
              decoration: const InputDecoration(
                labelText: 'Material / Composição',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _precoController,
              decoration: const InputDecoration(labelText: 'Preço (R\$)'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _confirmar,
              child: const Text('Confirmar leitura'),
            ),
          ],
        ),
      ),
    );
  }
}
