import 'package:flutter/material.dart';

import '../repositories/notification_center_repository.dart';

class NotificationPreferencesPage extends StatefulWidget {
  const NotificationPreferencesPage({super.key});

  @override
  State<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends State<NotificationPreferencesPage> {
  final _repository = NotificationCenterRepository();
  final _values = <String, bool>{};

  static const _categories = <String, String>{
    'agenda': 'Agenda',
    'financeiro': 'Financeiro',
    'contas_pagar': 'Contas a pagar',
    'estoque': 'Estoque',
    'sistema': 'Sistema',
  };
  static const _whatsapp = <String, String>{
    'confirmacao_dia_anterior': 'Confirmação dia anterior',
    'lembrete_2h': 'Lembrete 2h antes',
    'cobrancas': 'Cobranças',
    'aniversarios': 'Aniversários',
    'ia_atendimento': 'IA de atendimento',
  };

  Future<bool> _get(String category, String channel) async {
    final key = '$channel:$category';
    return _values[key] ??= await _repository.enabled(category, channel);
  }

  Widget _toggle(String category, String label, String channel) =>
      FutureBuilder<bool>(
        future: _get(category, channel),
        builder: (context, snapshot) => SwitchListTile(
          title: Text(label),
          value: snapshot.data ?? true,
          onChanged: snapshot.hasData
              ? (value) async {
                  await _repository.setEnabled(category, channel, value);
                  setState(() => _values['$channel:$category'] = value);
                }
              : null,
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Preferências de notificação')),
    body: ListView(
      children: [
        const ListTile(title: Text('Notificações no celular')),
        for (final entry in _categories.entries)
          _toggle(entry.key, entry.value, 'local'),
        const Divider(),
        const ListTile(title: Text('WhatsApp')),
        for (final entry in _whatsapp.entries)
          _toggle(entry.key, entry.value, 'whatsapp'),
      ],
    ),
  );
}
