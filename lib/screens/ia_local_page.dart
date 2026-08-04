import 'package:flutter/material.dart';

import '../services/ia_local_service.dart';
import '../services/ia_command_service.dart';
import '../services/session_controller.dart';
import '../services/external_action_service.dart';
import 'agenda_page.dart';
import 'clientes_page.dart';
import 'produtos_loja_page.dart';
import 'comandas_loja_page.dart';
import 'joias_consignadas_page.dart';

class IaLocalPage extends StatefulWidget {
  const IaLocalPage({super.key});

  @override
  State<IaLocalPage> createState() => _IaLocalPageState();
}

class _IaLocalPageState extends State<IaLocalPage> {
  final _service = IaLocalService();
  final _commands = IaCommandService();
  final _controller = TextEditingController();
  final _messages = <({bool user, String text})>[];
  bool _sending = false;

  static const _prompts = [
    'Como está minha agenda hoje?',
    'Quais produtos estão acabando?',
    'Como estão as contas a receber?',
    'Quantas comandas tenho?',
    'Quantas joias consignadas estão disponíveis?',
  ];

  Future<void> _send([String? prompt]) async {
    final text = (prompt ?? _controller.text).trim();
    if (text.isEmpty || _sending) {
      return;
    }
    setState(() {
      _sending = true;
      _messages.add((user: true, text: text));
      _controller.clear();
    });
    try {
      final user = SessionController.instance.usuario!;
      final preview = await _commands.prepare(
        text,
        unitId: SessionController.instance.unidadeAtiva,
      );
      if (preview != null) {
        if (!preview.ready) {
          final answer =
              '${preview.summary}\n\nInforme somente os campos faltantes e refaça o comando.';
          if (mounted) {
            setState(() => _messages.add((user: false, text: answer)));
          }
        } else {
          final confirmed = await _confirmCommand(preview);
          if (confirmed == true) {
            final result = await _commands.execute(preview);
            if (mounted) {
              setState(
                () => _messages.add((user: false, text: result.message)),
              );
            }
          } else if (mounted) {
            setState(
              () => _messages.add((
                user: false,
                text: 'Ação cancelada. Nenhum dado foi alterado.',
              )),
            );
          }
        }
      } else {
        final answer = await _service.conversar(text, user.comercioId);
        if (mounted) setState(() => _messages.add((user: false, text: answer)));
      }
    } catch (error) {
      if (mounted) setState(() => _messages.add((user: false, text: '$error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<bool?> _confirmCommand(IaCommandPreview preview) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirme antes de executar'),
      content: SingleChildScrollView(child: SelectableText(preview.summary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Editar informações'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirmar ação'),
        ),
      ],
    ),
  );
  Future<void> _open(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  Future<void> _prepare(String type) async {
    final text = type == 'lembrete'
        ? 'Olá! Este é um lembrete preparado pelo StudioFlow sobre seu próximo atendimento.'
        : 'Olá! Identificamos um saldo pendente no StudioFlow. Podemos combinar o pagamento?';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Prévia de $type'),
        content: SelectableText(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Editar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await const ExternalActionService().copiar(text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('IA StudioFlow')),
    body: Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            scrollDirection: Axis.horizontal,
            itemCount: _prompts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, index) => ActionChip(
              label: Text(_prompts[index]),
              onPressed: () => _send(_prompts[index]),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              ActionChip(
                label: const Text('Abrir agenda'),
                onPressed: () => _open(const AgendaPage()),
              ),
              ActionChip(
                label: const Text('Abrir cliente'),
                onPressed: () => _open(const ClientesPage()),
              ),
              ActionChip(
                label: const Text('Estoque baixo'),
                onPressed: () =>
                    _open(const ProdutosLojaPage(somenteBaixo: true)),
              ),
              ActionChip(
                label: const Text('Abrir comanda'),
                onPressed: () => _open(const ComandasLojaPage()),
              ),
              ActionChip(
                label: const Text('Lote de joias'),
                onPressed: () => _open(const JoiasConsignadasPage()),
              ),
              ActionChip(
                label: const Text('Criar/remarcar/confirmar/cancelar'),
                onPressed: () => _open(const AgendaPage()),
              ),
              ActionChip(
                label: const Text('Preparar lembrete'),
                onPressed: () => _prepare('lembrete'),
              ),
              ActionChip(
                label: const Text('Preparar cobrança'),
                onPressed: () => _prepare('cobrança'),
              ),
              ActionChip(
                label: const Text('Comparar preços'),
                onPressed: () =>
                    _open(const ProdutosLojaPage(somenteBaixo: true)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Text(
                    'Pergunte sobre agenda, clientes, estoque, comandas, consignações ou financeiro.',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (_, index) {
                    final message = _messages[index];
                    return Align(
                      alignment: message.user
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Card(
                        color: message.user
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(message.text),
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Pergunte à IA StudioFlow',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
