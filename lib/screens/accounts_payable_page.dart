import 'package:flutter/material.dart';

import '../repositories/accounts_payable_repository.dart';
import '../services/session_controller.dart';

class AccountsPayablePage extends StatefulWidget {
  final String? accountId;
  const AccountsPayablePage({super.key, this.accountId});

  @override
  State<AccountsPayablePage> createState() => _AccountsPayablePageState();
}

class _AccountsPayablePageState extends State<AccountsPayablePage> {
  final _repository = AccountsPayableRepository();
  String? _type;
  String? _status;
  late Future<List<AccountPayable>> _items = _load();
  late Future<AccountsPayableSummary> _summary = _repository.summary();

  Future<List<AccountPayable>> _load() async {
    await _repository.refreshOverdue();
    if (widget.accountId != null) {
      final item = await _repository.get(widget.accountId!);
      return item == null ? [] : [item];
    }
    return _repository.list(type: _type, status: _status);
  }

  void _refresh() => setState(() {
    _items = _load();
    _summary = _repository.summary();
  });

  Future<void> _edit(AccountPayable item) async {
    final description = TextEditingController(text: item.description);
    final category = TextEditingController(text: item.category);
    final supplier = TextEditingController(text: item.supplier);
    final amount = TextEditingController(text: item.amount.toStringAsFixed(2));
    final payment = TextEditingController(text: item.paymentMethod);
    final notes = TextEditingController(text: item.notes);
    var due = item.dueDate;
    var type = item.type;
    var recurrence = item.recurrence;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Editar conta'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final field in [
                  (description, 'Descrição'),
                  (category, 'Categoria'),
                  (supplier, 'Fornecedor'),
                  (amount, 'Valor'),
                  (payment, 'Forma de pagamento'),
                  (notes, 'Observação'),
                ])
                  TextField(
                    controller: field.$1,
                    decoration: InputDecoration(labelText: field.$2),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  items: const [
                    DropdownMenuItem(value: 'fixa', child: Text('Fixa')),
                    DropdownMenuItem(
                      value: 'variavel',
                      child: Text('Variável'),
                    ),
                  ],
                  onChanged: (value) => setLocal(() => type = value!),
                ),
                if (type == 'fixa')
                  DropdownButtonFormField<String>(
                    initialValue: recurrence,
                    items: const [
                      DropdownMenuItem(
                        value: 'semanal',
                        child: Text('Semanal'),
                      ),
                      DropdownMenuItem(
                        value: 'quinzenal',
                        child: Text('Quinzenal'),
                      ),
                      DropdownMenuItem(value: 'mensal', child: Text('Mensal')),
                      DropdownMenuItem(value: 'anual', child: Text('Anual')),
                    ],
                    onChanged: (value) => recurrence = value!,
                  ),
                ListTile(
                  title: const Text('Vencimento'),
                  subtitle: Text('${due.day}/${due.month}/${due.year}'),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: due,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 3650),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (selected != null) setLocal(() => due = selected);
                  },
                ),
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
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    final value = double.tryParse(amount.text.replaceAll(',', '.'));
    if (value == null || value <= 0 || description.text.trim().isEmpty) return;
    await _repository.save(
      item.copyWith(
        description: description.text.trim(),
        category: category.text.trim(),
        supplier: supplier.text.trim(),
        amount: value,
        dueDate: due,
        type: type,
        recurrence: type == 'fixa' ? recurrence : 'nenhuma',
        paymentMethod: payment.text.trim(),
        notes: notes.text.trim(),
      ),
    );
    _refresh();
  }

  Future<void> _create() async {
    final description = TextEditingController();
    final amount = TextEditingController();
    var type = 'variavel';
    var recurrence = 'nenhuma';
    var due = DateTime.now();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Nova conta a pagar'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Descrição'),
                ),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Valor'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(value: 'fixa', child: Text('Fixa')),
                    DropdownMenuItem(
                      value: 'variavel',
                      child: Text('Variável'),
                    ),
                  ],
                  onChanged: (value) => setLocal(() => type = value!),
                ),
                if (type == 'fixa')
                  DropdownButtonFormField<String>(
                    initialValue: recurrence,
                    decoration: const InputDecoration(labelText: 'Recorrência'),
                    items: const [
                      DropdownMenuItem(
                        value: 'semanal',
                        child: Text('Semanal'),
                      ),
                      DropdownMenuItem(
                        value: 'quinzenal',
                        child: Text('Quinzenal'),
                      ),
                      DropdownMenuItem(value: 'mensal', child: Text('Mensal')),
                      DropdownMenuItem(value: 'anual', child: Text('Anual')),
                    ],
                    onChanged: (value) => recurrence = value!,
                  ),
                ListTile(
                  title: const Text('Vencimento'),
                  subtitle: Text('${due.day}/${due.month}/${due.year}'),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: due,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (selected != null) setLocal(() => due = selected);
                  },
                ),
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
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    final value = double.tryParse(amount.text.replaceAll(',', '.'));
    if (description.text.trim().isEmpty || value == null || value <= 0) return;
    final now = DateTime.now();
    await _repository.save(
      AccountPayable(
        id: 'account_${now.microsecondsSinceEpoch}',
        businessId: SessionController.instance.usuario!.comercioId,
        description: description.text.trim(),
        category: 'Outros',
        amount: value,
        type: type,
        dueDate: due,
        recurrence: type == 'fixa' ? recurrence : 'nenhuma',
        createdAt: now,
        updatedAt: now,
      ),
    );
    _refresh();
  }

  Future<void> _action(AccountPayable item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar conta'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Marcar como paga'),
              onTap: () => Navigator.pop(context, 'paid'),
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Cancelar conta'),
              onTap: () => Navigator.pop(context, 'cancel'),
            ),
          ],
        ),
      ),
    );
    if (action == 'edit') await _edit(item);
    if (action == 'paid') await _repository.markPaid(item.id, 'Não informado');
    if (action == 'cancel') await _repository.cancel(item.id);
    _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Contas a pagar')),
    body: Column(
      children: [
        FutureBuilder<AccountsPayableSummary>(
          future: _summary,
          builder: (context, snapshot) {
            final value = snapshot.data;
            if (value == null) return const LinearProgressIndicator();
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  _SummaryCard('Vence hoje', '${value.dueToday}'),
                  _SummaryCard('Vence amanhã', '${value.dueTomorrow}'),
                  _SummaryCard('Vencidas', '${value.overdue}'),
                  _SummaryCard(
                    'Pendente no mês',
                    'R\$ ${value.pendingMonth.toStringAsFixed(2)}',
                  ),
                  _SummaryCard(
                    'Pago no mês',
                    'R\$ ${value.paidMonth.toStringAsFixed(2)}',
                  ),
                ],
              ),
            );
          },
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              for (final entry in const {
                'Todas': null,
                'Fixas': 'fixa',
                'Variáveis': 'variavel',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.key),
                    selected: _type == entry.value,
                    onSelected: (_) {
                      _type = entry.value;
                      _refresh();
                    },
                  ),
                ),
              PopupMenuButton<String?>(
                tooltip: 'Status',
                onSelected: (value) {
                  _status = value;
                  _refresh();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: null, child: Text('Todos os status')),
                  PopupMenuItem(value: 'pendente', child: Text('Pendentes')),
                  PopupMenuItem(value: 'vencida', child: Text('Vencidas')),
                  PopupMenuItem(value: 'paga', child: Text('Pagas')),
                  PopupMenuItem(value: 'cancelada', child: Text('Canceladas')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AccountPayable>>(
            future: _items,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.isEmpty) {
                return const Center(child: Text('Nenhuma conta encontrada.'));
              }
              return ListView.builder(
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  final item = snapshot.data![index];
                  return ListTile(
                    title: Text(item.description),
                    subtitle: Text(
                      '${item.dueDate.day}/${item.dueDate.month}/${item.dueDate.year} • ${item.status}',
                    ),
                    trailing: Text('R\$ ${item.amount.toStringAsFixed(2)}'),
                    onTap: () => _action(item),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.add),
      label: const Text('Nova conta'),
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryCard(this.label, this.value);

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    ),
  );
}
