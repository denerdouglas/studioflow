import 'package:flutter/material.dart';

import '../repositories/consignacao_acerto_repository.dart';

class ConsignacaoAcertoPage extends StatefulWidget {
  final String remessaId;
  const ConsignacaoAcertoPage({super.key, required this.remessaId});

  @override
  State<ConsignacaoAcertoPage> createState() => _ConsignacaoAcertoPageState();
}

class _ConsignacaoAcertoPageState extends State<ConsignacaoAcertoPage> {
  final repository = ConsignacaoAcertoRepository();
  final supplierQuantity = TextEditingController();
  final supplierValue = TextEditingController();
  final commissionPercent = TextEditingController();
  final commissionValue = TextEditingController();
  final transfer = TextEditingController(text: '0');
  final discount = TextEditingController(text: '0');
  final fees = TextEditingController(text: '0');
  final adjustments = TextEditingController(text: '0');
  final losses = TextEditingController(text: '0');
  final notes = TextEditingController();
  final responsible = TextEditingController();
  Map<String, Object?>? summary;
  Map<String, Object?>? settlement;
  DateTime? settlementDate;
  DateTime? paymentDate;
  bool confirmDivergence = false;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_refresh);
    }
    _load();
  }

  List<TextEditingController> get _controllers => [
    supplierQuantity,
    supplierValue,
    commissionPercent,
    commissionValue,
    transfer,
    discount,
    fees,
    adjustments,
    losses,
    notes,
    responsible,
  ];

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final values = await Future.wait([
      repository.resumoRemessa(widget.remessaId),
      repository.carregar(widget.remessaId),
    ]);
    summary = values[0];
    settlement = values[1];
    responsible.text = repository.responsavelAtual;
    final data = settlement;
    if (data != null) {
      supplierQuantity.text = '${data['quantidade_fornecedor'] ?? ''}';
      supplierValue.text = '${data['valor_fornecedor'] ?? ''}';
      commissionPercent.text = '${data['comissao_percentual'] ?? ''}';
      commissionValue.text = '${data['comissao_valor'] ?? ''}';
      transfer.text = '${data['repasse'] ?? 0}';
      discount.text = '${data['desconto'] ?? 0}';
      fees.text = '${data['taxas'] ?? 0}';
      adjustments.text = '${data['ajustes'] ?? 0}';
      losses.text = '${data['perdas_financeiras'] ?? 0}';
      notes.text = '${data['observacoes'] ?? ''}';
      responsible.text =
          '${data['responsavel_id'] ?? repository.responsavelAtual}';
      confirmDivergence = data['divergencia_confirmada'] == 1;
      settlementDate = DateTime.tryParse('${data['data_acerto'] ?? ''}');
      paymentDate = DateTime.tryParse('${data['data_pagamento'] ?? ''}');
    }
    if (mounted) setState(() {});
  }

  double _n(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0;
  double get sold => (summary?['valor_vendido'] as num?)?.toDouble() ?? 0;
  double get result =>
      sold -
      _n(transfer) -
      _n(losses) -
      _n(fees) +
      _n(discount) +
      _n(adjustments);
  int? get quantityDifference => int.tryParse(supplierQuantity.text) == null
      ? null
      : int.parse(supplierQuantity.text) -
            ((summary?['vendidas'] as num?)?.toInt() ?? 0);
  double? get valueDifference =>
      supplierValue.text.trim().isEmpty ? null : _n(supplierValue) - sold;

  Future<Map<String, Object?>?> _save() async {
    setState(() => busy = true);
    try {
      final saved = await repository.salvar(
        widget.remessaId,
        ConsignacaoAcertoInput(
          responsavelId: responsible.text,
          quantidadeFornecedor: int.tryParse(supplierQuantity.text),
          valorFornecedor: supplierValue.text.trim().isEmpty
              ? null
              : _n(supplierValue),
          comissaoPercentual: commissionPercent.text.trim().isEmpty
              ? null
              : _n(commissionPercent),
          comissaoValor: commissionValue.text.trim().isEmpty
              ? null
              : _n(commissionValue),
          repasse: _n(transfer),
          desconto: _n(discount),
          taxas: _n(fees),
          ajustes: _n(adjustments),
          perdasFinanceiras: _n(losses),
          dataAcerto: settlementDate,
          dataPagamento: paymentDate,
          observacoes: notes.text,
          confirmarDivergencia: confirmDivergence,
        ),
      );
      settlement = saved;
      if (mounted) setState(() {});
      return saved;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _action(String action) async {
    try {
      final saved = await _save();
      if (saved == null) return;
      final id = saved['id'] as String;
      if (action == 'conferido') await repository.marcarConferido(id);
      if (action == 'pago') {
        await repository.marcarConferido(id);
        await repository.pagar(id);
      }
      if (action == 'fechado') await repository.fechar(id);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Acerto da remessa')),
    body: summary == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Status: ${settlement?['status'] ?? 'em_aberto'}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'Recebidas: ${summary!['recebidas']}  Vendidas: ${summary!['vendidas']}  Devolvidas: ${summary!['devolvidas']}',
              ),
              Text(
                'Faltantes/perdas: ${summary!['perdas']}  Vendido StudioFlow: R\$ ${sold.toStringAsFixed(2)}',
              ),
              const Divider(),
              _field(supplierQuantity, 'Quantidade informada pela fornecedora'),
              _field(supplierValue, 'Valor informado pela fornecedora'),
              _field(commissionPercent, 'Comissão percentual'),
              _field(commissionValue, 'Comissão em valor'),
              _field(transfer, 'Repasse'),
              _field(discount, 'Desconto'),
              _field(fees, 'Taxas'),
              _field(adjustments, 'Ajustes (+/-)'),
              _field(losses, 'Perdas financeiras'),
              ListTile(
                title: const Text('Data do acerto'),
                subtitle: Text('${settlementDate ?? 'Não informada'}'),
                onTap: () => _date(false),
              ),
              ListTile(
                title: const Text('Data do pagamento'),
                subtitle: Text('${paymentDate ?? 'Não informada'}'),
                onTap: () => _date(true),
              ),
              TextField(
                controller: notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Observações'),
              ),
              _field(responsible, 'Responsável', numeric: false),
              const Divider(),
              Text('Diferença quantidade: ${quantityDifference ?? '-'}'),
              Text(
                'Diferença valor: ${valueDifference?.toStringAsFixed(2) ?? '-'}',
              ),
              CheckboxListTile(
                value: confirmDivergence,
                onChanged: (v) =>
                    setState(() => confirmDivergence = v ?? false),
                title: const Text('Confirmar divergência explicitamente'),
              ),
              Text(
                'Resultado líquido: R\$ ${result.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: busy ? null : () => _action('salvar'),
                    child: const Text('Salvar'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => _action('conferido'),
                    child: const Text('Marcar conferido'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => _action('pago'),
                    child: const Text('Registrar pagamento'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => _action('fechado'),
                    child: const Text('Fechar acerto'),
                  ),
                ],
              ),
            ],
          ),
  );

  Widget _field(TextEditingController c, String label, {bool numeric = true}) =>
      TextField(
        controller: c,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        decoration: InputDecoration(labelText: label),
      );
  Future<void> _date(bool payment) async {
    final value = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: DateTime.now(),
    );
    if (value != null) {
      setState(() => payment ? paymentDate = value : settlementDate = value);
    }
  }
}
