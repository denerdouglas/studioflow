import 'package:flutter/material.dart';

import '../repositories/notification_center_repository.dart';
import '../repositories/agenda_repository.dart';
import 'accounts_payable_page.dart';
import 'agenda_page.dart';
import 'financeiro_page.dart';
import 'clientes_360_page.dart';
import 'produtos_loja_page.dart';

class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({super.key});

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  final _repository = NotificationCenterRepository();
  late Future<List<Map<String, Object?>>> _items = _repository.list();

  Future<void> _read(Map<String, Object?> item) async {
    await _repository.markRead(item['id'] as String);
    if (!mounted) return;
    setState(() => _items = _repository.list());
    final entity = item['entidade'] as String?;
    final entityId = item['referencia_id'] as String?;
    if (entity == null ||
        entityId == null ||
        !await _repository.entityBelongsToBusiness(entity, entityId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Este item não está mais disponível.')),
        );
      }
      return;
    }
    if (!mounted) return;
    Widget? page;
    if (entity == 'appointment') {
      final appointment = await AgendaRepository().buscarPorId(entityId);
      if (appointment != null) {
        page = AgendaPage(
          agendamentoInicialId: entityId,
          dataInicial: appointment.inicio,
        );
      }
    } else if (entity == 'account_payable') {
      page = AccountsPayablePage(accountId: entityId);
    } else if (entity == 'financial_movement') {
      page = FinanceiroPage(movementId: entityId);
    } else if (entity == 'client') {
      page = Cliente360DetalhePage(clienteId: entityId);
    } else if (entity == 'stock_product') {
      page = ProdutoDetalhePage(produtoId: entityId);
    }
    if (page != null && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => page!),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notificações')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _items,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return const Center(child: Text('Nenhuma notificação.'));
        }
        return RefreshIndicator(
          onRefresh: () async => setState(() => _items = _repository.list()),
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              final read = item['read_at'] != null || item['status'] == 'lida';
              return ListTile(
                leading: Icon(
                  read ? Icons.notifications_none : Icons.notifications_active,
                ),
                title: Text(
                  item['titulo'] as String,
                  style: TextStyle(
                    fontWeight: read ? FontWeight.normal : FontWeight.bold,
                  ),
                ),
                subtitle: Text(item['mensagem'] as String),
                onTap: () => _read(item),
              );
            },
          ),
        );
      },
    ),
  );
}
