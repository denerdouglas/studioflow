import 'package:flutter/material.dart';

import '../models/domain/configuracao_comercio.dart';
import '../repositories/aniversarios_repository.dart';
import '../repositories/configuracoes_repository.dart';
import '../services/external_action_service.dart';
import '../services/session_controller.dart';

class AniversariosPage extends StatefulWidget {
  const AniversariosPage({super.key});

  @override
  State<AniversariosPage> createState() => _AniversariosPageState();
}

class _AniversariosPageState extends State<AniversariosPage> {
  final _repository = AniversariosRepository();
  final _acoes = const ExternalActionService();
  bool _carregando = true;
  String? _erro;
  String _salao = 'StudioFlow';
  List<AniversarianteResumo> _itens = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final comercioId = SessionController.instance.usuario!.comercioId;
      final resultados = await Future.wait([
        _repository.listarDoDia(),
        ConfiguracoesRepository().carregar(comercioId),
      ]);
      if (!mounted) return;
      setState(() {
        _itens = resultados[0] as List<AniversarianteResumo>;
        _salao = (resultados[1] as ConfiguracaoComercio).nomeExibicao;
      });
    } catch (erro) {
      if (mounted) setState(() => _erro = erro.toString());
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String _parabens(AniversarianteResumo item) =>
      'Parabéns, ${item.nome}! 🎉 A equipe do $_salao deseja um novo ciclo '
      'cheio de alegria. Será um prazer receber você novamente!';

  Future<void> _whatsApp(AniversarianteResumo item, String mensagem) async {
    if (item.telefone.trim().isEmpty) {
      _mensagem('Esta cliente não possui telefone cadastrado.');
      return;
    }
    await _acoes.abrirWhatsApp(telefone: item.telefone, mensagem: mensagem);
  }

  Future<void> _oferta(AniversarianteResumo item, String tipo) async {
    final conteudo = TextEditingController(
      text: tipo == 'cupom'
          ? 'Seu cupom de aniversário: ANIVERSARIO10 (10% de desconto).'
          : 'Preparamos um presente especial de aniversário para você!',
    );
    final link = TextEditingController();
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tipo == 'cupom' ? 'Enviar cupom' : 'Enviar presente'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: conteudo,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Mensagem, desconto ou presente',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: link,
                decoration: const InputDecoration(
                  labelText: 'Link de imagem/agendamento (opcional)',
                ),
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
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (confirmou == true && conteudo.text.trim().isNotEmpty) {
      final complemento = link.text.trim().isEmpty
          ? ''
          : '\n${link.text.trim()}';
      await _whatsApp(
        item,
        'Olá, ${item.nome}! ${conteudo.text.trim()}$complemento\nEquipe $_salao.',
      );
    }
    conteudo.dispose();
    link.dispose();
  }

  Future<void> _agendar(AniversarianteResumo item) async {
    final agora = DateTime.now();
    final data = await showDatePicker(
      context: context,
      initialDate: agora.add(const Duration(days: 1)),
      firstDate: agora,
      lastDate: agora.add(const Duration(days: 365)),
    );
    if (data == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (hora == null) return;
    final quando = DateTime(
      data.year,
      data.month,
      data.day,
      hora.hour,
      hora.minute,
    );
    try {
      await _repository.agendarContato(
        clienteId: item.clienteId,
        quando: quando,
        observacao: 'Contato de aniversário com ${item.nome}',
      );
      _mensagem('Contato agendado e salvo no aparelho.');
    } catch (erro) {
      _mensagem(erro.toString());
    }
  }

  void _mensagem(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  String _data(DateTime? valor) {
    if (valor == null) return 'Nenhum atendimento concluído';
    return '${valor.day.toString().padLeft(2, '0')}/'
        '${valor.month.toString().padLeft(2, '0')}/${valor.year}';
  }

  String _tempo(int meses) {
    if (meses < 12) return '$meses ${meses == 1 ? 'mês' : 'meses'}';
    final anos = meses ~/ 12;
    final resto = meses % 12;
    return resto == 0
        ? '$anos ${anos == 1 ? 'ano' : 'anos'}'
        : '$anos ano(s) e $resto mês(es)';
  }

  @override
  Widget build(BuildContext context) {
    final hoje = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aniversários de hoje'),
        actions: [
          IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_erro!),
              ),
            )
          : _itens.isEmpty
          ? const Center(child: Text('Nenhuma cliente aniversaria hoje.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _itens.length,
              itemBuilder: (context, index) {
                final item = _itens[index];
                final idade = item.idadeEm(hoje);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.nome,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          idade == null ? 'Idade não informada' : '$idade anos',
                        ),
                        Text(
                          'Cliente há ${_tempo(item.mesesComoCliente(hoje))}',
                        ),
                        Text(
                          'Último atendimento: ${_data(item.ultimoAtendimento)}',
                        ),
                        Text(
                          'Valor gasto: R\$ ${item.valorGasto.toStringAsFixed(2).replaceAll('.', ',')}',
                        ),
                        Text('Serviços favoritos: ${item.servicosFavoritos}'),
                        const Divider(height: 24),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _whatsApp(item, _parabens(item)),
                              icon: const Icon(Icons.chat_outlined),
                              label: const Text('WhatsApp'),
                            ),
                            FilledButton.icon(
                              onPressed: () => _whatsApp(item, _parabens(item)),
                              icon: const Icon(Icons.celebration_outlined),
                              label: const Text('Parabéns'),
                            ),
                            OutlinedButton(
                              onPressed: () => _oferta(item, 'cupom'),
                              child: const Text('Cupom'),
                            ),
                            OutlinedButton(
                              onPressed: () => _oferta(item, 'presente'),
                              child: const Text('Presente'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                if (!await _acoes.ligar(item.telefone)) {
                                  _mensagem(
                                    'Telefone indisponível para ligação.',
                                  );
                                }
                              },
                              icon: const Icon(Icons.phone_outlined),
                              label: const Text('Ligar'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _agendar(item),
                              icon: const Icon(Icons.event_outlined),
                              label: const Text('Agendar contato'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
