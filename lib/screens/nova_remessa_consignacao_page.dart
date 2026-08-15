import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../repositories/consignacao_repository.dart';
import '../models/domain/consignment_document_import.dart';
import '../services/consignment_document_import_service.dart';
import '../models/domain/universal_reader.dart';
import 'vision_scanner_page.dart';

class NovaRemessaConsignacaoPage extends StatefulWidget {
  const NovaRemessaConsignacaoPage({super.key});

  @override
  State<NovaRemessaConsignacaoPage> createState() =>
      _NovaRemessaConsignacaoPageState();
}

class _NovaRemessaConsignacaoPageState
    extends State<NovaRemessaConsignacaoPage> {
  final repo = ConsignacaoRepository();
  final importer = ConsignmentDocumentImportService();
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
  bool importando = false;
  final pendencias = <ConsignmentPendingLine>[];
  String? validacaoDocumento;

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
    await _importar(path);
  }

  Future<void> _importar(String path) async {
    setState(() => importando = true);
    try {
      final data = path.toLowerCase().endsWith('.pdf')
          ? await importer.importPdf(path)
          : await importer.importImage(path);
      if (!mounted) return;
      setState(() {
        arquivo = path;
        itens
          ..clear()
          ..addAll(data.itens.map((item) => item.toPieceMap()));
        pendencias
          ..clear()
          ..addAll(data.linhasPendentes);
        validacaoDocumento = data.divergeDoDeclarado
            ? 'Documento informa ${data.quantidadeDeclarada ?? "?"} itens / R\$ ${_money(data.totalDeclarado)}. '
                  'Importação identificou ${data.quantidadeImportada} itens / R\$ ${_money(data.totalImportado)}. '
                  'Revise antes de confirmar.'
            : null;
        _applyHeader(data);
        conferindo = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Documento analisado:\n'
              '${data.quantidadeImportada} produtos encontrados\n'
              '${data.linhasPendentes.length} pendentes de revisão',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } on ConsignmentImportException catch (error) {
      if (mounted) await _showImportError(error.message, path);
    } catch (_) {
      if (mounted) {
        await _showImportError(
          'Não foi possível extrair os itens deste PDF.',
          path,
        );
      }
    } finally {
      if (mounted) setState(() => importando = false);
    }
  }

  void _applyHeader(ConsignmentDocumentImport data) {
    contrato.text = data.contrato ?? contrato.text;
    mostruario.text = data.mostruario ?? mostruario.text;
    recebimento = data.dataEnvio ?? recebimento;
    troca = data.dataTroca ?? troca;
    pagamento = data.dataPagamento ?? pagamento;
    if (nome.text.trim().isEmpty && data.mostruario != null) {
      nome.text = 'Mostruário ${data.mostruario}';
    }
    final representative = data.representante?.trim();
    if (representative != null && representative.isNotEmpty) {
      final match = fornecedores.where(
        (supplier) =>
            '${supplier['nome']}'.trim().toLowerCase() ==
            representative.toLowerCase(),
      );
      if (match.isNotEmpty) {
        fornecedorId = match.first['id'] as String;
      } else if (!observacoes.text.contains(representative)) {
        observacoes.text = [
          observacoes.text.trim(),
          'Representante identificado: $representative',
        ].where((value) => value.isNotEmpty).join('\n');
      }
    }
    final zone = data.zonaVenda?.trim();
    if (zone != null && zone.isNotEmpty && !observacoes.text.contains(zone)) {
      observacoes.text = [
        observacoes.text.trim(),
        'Zona de venda: $zone',
      ].where((value) => value.isNotEmpty).join('\n');
    }
  }

  Future<void> _showImportError(String message, String path) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Falha na importação'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'manual'),
            child: const Text('Preencher manualmente'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'bip'),
            child: const Text('Cadastrar por Bip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'retry'),
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
    if (action == 'retry') await _importar(path);
    if (action == 'bip') await _cadastrarPorBip();
  }

  Future<void> _cadastrarPorBip() async {
    final readings = await Navigator.push<List<BipSessionItem>>(
      context,
      MaterialPageRoute(
        builder: (_) => VisionScannerPage(
          policy: ReaderContextPolicy.forContext(ReaderContext.consignacao),
        ),
      ),
    );
    if (readings == null || readings.isEmpty || !mounted) return;
    setState(() {
      for (final reading in readings.where((item) => !item.ignored)) {
        final draft = reading.draft;
        itens.add({
          'codigo': draft.referenciaComercial?.value ?? draft.gtin?.value ?? '',
          'categoria': draft.categoriaSugerida?.value ?? '',
          'nome': draft.nome?.value ?? draft.descricao?.value ?? '',
          'descricao': draft.descricao?.value ?? draft.nome?.value ?? '',
          'quantidade': draft.quantidade?.value?.toInt() ?? 1,
          'preco': draft.preco?.value ?? -1,
          'material': draft.material?.value ?? '',
          'observacoes': draft.precisaRevisao ? 'Revisar leitura por Bip' : '',
        });
      }
      conferindo = true;
    });
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

  Future<void> _revisarPendencias() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: FractionallySizedBox(
            heightFactor: .85,
            child: Scaffold(
              appBar: AppBar(title: const Text('Linhas para revisão')),
              body: pendencias.isEmpty
                  ? const Center(child: Text('Nenhuma linha pendente.'))
                  : ListView.builder(
                      itemCount: pendencias.length,
                      itemBuilder: (context, index) {
                        final pending = pendencias[index];
                        return Card(
                          child: ListTile(
                            title: Text('Linha ${pending.lineNumber}'),
                            subtitle: Text(
                              '“${pending.originalText}”\nMotivo: ${pending.reason}',
                            ),
                            isThreeLine: true,
                            trailing: PopupMenuButton<String>(
                              onSelected: (action) async {
                                if (action == 'correct') {
                                  final before = itens.length;
                                  await _editarItem();
                                  if (itens.length == before) return;
                                }
                                setState(() => pendencias.remove(pending));
                                setSheet(() {});
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'correct',
                                  child: Text('Corrigir'),
                                ),
                                PopupMenuItem(
                                  value: 'ignore',
                                  child: Text('Ignorar'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
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
    if (pendencias.isNotEmpty) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Linhas não revisadas'),
          content: Text(
            'Existem ${pendencias.length} linhas não revisadas. '
            'Deseja continuar mesmo assim?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'review'),
              child: const Text('Revisar pendências'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'continue'),
              child: const Text('Continuar sem elas'),
            ),
          ],
        ),
      );
      if (action == 'review') {
        await _revisarPendencias();
        return;
      }
      if (action != 'continue') return;
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
            onPressed: importando ? null : _selecionarArquivo,
            icon: const Icon(Icons.upload_file),
            label: Text(
              importando ? 'Extraindo documento...' : 'Importar documento',
            ),
          ),
          OutlinedButton.icon(
            onPressed: importando ? null : _cadastrarPorBip,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Cadastrar peças por Bip'),
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
                '${itens.fold<int>(0, (sum, item) => sum + ((item['quantidade'] as num?)?.toInt() ?? 0))} itens válidos',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Adicionar item',
              onPressed: () => _editarItem(),
              icon: const Icon(Icons.add_circle_outline),
            ),
            IconButton(
              tooltip: 'Complementar por Bip',
              onPressed: _cadastrarPorBip,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ],
        ),
        if (pendencias.isNotEmpty)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.warning_amber_outlined),
              title: Text('${pendencias.length} linhas não interpretadas'),
              subtitle: const Text('Toque para ver, corrigir ou ignorar.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _revisarPendencias,
            ),
          ),
        if (validacaoDocumento != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('Totais divergentes'),
              subtitle: Text(validacaoDocumento!),
            ),
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

  static String _money(double? value) =>
      value == null ? '?' : value.toStringAsFixed(2).replaceAll('.', ',');
}
