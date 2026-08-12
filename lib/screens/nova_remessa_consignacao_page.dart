import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../repositories/consignacao_repository.dart';
import '../services/vision_ocr_service.dart';

class NovaRemessaConsignacaoPage extends StatefulWidget {
  const NovaRemessaConsignacaoPage({super.key});

  @override
  State<NovaRemessaConsignacaoPage> createState() =>
      _NovaRemessaConsignacaoPageState();
}

class _NovaRemessaConsignacaoPageState
    extends State<NovaRemessaConsignacaoPage> {
  final repo = ConsignacaoRepository();
  final nome = TextEditingController();
  final contrato = TextEditingController();
  final mostruario = TextEditingController();
  final observacoes = TextEditingController();
  final itens = <Map<String, Object?>>[];
  List<Map<String, Object?>> fornecedores = [];
  String? fornecedorId;
  String? arquivo;
  DateTime recebimento = DateTime.now();
  DateTime? troca;
  DateTime? pagamento;
  bool conferindo = false;
  bool salvando = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await repo.fornecedores();
    if (!mounted) return;
    setState(() {
      fornecedores = data;
      fornecedorId = data.firstOrNull?['id'] as String?;
    });
  }

  @override
  void dispose() {
    nome.dispose();
    contrato.dispose();
    mostruario.dispose();
    observacoes.dispose();
    super.dispose();
  }

  Future<void> _selecionarArquivo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    arquivo = path;
    final lower = path.toLowerCase();
    if (!lower.endsWith('.pdf')) {
      try {
        final data = await VisionOcrService.processImage(path);
        itens.add({
          'codigo': data.codigo ?? '',
          'categoria': '',
          'nome': data.nome ?? '',
          'descricao': data.descricao ?? '',
          'quantidade': 1,
          'preco': data.preco ?? 0,
          'material': data.material ?? '',
          'observacoes': '',
        });
      } catch (_) {
        // O arquivo continua anexado e a conferência manual permanece possível.
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _editarItem([int? index]) async {
    final current = index == null ? <String, Object?>{} : itens[index];
    final code = TextEditingController(text: '${current['codigo'] ?? ''}');
    final category = TextEditingController(
      text: '${current['categoria'] ?? ''}',
    );
    final description = TextEditingController(
      text: '${current['nome'] ?? current['descricao'] ?? ''}',
    );
    final quantity = TextEditingController(
      text: '${current['quantidade'] ?? 1}',
    );
    final price = TextEditingController(text: '${current['preco'] ?? ''}');
    final material = TextEditingController(
      text: '${current['material'] ?? ''}',
    );
    final notes = TextEditingController(
      text: '${current['observacoes'] ?? ''}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(index == null ? 'Adicionar item' : 'Conferir item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(code, 'Código'),
              _field(category, 'Categoria'),
              _field(description, 'Descrição'),
              _field(quantity, 'Quantidade', number: true),
              _field(price, 'Valor unitário', number: true),
              _field(material, 'Material/tipo'),
              _field(notes, 'Observação'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final item = <String, Object?>{
      'codigo': code.text.trim(),
      'categoria': category.text.trim(),
      'nome': description.text.trim(),
      'descricao': description.text.trim(),
      'quantidade': int.tryParse(quantity.text) ?? 1,
      'preco': double.tryParse(price.text.replaceAll(',', '.')) ?? -1,
      'material': material.text.trim(),
      'observacoes': notes.text.trim(),
    };
    setState(() => index == null ? itens.add(item) : itens[index] = item);
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool number = false,
  }) => TextField(
    controller: controller,
    keyboardType: number ? TextInputType.number : null,
    decoration: InputDecoration(labelText: label),
  );

  Future<void> _date(String type) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: type == 'recebimento'
          ? recebimento
          : (type == 'troca' ? troca : pagamento) ?? DateTime.now(),
    );
    if (selected == null) return;
    setState(() {
      if (type == 'recebimento') recebimento = selected;
      if (type == 'troca') troca = selected;
      if (type == 'pagamento') pagamento = selected;
    });
  }

  bool get _valido =>
      fornecedorId != null &&
      nome.text.trim().isNotEmpty &&
      itens.isNotEmpty &&
      itens.every(
        (item) =>
            '${item['codigo'] ?? ''}'.trim().isNotEmpty &&
            '${item['nome'] ?? ''}'.trim().isNotEmpty &&
            (item['quantidade'] as num? ?? 0) > 0 &&
            (item['preco'] as num? ?? -1) >= 0,
      );

  Future<void> _confirmar() async {
    if (!_valido) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Confira o cabeçalho e todos os itens.')),
      );
      return;
    }
    setState(() => salvando = true);
    try {
      await repo.receberMaleta(
        fornecedorId: fornecedorId!,
        nomeLote: nome.text,
        contrato: contrato.text,
        numeroMostruario: mostruario.text,
        recebidaEm: recebimento,
        recolhimentoPrevisto: troca,
        dataPagamento: pagamento,
        observacoes: observacoes.text,
        arquivoOrigem: arquivo,
        pecas: itens,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(conferindo ? 'Conferir remessa' : 'Nova remessa'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: fornecedorId,
          decoration: const InputDecoration(
            labelText: 'Fornecedor/representante',
          ),
          items: fornecedores
              .map(
                (f) => DropdownMenuItem(
                  value: f['id'] as String,
                  child: Text('${f['nome']}'),
                ),
              )
              .toList(),
          onChanged: conferindo
              ? null
              : (value) => setState(() => fornecedorId = value),
        ),
        _field(nome, 'Nome da remessa'),
        _field(contrato, 'Contrato'),
        _field(mostruario, 'Número do mostruário'),
        ListTile(
          title: const Text('Recebimento'),
          subtitle: Text(_formatDate(recebimento)),
          onTap: () => _date('recebimento'),
        ),
        ListTile(
          title: const Text('Troca prevista'),
          subtitle: Text(troca == null ? 'Não informada' : _formatDate(troca!)),
          onTap: () => _date('troca'),
        ),
        ListTile(
          title: const Text('Data de pagamento'),
          subtitle: Text(
            pagamento == null ? 'Não informada' : _formatDate(pagamento!),
          ),
          onTap: () => _date('pagamento'),
        ),
        _field(observacoes, 'Observações'),
        const SizedBox(height: 12),
        if (!conferindo) ...[
          OutlinedButton.icon(
            onPressed: _selecionarArquivo,
            icon: const Icon(Icons.upload_file),
            label: const Text('Selecionar foto/imagem/PDF'),
          ),
          if (arquivo != null)
            Text(
              'Arquivo selecionado. Toda extração deve ser conferida.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
        const Divider(height: 32),
        Row(
          children: [
            Expanded(
              child: Text(
                'Itens (${itens.length} linhas)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Adicionar item',
              onPressed: () => _editarItem(),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        ...itens.indexed.map(
          (entry) => Card(
            child: ListTile(
              title: Text('${entry.$2['codigo']} • ${entry.$2['nome']}'),
              subtitle: Text(
                '${entry.$2['quantidade']} un. • R\$ ${entry.$2['preco']}',
              ),
              onTap: () => _editarItem(entry.$1),
              trailing: IconButton(
                tooltip: 'Excluir item',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => itens.removeAt(entry.$1)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: salvando
              ? null
              : conferindo
              ? _confirmar
              : () => setState(() => conferindo = true),
          child: Text(
            salvando
                ? 'Salvando...'
                : conferindo
                ? 'Confirmar remessa'
                : 'Conferir remessa',
          ),
        ),
      ],
    ),
  );

  static String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}
