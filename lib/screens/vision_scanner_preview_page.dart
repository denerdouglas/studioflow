import 'package:flutter/material.dart';
import '../repositories/estoque_repository.dart';
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
  State<VisionScannerPreviewPage> createState() => _VisionScannerPreviewPageState();
}

class _VisionScannerPreviewPageState extends State<VisionScannerPreviewPage> {
  late final TextEditingController _codigoController;
  late final TextEditingController _nomeController;
  late final TextEditingController _fornecedorController;
  late final TextEditingController _descricaoController;
  late final TextEditingController _materialController;
  late final TextEditingController _precoController;

  bool _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _codigoController = TextEditingController(text: widget.scannedCode ?? widget.data.codigo ?? '');
    _nomeController = TextEditingController(text: widget.data.nome ?? '');
    _fornecedorController = TextEditingController(text: widget.data.fornecedor ?? '');
    _descricaoController = TextEditingController(text: widget.data.descricao ?? '');
    _materialController = TextEditingController(text: widget.data.material ?? '');
    _precoController = TextEditingController(
      text: widget.data.preco != null ? widget.data.preco!.toStringAsFixed(2) : '',
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

  Future<void> _salvar() async {
    final codigo = _codigoController.text.trim();
    final nome = _nomeController.text.trim();
    
    if (codigo.isEmpty) {
      setState(() => _erro = 'O código é obrigatório.');
      return;
    }
    
    if (nome.isEmpty) {
      setState(() => _erro = 'O nome é obrigatório.');
      return;
    }

    setState(() {
      _salvando = true;
      _erro = null;
    });

    try {
      final repo = EstoqueRepository();
      
      // Checar se já existe um produto com o mesmo código de barras
      final itens = await repo.listar(incluirInativos: true);
      final existeCodigo = itens.any((i) => i.codigoBarras == codigo);
      if (existeCodigo) {
        setState(() {
          _erro = 'Já existe um produto no estoque com este código de barras.';
          _salvando = false;
        });
        return;
      }

      final preco = double.tryParse(_precoController.text.replaceAll(',', '.')) ?? 0;

      final novoItem = ItemEstoqueRegistro(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        nome: nome,
        categoria: 'Outros',
        tipo: 'revenda',
        quantidadeAtual: 1, // Start with 1 for now or 0
        estoqueMinimo: 1,
        unidade: 'unidade',
        conteudoPorUnidade: 1,
        unidadeConteudo: '',
        revisaoModelagemEstoque: false,
        custoUnitario: preco,
        fornecedor: _fornecedorController.text.trim(),
        codigoBarras: codigo,
        dataValidade: null,
        ativo: true,
        descontarAutomaticamente: true,
        observacoes: 'Material: ${_materialController.text.trim()}\nDesc: ${_descricaoController.text.trim()}',
        dataCadastro: DateTime.now(),
      );

      await repo.inserir(novoItem);
      
      if (!mounted) return;
      Navigator.pop(context, novoItem);
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = 'Erro ao salvar: $e';
          _salvando = false;
        });
      }
    }
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
              decoration: const InputDecoration(labelText: 'Código / Código de Barras *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nomeController,
              decoration: const InputDecoration(labelText: 'Nome do Produto *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _fornecedorController,
              decoration: const InputDecoration(labelText: 'Fornecedor / Marca'),
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
              decoration: const InputDecoration(labelText: 'Material / Composição'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _precoController,
              decoration: const InputDecoration(labelText: 'Preço (R\$)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _salvando ? null : _salvar,
              child: _salvando 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Confirmar e Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
