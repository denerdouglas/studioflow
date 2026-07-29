import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../repositories/agenda_completa_repository.dart';

class LinkAgendamentoPage extends StatefulWidget {
  const LinkAgendamentoPage({super.key});
  @override
  State<LinkAgendamentoPage> createState() => _LinkAgendamentoPageState();
}

class _LinkAgendamentoPageState extends State<LinkAgendamentoPage> {
  final _repository = AgendaCompletaRepository();
  final _politica = TextEditingController();
  bool _exigeSinal = false;
  String? _token;

  Future<void> _gerar() async {
    final token = await _repository.criarRascunhoLinkPublico(
      politicaCancelamento: _politica.text,
      exigeSinal: _exigeSinal,
    );
    if (mounted) setState(() => _token = token);
  }

  @override
  void dispose() {
    _politica.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Link público de agendamento')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Card(
          child: ListTile(
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Backend público ainda não conectado'),
            subtitle: Text(
              'O cliente não precisará instalar o aplicativo. Nesta versão, o StudioFlow cria e salva o rascunho seguro; a URL pública dependerá do backend.',
            ),
          ),
        ),
        TextField(
          controller: _politica,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Política de cancelamento exibida ao cliente',
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _exigeSinal,
          title: const Text('Exigir sinal quando o backend estiver conectado'),
          onChanged: (v) => setState(() => _exigeSinal = v),
        ),
        FilledButton.icon(
          onPressed: _gerar,
          icon: const Icon(Icons.link),
          label: const Text('Criar rascunho de link'),
        ),
        if (_token != null)
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(
              title: const Text('Token do rascunho'),
              subtitle: SelectableText(_token!),
              trailing: IconButton(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _token!)),
                icon: const Icon(Icons.copy),
              ),
            ),
          ),
      ],
    ),
  );
}
