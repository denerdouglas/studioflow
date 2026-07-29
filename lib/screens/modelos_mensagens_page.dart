import 'package:flutter/material.dart';

import '../models/domain/mensagem_modelo.dart';
import '../repositories/modelos_mensagens_repository.dart';
import '../services/backend_sync_service.dart';
import '../services/mensagem_service.dart';
import '../services/session_controller.dart';
import '../widgets/mensagem_revisao_dialog.dart';

class ModelosMensagensPage extends StatefulWidget {
  const ModelosMensagensPage({super.key});

  @override
  State<ModelosMensagensPage> createState() => _ModelosMensagensPageState();
}

class _ModelosMensagensPageState extends State<ModelosMensagensPage> {
  final _repository = ModelosMensagensRepository();
  List<ModeloMensagem> _modelos = [];
  bool _carregando = true;

  String get _comercioId => SessionController.instance.usuario!.comercioId;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final modelos = await _repository.listar(_comercioId);
    if (mounted) {
      setState(() {
        _modelos = modelos;
        _carregando = false;
      });
    }
  }

  DadosMensagem get _exemplo => const DadosMensagem(
    cliente: 'Mariana',
    salao: 'StudioFlow',
    data: '25/07/2026',
    hora: '14:00',
    profissional: 'Rafa',
    servico: 'Manicure',
    formaPagamento: 'Pix',
    valorPago: 81,
    valorSinal: 20,
    pix: 'contato@studioflow.com',
    nomeRecebedor: 'StudioFlow',
    banco: 'Banco Exemplo',
    endereco: 'Rua das Flores, 100, Centro',
    pontoReferencia: 'Ao lado da praça',
    linkRota: 'https://maps.google.com',
    telefoneSalao: '(11) 99999-9999',
    servicos: [
      ItemResumoMensagem(
        nome: 'Manicure',
        valorUnitario: 40,
        profissional: 'Rafa',
      ),
    ],
    produtos: [
      ItemResumoMensagem(nome: 'Óleo Reparador', valorUnitario: 25),
      ItemResumoMensagem(nome: 'Esmalte', quantidade: 2, valorUnitario: 8),
    ],
  );

  Future<void> _editar(ModeloMensagem modelo) async {
    final nome = TextEditingController(text: modelo.nome);
    final texto = TextEditingController(text: modelo.texto);
    var ativo = modelo.ativo;
    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Editar modelo'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nome,
                    decoration: const InputDecoration(labelText: 'Nome'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: texto,
                    maxLines: 14,
                    decoration: const InputDecoration(
                      labelText: 'Mensagem',
                      alignLabelWithHint: true,
                    ),
                  ),
                  SwitchListTile(
                    value: ativo,
                    title: const Text('Modelo ativo'),
                    onChanged: (v) => setLocal(() => ativo = v),
                  ),
                ],
              ),
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
    if (salvar == true && texto.text.trim().isNotEmpty) {
      await _repository.salvar(
        ModeloMensagem(
          id: modelo.id,
          comercioId: modelo.comercioId,
          chave: modelo.chave,
          nome: nome.text,
          texto: texto.text,
          textoPadrao: modelo.textoPadrao,
          ativo: ativo,
        ),
      );
      await _carregar();
    }
    nome.dispose();
    texto.dispose();
  }

  Future<void> _restaurar(ModeloMensagem modelo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurar texto padrão?'),
        content: const Text(
          'A versão personalizada deste modelo será substituída.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _repository.restaurar(modelo);
      await _carregar();
    }
  }

  Future<void> _prever(ModeloMensagem modelo, {bool teste = false}) async {
    final mensagem = const MensagemService().montar(modelo.texto, _exemplo);
    await mostrarRevisaoMensagem(
      context,
      titulo: teste ? 'Testar mensagem' : 'Prévia — ${modelo.nome}',
      mensagem: mensagem,
      telefone: '(11) 99999-9999',
    );
  }

  Future<void> _historico() async {
    try {
      final itens = await BackendSyncService().historicoMensagens(_comercioId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Histórico de mensagens automáticas'),
          content: SizedBox(
            width: 620,
            height: 480,
            child: itens.isEmpty
                ? const Center(
                    child: Text('Nenhuma mensagem automática registrada.'),
                  )
                : ListView.builder(
                    itemCount: itens.length,
                    itemBuilder: (context, index) {
                      final item = itens[index];
                      return ListTile(
                        leading: Icon(
                          item['status'] == 'delivered' ||
                                  item['status'] == 'read'
                              ? Icons.done_all
                              : item['status'] == 'error'
                              ? Icons.error_outline
                              : Icons.schedule_send_outlined,
                        ),
                        title: Text(item['kind']?.toString() ?? 'Mensagem'),
                        subtitle: Text(
                          '${item['destinationMasked'] ?? ''} • '
                          '${item['scheduledAt'] ?? ''}\n'
                          '${item['body'] ?? ''}',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          '${item['status'] ?? ''}\n${item['attempts'] ?? 0} tentativa(s)',
                          textAlign: TextAlign.end,
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    } catch (erro) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(erro.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Modelos de mensagens'),
      actions: [
        IconButton(
          tooltip: 'Histórico de envios automáticos',
          onPressed: _historico,
          icon: const Icon(Icons.history),
        ),
      ],
    ),
    body: _carregando
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: _modelos.length,
            itemBuilder: (context, index) {
              final modelo = _modelos[index];
              return Card(
                child: ExpansionTile(
                  leading: Icon(
                    modelo.ativo
                        ? Icons.message_outlined
                        : Icons.comments_disabled_outlined,
                  ),
                  title: Text(modelo.nome),
                  subtitle: Text(modelo.ativo ? 'Ativo' : 'Desativado'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        modelo.texto,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _editar(modelo),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Editar'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _prever(modelo),
                          icon: const Icon(Icons.preview_outlined),
                          label: const Text('Prévia'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _prever(modelo, teste: true),
                          icon: const Icon(Icons.send_outlined),
                          label: const Text('Testar'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await _repository.duplicar(modelo);
                            await _carregar();
                          },
                          icon: const Icon(Icons.copy_all_outlined),
                          label: const Text('Duplicar'),
                        ),
                        TextButton.icon(
                          onPressed: () => _restaurar(modelo),
                          icon: const Icon(Icons.restore),
                          label: const Text('Restaurar padrão'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
  );
}
