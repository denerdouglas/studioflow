import 'package:flutter/material.dart';
import '../models/domain/scanner_product_draft.dart';
import '../repositories/loja_repository.dart';
import '../models/domain/loja.dart';
import '../services/session_controller.dart';
import '../core/utils/id_generator.dart';

class ScannerDraftPage extends StatefulWidget {
  final ScannerProductDraft draft;
  final String? frontImagePath;
  final String? backImagePath;

  const ScannerDraftPage({
    super.key,
    required this.draft,
    this.frontImagePath,
    this.backImagePath,
  });

  @override
  State<ScannerDraftPage> createState() => _ScannerDraftPageState();
}

class _ScannerDraftPageState extends State<ScannerDraftPage> {
  late TextEditingController _nomeController;
  late TextEditingController _gtinController;
  late TextEditingController _marcaController;
  late TextEditingController _quantidadeController;

  String _finalidadeSelecionada =
      'venda'; // venda, uso_interno, ambos, ativo_imobilizado
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(
      text: widget.draft.nome?.value ?? '',
    );
    _gtinController = TextEditingController(
      text: widget.draft.gtin?.value ?? '',
    );
    _marcaController = TextEditingController(
      text: widget.draft.marca?.value ?? '',
    );
    _quantidadeController = TextEditingController(
      text: widget.draft.quantidadeEmbalagem?.value?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _gtinController.dispose();
    _marcaController.dispose();
    _quantidadeController.dispose();
    super.dispose();
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    ScannerField? fieldData,
  ) {
    final bool isLowConfidence =
        fieldData?.confidence == ScannerConfidence.baixa;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          filled: isLowConfidence,
          fillColor: isLowConfidence
              ? Colors.orange.withValues(alpha: 0.1)
              : null,
          helperText: fieldData != null
              ? 'Origem: ${fieldData.source}'
              : 'Preenchimento manual',
          suffixIcon: isLowConfidence
              ? const Tooltip(
                  message: 'Confiança baixa, verifique a informação.',
                  child: Icon(Icons.warning, color: Colors.orange),
                )
              : null,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Future<void> _confirmar() async {
    // Injeção limpa de dependência para evitar acoplamento
    final nome = _nomeController.text.trim();
    final gtin = _gtinController.text.trim();

    if (nome.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nome é obrigatório.')));
      return;
    }

    final confirmedDraft = ScannerProductDraft(
      nome: ScannerField(
        nome,
        source: 'user_confirmed',
        confidence: ScannerConfidence.alta,
      ),
      gtin: ScannerField(
        gtin,
        source: 'user_confirmed',
        confidence: ScannerConfidence.alta,
      ),
      marca: ScannerField(
        _marcaController.text.trim(),
        source: 'user_confirmed',
        confidence: ScannerConfidence.alta,
      ),
      qr: widget.draft.qr,
      referenciaComercial: widget.draft.referenciaComercial,
      referenciaInterna: widget.draft.referenciaInterna,
      descricao: widget.draft.descricao,
      quantidadeEmbalagem: widget.draft.quantidadeEmbalagem,
      unidade: widget.draft.unidade,
      validade: widget.draft.validade,
      lote: widget.draft.lote,
      categoriaSugerida: widget.draft.categoriaSugerida,
      preco: widget.draft.preco,
      material: widget.draft.material,
      tamanhoVariacao: widget.draft.tamanhoVariacao,
      quantidade: widget.draft.quantidade,
      imagemFrente: widget.draft.imagemFrente,
      imagemVerso: widget.draft.imagemVerso,
      rawSignals: widget.draft.rawSignals,
    );

    setState(() => _salvando = true);

    try {
      final u = SessionController.instance.usuario;
      if (u == null) throw StateError('Usuário não autenticado.');

      final agora = DateTime.now();
      final produto = ProdutoLoja(
        id: IdGenerator.temporal(),
        comercioId: u.comercioId,
        nome: confirmedDraft.nome?.value ?? '',
        tipoProduto: _finalidadeSelecionada,
        descricao: confirmedDraft.descricao?.value,
        categoria: confirmedDraft.categoriaSugerida?.value ?? 'Geral',
        marca: confirmedDraft.marca?.value,
        codigoInterno:
            confirmedDraft.referenciaComercial?.value ??
            confirmedDraft.referenciaInterna?.value ??
            '',
        codigoBarras: confirmedDraft.gtin?.value,
        tipo: 'produto',
        modalidade: ModalidadeProduto.proprio,
        custo: 0.0,
        precoVenda: confirmedDraft.preco?.value ?? 0.0,
        margem: 0.0,
        quantidadeAtual: confirmedDraft.quantidade?.value ?? 0.0,
        estoqueMinimo: 0.0,
        quantidadeSugerida: 0.0,
        unidade: confirmedDraft.unidade?.value ?? 'un',
        conteudoPorUnidade: 0.0,
        unidadeConteudo: '',
        revisaoModelagemEstoque: false,
        quantidadeEmbalagem: confirmedDraft.quantidadeEmbalagem?.value ?? 1.0,
        lote: confirmedDraft.lote?.value ?? '',
        dataEntrada: agora,
        validade: confirmedDraft.validade?.value,
        imagem: confirmedDraft.imagemFrente ?? '',
        observacoes: '',
        origemCatalogo: 'scanner_ocr',
        ativo: true,
        criadoEm: agora,
        atualizadoEm: agora,
      );

      await LojaRepository().salvarProduto(produto);

      if (mounted) {
        Navigator.pop(context, ScannerResult.novo(produto));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Falha ao salvar produto: $e')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Revisar Produto')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Confira as informações extraídas. Campos com aviso precisam da sua confirmação.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            if (widget.frontImagePath != null)
              Container(
                height: 150,
                color: Colors.grey.shade200,
                child: const Center(
                  child: Text('Foto Frente (Preview)'),
                ), // Mockado para não exigir dart:io aqui de imediato caso seja mobile puro
              ),
            const SizedBox(height: 16),
            _buildField(
              'Código de Barras (GTIN)',
              _gtinController,
              widget.draft.gtin,
            ),
            _buildField('Nome do Produto', _nomeController, widget.draft.nome),
            _buildField('Marca', _marcaController, widget.draft.marca),

            const SizedBox(height: 16),
            const Text(
              'Finalidade do Produto:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            DropdownButtonFormField<String>(
              initialValue: _finalidadeSelecionada,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'venda', child: Text('Venda (Loja)')),
                DropdownMenuItem(
                  value: 'uso_interno',
                  child: Text('Uso Interno (Estoque Salão)'),
                ),
                DropdownMenuItem(
                  value: 'ambos',
                  child: Text('Ambos (Venda e Uso Interno)'),
                ),
                DropdownMenuItem(
                  value: 'ativo_imobilizado',
                  child: Text('Ativo Imobilizado (Móveis/Equip)'),
                ),
              ],
              onChanged: (v) => setState(() => _finalidadeSelecionada = v!),
            ),
            const SizedBox(height: 32),
            _salvando
                ? const Center(child: CircularProgressIndicator())
                : FilledButton(
                    onPressed: _confirmar,
                    child: const Text('Confirmar e Salvar'),
                  ),
            if (!_salvando)
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, ScannerResult.cancelado()),
                child: const Text('Cancelar (Nenhum dado salvo)'),
              ),
          ],
        ),
      ),
    );
  }
}
