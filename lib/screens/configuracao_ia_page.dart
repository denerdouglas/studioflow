import 'package:flutter/material.dart';

import '../models/domain/atendimento.dart';
import '../repositories/atendimento_ia_repository.dart';
import 'simulador_ia_page.dart';

class ConfiguracaoIaPage extends StatefulWidget {
  const ConfiguracaoIaPage({super.key});
  @override
  State<ConfiguracaoIaPage> createState() => _ConfiguracaoIaPageState();
}

class _ConfiguracaoIaPageState extends State<ConfiguracaoIaPage> {
  final _repository = AtendimentoIaRepository();
  final _nome = TextEditingController();
  final _apresentacao = TextEditingController();
  final _inicio = TextEditingController();
  final _fim = TextEditingController();
  final _politica = TextEditingController();
  final _transferencia = TextEditingController();
  final _palavras = TextEditingController();
  String _estilo = 'descontraido';
  bool _ativo = true;
  bool _carregando = true;
  List<FaqIa> _faqs = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final c = await _repository.carregarConfiguracao();
    final faqs = await _repository.listarFaqs();
    _nome.text = c.nomeIa;
    _apresentacao.text = c.mensagemApresentacao;
    _inicio.text = c.horarioInicio;
    _fim.text = c.horarioFim;
    _politica.text = c.politicaCancelamento;
    _transferencia.text = c.instrucaoTransferencia;
    _palavras.text = c.transferirPalavras;
    if (mounted) {
      setState(() {
        _estilo = c.estiloLinguagem;
        _ativo = c.ativo;
        _faqs = faqs;
        _carregando = false;
      });
    }
  }

  Future<void> _salvar() async {
    if (_nome.text.trim().isEmpty || _apresentacao.text.trim().isEmpty) {
      _mensagem('Informe o nome e a apresentação da assistente.');
      return;
    }
    await _repository.salvarConfiguracao(
      ConfiguracaoIaSalao(
        comercioId: '',
        nomeIa: _nome.text,
        mensagemApresentacao: _apresentacao.text,
        estiloLinguagem: _estilo,
        horarioInicio: _inicio.text,
        horarioFim: _fim.text,
        politicaCancelamento: _politica.text,
        instrucaoTransferencia: _transferencia.text,
        transferirPalavras: _palavras.text,
        ativo: _ativo,
      ),
    );
    _mensagem('Configuração da assistente salva.');
  }

  Future<void> _novoFaq() async {
    final pergunta = TextEditingController();
    final resposta = TextEditingController();
    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pergunta frequente'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pergunta,
                decoration: const InputDecoration(labelText: 'Pergunta'),
              ),
              TextField(
                controller: resposta,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Resposta'),
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
    );
    if (salvar == true) {
      await _repository.salvarFaq(
        FaqIa(id: '', pergunta: pergunta.text, resposta: resposta.text),
      );
      await _carregar();
    }
  }

  void _mensagem(String texto) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(texto)));

  @override
  void dispose() {
    for (final c in [
      _nome,
      _apresentacao,
      _inicio,
      _fim,
      _politica,
      _transferencia,
      _palavras,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Configurar assistente'),
      actions: [
        IconButton(
          tooltip: 'Abrir simulador',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SimuladorIaPage()),
          ),
          icon: const Icon(Icons.forum_outlined),
        ),
      ],
    ),
    body: _carregando
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Card(
                child: ListTile(
                  leading: Icon(Icons.security),
                  title: Text('Modo local seguro'),
                  subtitle: Text(
                    'Nenhuma chave de IA ou WhatsApp está no aplicativo. A integração oficial dependerá de backend.',
                  ),
                ),
              ),
              TextField(
                controller: _nome,
                decoration: const InputDecoration(
                  labelText: 'Nome da assistente',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _apresentacao,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Mensagem de apresentação',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _estilo,
                decoration: const InputDecoration(
                  labelText: 'Estilo de linguagem',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'descontraido',
                    child: Text('Descontraído'),
                  ),
                  DropdownMenuItem(value: 'formal', child: Text('Formal')),
                ],
                onChanged: (v) => setState(() => _estilo = v!),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inicio,
                      decoration: const InputDecoration(labelText: 'Atende de'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _fim,
                      decoration: const InputDecoration(labelText: 'Até'),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: _politica,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Política de cancelamento',
                ),
              ),
              TextField(
                controller: _transferencia,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Mensagem ao transferir para humano',
                ),
              ),
              TextField(
                controller: _palavras,
                decoration: const InputDecoration(
                  labelText: 'Palavras para transferir',
                  helperText: 'Separadas por vírgula',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _ativo,
                title: const Text('Assistente local ativa'),
                onChanged: (v) => setState(() => _ativo = v),
              ),
              FilledButton.icon(
                onPressed: _salvar,
                icon: const Icon(Icons.save),
                label: const Text('Salvar configuração'),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Perguntas frequentes',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(onPressed: _novoFaq, icon: const Icon(Icons.add)),
                ],
              ),
              if (_faqs.isEmpty)
                const Card(
                  child: ListTile(
                    title: Text('Nenhuma pergunta personalizada.'),
                  ),
                ),
              ..._faqs.map(
                (faq) => Card(
                  child: ListTile(
                    title: Text(faq.pergunta),
                    subtitle: Text(faq.resposta),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await _repository.removerFaq(faq.id);
                        await _carregar();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
  );
}
