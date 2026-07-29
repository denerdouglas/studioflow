import 'package:flutter/material.dart';

import '../models/domain/atendimento.dart';
import '../repositories/atendimento_ia_repository.dart';
import '../services/session_controller.dart';

class SimuladorIaPage extends StatefulWidget {
  const SimuladorIaPage({super.key});
  @override
  State<SimuladorIaPage> createState() => _SimuladorIaPageState();
}

class _SimuladorIaPageState extends State<SimuladorIaPage> {
  final _repository = AtendimentoIaRepository();
  final _texto = TextEditingController();
  final _scroll = ScrollController();
  String? _conversaId;
  List<MensagemSimulada> _mensagens = [];
  bool _enviando = false;

  static const _rapidas = [
    'Quero agendar',
    'Quais são os serviços e preços?',
    'Quais profissionais atendem?',
    'Como faço o Pix?',
    'Quero falar com uma pessoa',
  ];

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    final id = await _repository.iniciarConversa();
    final mensagens = await _repository.listarMensagens(id);
    if (mounted) {
      setState(() {
        _conversaId = id;
        _mensagens = mensagens;
      });
    }
  }

  Future<void> _enviar([String? pronta]) async {
    final mensagem = (pronta ?? _texto.text).trim();
    if (mensagem.isEmpty || _conversaId == null || _enviando) return;
    _texto.clear();
    setState(() => _enviando = true);
    try {
      await _repository.responder(
        comercioId: SessionController.instance.usuario!.comercioId,
        conversaId: _conversaId!,
        mensagem: mensagem,
      );
      final dados = await _repository.listarMensagens(_conversaId!);
      if (mounted) setState(() => _mensagens = dados);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  void dispose() {
    _texto.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Simulador da assistente'),
      actions: [
        IconButton(onPressed: _iniciar, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: Column(
      children: [
        const MaterialBanner(
          content: Text(
            'Demonstração local. Nenhuma mensagem é enviada ao WhatsApp.',
          ),
          actions: [SizedBox.shrink()],
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: _rapidas
                .map(
                  (p) => Padding(
                    padding: const EdgeInsets.all(4),
                    child: ActionChip(
                      label: Text(p),
                      onPressed: () => _enviar(p),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Expanded(
          child: _conversaId == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: _mensagens.length,
                  itemBuilder: (context, index) {
                    final m = _mensagens[index];
                    final cliente = m.remetente == 'cliente';
                    return Align(
                      alignment: cliente
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 330),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cliente
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(m.conteudo),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _texto,
                    decoration: const InputDecoration(
                      hintText: 'Digite como se fosse o cliente',
                    ),
                    onSubmitted: (_) => _enviar(),
                  ),
                ),
                IconButton(
                  onPressed: _enviando ? null : _enviar,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
