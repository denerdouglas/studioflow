import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/helpers/app_formatters.dart';
import '../models/domain/atendimento.dart';
import '../repositories/pagamento_repository.dart';
import '../services/external_action_service.dart';

class PagamentosSprint4Page extends StatefulWidget {
  const PagamentosSprint4Page({super.key});
  @override
  State<PagamentosSprint4Page> createState() => _PagamentosSprint4PageState();
}

class _PagamentosSprint4PageState extends State<PagamentosSprint4Page>
    with SingleTickerProviderStateMixin {
  final _repository = PagamentoRepository();
  final _chave = TextEditingController();
  final _nome = TextEditingController();
  final _cidade = TextEditingController();
  final _banco = TextEditingController();
  final _observacoes = TextEditingController();
  final _valorSinalFixo = TextEditingController();
  final _percentualSinal = TextEditingController();
  final _mensagem = TextEditingController();
  final _valorSinal = TextEditingController();
  final _prazo = TextEditingController();
  final _politica = TextEditingController();
  final _link = TextEditingController();
  String _tipoChave = 'aleatoria';
  String _tipoSinal = 'percentual';
  Set<String> _formasAceitas = {'pix', 'dinheiro'};
  final _externo = const ExternalActionService();
  bool _carregando = true;
  List<Cobranca> _cobrancas = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final c = await _repository.carregarConfiguracao();
    final cobrancas = await _repository.listarCobrancas();
    _chave.text = c.chavePix;
    _nome.text = c.nomeRecebedor;
    _cidade.text = c.cidadeRecebedor;
    _banco.text = c.banco;
    _observacoes.text = c.observacoes;
    _valorSinalFixo.text = c.valorSinalFixo.toString();
    _percentualSinal.text = c.percentualSinal.toString();
    _mensagem.text = c.mensagemCobranca;
    _valorSinal.text = c.valorSinal.toString();
    _prazo.text = c.prazoHoras.toString();
    _politica.text = c.politicaCancelamento;
    _link.text = c.linkPagamentoBase;
    if (mounted) {
      setState(() {
        _tipoChave = c.tipoChave;
        _tipoSinal = c.tipoSinal;
        _formasAceitas = {...c.formasAceitas};
        _cobrancas = cobrancas;
        _carregando = false;
      });
    }
  }

  ConfiguracaoPagamento _config() => ConfiguracaoPagamento(
    comercioId: '',
    chavePix: _chave.text,
    tipoChave: _tipoChave,
    nomeRecebedor: _nome.text,
    cidadeRecebedor: _cidade.text,
    mensagemCobranca: _mensagem.text,
    tipoSinal: _tipoSinal,
    valorSinal: double.tryParse(_valorSinal.text.replaceAll(',', '.')) ?? 0,
    prazoHoras: int.tryParse(_prazo.text) ?? 24,
    politicaCancelamento: _politica.text,
    linkPagamentoBase: _link.text,
    banco: _banco.text,
    observacoes: _observacoes.text,
    formasAceitas: _formasAceitas,
    valorSinalFixo:
        double.tryParse(_valorSinalFixo.text.replaceAll(',', '.')) ?? 0,
    percentualSinal:
        double.tryParse(_percentualSinal.text.replaceAll(',', '.')) ?? 0,
  );

  Future<void> _salvar() async {
    try {
      await _repository.salvarConfiguracao(_config());
      _mensagemSnack('Configuração de pagamento salva.');
    } catch (e) {
      _mensagemSnack('$e');
    }
  }

  Future<void> _criarCobranca() async {
    final valor = TextEditingController();
    final descricao = TextEditingController(text: 'Sinal de agendamento');
    var forma = 'pix';
    final criar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Gerar cobrança'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: valor,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Valor R\$'),
              ),
              TextField(
                controller: descricao,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              DropdownButtonFormField<String>(
                initialValue: forma,
                decoration: const InputDecoration(labelText: 'Forma'),
                items: const [
                  DropdownMenuItem(
                    value: 'pix',
                    child: Text('Pix Copia e Cola'),
                  ),
                  DropdownMenuItem(
                    value: 'link',
                    child: Text('Link configurado'),
                  ),
                ],
                onChanged: (v) => setLocal(() => forma = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Gerar'),
            ),
          ],
        ),
      ),
    );
    if (criar != true) return;
    try {
      await _repository.salvarConfiguracao(_config());
      final cobranca = await _repository.criarCobranca(
        valor: double.parse(valor.text.replaceAll(',', '.')),
        descricao: descricao.text,
        forma: forma,
      );
      final texto = _repository.textoCobranca(cobranca, _config());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cobrança gerada'),
          content: SingleChildScrollView(child: SelectableText(texto)),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: texto));
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copiar'),
            ),
            TextButton.icon(
              onPressed: () async {
                final uri = Uri.parse(
                  'https://wa.me/?text=${Uri.encodeComponent(texto)}',
                );
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.chat),
              label: const Text('WhatsApp'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
      await _carregar();
    } catch (e) {
      _mensagemSnack('$e');
    }
  }

  void _mensagemSnack(String texto) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(texto)));

  @override
  void dispose() {
    for (final c in [
      _chave,
      _nome,
      _cidade,
      _banco,
      _observacoes,
      _valorSinalFixo,
      _percentualSinal,
      _mensagem,
      _valorSinal,
      _prazo,
      _politica,
      _link,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Pix e pagamentos'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Configuração'),
            Tab(text: 'Cobranças'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _criarCobranca,
        icon: const Icon(Icons.add),
        label: const Text('Cobrança'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
                  children: [
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.verified_user_outlined),
                        title: Text('Confirmação segura'),
                        subtitle: Text(
                          'O StudioFlow não confirma pagamentos automaticamente sem retorno real do provedor. Use confirmação manual somente após conferir o recebimento.',
                        ),
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _tipoChave,
                      decoration: const InputDecoration(
                        labelText: 'Tipo da chave Pix',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cpf', child: Text('CPF')),
                        DropdownMenuItem(value: 'cnpj', child: Text('CNPJ')),
                        DropdownMenuItem(value: 'email', child: Text('E-mail')),
                        DropdownMenuItem(
                          value: 'telefone',
                          child: Text('Telefone'),
                        ),
                        DropdownMenuItem(
                          value: 'aleatoria',
                          child: Text('Aleatória'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _tipoChave = v!),
                    ),
                    TextField(
                      controller: _chave,
                      decoration: const InputDecoration(labelText: 'Chave Pix'),
                    ),
                    TextField(
                      controller: _nome,
                      decoration: const InputDecoration(
                        labelText: 'Nome do recebedor',
                      ),
                    ),
                    TextField(
                      controller: _cidade,
                      decoration: const InputDecoration(
                        labelText: 'Cidade do recebedor',
                      ),
                    ),
                    TextField(
                      controller: _banco,
                      decoration: const InputDecoration(
                        labelText: 'Banco ou instituição',
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children:
                          const {
                                'pix': 'Pix',
                                'dinheiro': 'Dinheiro',
                                'debito': 'Cartão de débito',
                                'credito': 'Cartão de crédito',
                                'transferencia': 'Transferência',
                                'outros': 'Outros',
                              }.entries
                              .map(
                                (item) => FilterChip(
                                  label: Text(item.value),
                                  selected: _formasAceitas.contains(item.key),
                                  onSelected: (selecionado) => setState(() {
                                    if (selecionado) {
                                      _formasAceitas.add(item.key);
                                    } else {
                                      _formasAceitas.remove(item.key);
                                    }
                                  }),
                                ),
                              )
                              .toList(),
                    ),
                    TextField(
                      controller: _valorSinalFixo,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Valor padrão de sinal (opcional)',
                      ),
                    ),
                    TextField(
                      controller: _percentualSinal,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Percentual padrão de sinal (opcional)',
                      ),
                    ),
                    TextField(
                      controller: _observacoes,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Observações de pagamento',
                      ),
                    ),
                    TextField(
                      controller: _mensagem,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Mensagem de cobrança',
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _tipoSinal,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de sinal',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'percentual',
                          child: Text('Percentual'),
                        ),
                        DropdownMenuItem(
                          value: 'fixo',
                          child: Text('Valor fixo'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _tipoSinal = v!),
                    ),
                    TextField(
                      controller: _valorSinal,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Valor ou percentual do sinal',
                      ),
                    ),
                    TextField(
                      controller: _prazo,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Prazo em horas',
                      ),
                    ),
                    TextField(
                      controller: _politica,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Política de cancelamento',
                      ),
                    ),
                    TextField(
                      controller: _link,
                      decoration: const InputDecoration(
                        labelText: 'Link de pagamento do provedor (opcional)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _salvar,
                      icon: const Icon(Icons.save),
                      label: const Text('Salvar'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _chave.text.trim().isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: _chave.text.trim()),
                              );
                              _mensagemSnack('Chave Pix copiada.');
                            },
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('COPIAR CHAVE PIX'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final texto =
                            '${_mensagem.text}\n\nChave Pix: ${_chave.text}\nRecebedor: ${_nome.text}\nBanco: ${_banco.text}';
                        await _externo.abrirWhatsApp(mensagem: texto);
                      },
                      icon: const Icon(Icons.chat_outlined),
                      label: const Text('ENVIAR PIX PELO WHATSAPP'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _externo.compartilhar(
                        'Chave Pix: ${_chave.text}\nRecebedor: ${_nome.text}\nBanco: ${_banco.text}\n${_observacoes.text}',
                      ),
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('COMPARTILHAR DADOS DE PAGAMENTO'),
                    ),
                  ],
                ),
                _cobrancas.isEmpty
                    ? const Center(child: Text('Nenhuma cobrança gerada.'))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                        children: _cobrancas
                            .map(
                              (c) => Card(
                                child: ListTile(
                                  leading: Icon(
                                    c.forma == 'pix' ? Icons.pix : Icons.link,
                                  ),
                                  title: Text(
                                    '${c.descricao} • ${AppFormatters.moeda(c.valor)}',
                                  ),
                                  subtitle: Text(
                                    '${c.status} • ${c.criadaEm.day}/${c.criadaEm.month}/${c.criadaEm.year}',
                                  ),
                                  trailing: c.status == 'pendente'
                                      ? TextButton(
                                          onPressed: () async {
                                            try {
                                              await _repository.confirmarManual(
                                                c.id,
                                              );
                                              await _carregar();
                                            } catch (e) {
                                              _mensagemSnack('$e');
                                            }
                                          },
                                          child: const Text('Confirmar'),
                                        )
                                      : const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                        ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ],
            ),
    ),
  );
}
