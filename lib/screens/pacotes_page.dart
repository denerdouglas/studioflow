import 'package:flutter/material.dart';

import '../models/domain/pacote_servico.dart';
import '../repositories/pacotes_repository.dart';
import 'pacotes/novo_pacote_page.dart';
import 'pacotes/venda_pacote_page.dart';
import 'novo_agendamento_sheet.dart';
import 'pacote_vendido_detalhe_page.dart';
import '../repositories/cliente_repository.dart';
import '../repositories/cadastros_basicos_repository.dart';

class PacotesPage extends StatefulWidget {
  const PacotesPage({super.key});

  @override
  State<PacotesPage> createState() => _PacotesPageState();
}

class _PacotesPageState extends State<PacotesPage>
    with SingleTickerProviderStateMixin {
  final _repository = PacotesRepository();
  late final TabController _tabs;
  bool _carregando = true;
  List<PacoteModeloRegistro> _modelos = [];
  List<ResumoVendaPacote> _vendas = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() {}));
    _carregar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _venderPacote() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VendaPacotePage()),
    );
    if (result == true && mounted) {
      _carregar();
    }
  }

  Future<void> _carregar() async {
    try {
      final resultado = await Future.wait([
        _repository.listarModelos(),
        _repository.listarVendas(),
        _repository.gerarAlertas(),
      ]);
      if (!mounted) return;
      setState(() {
        _modelos = resultado[0] as List<PacoteModeloRegistro>;
        _vendas = resultado[1] as List<ResumoVendaPacote>;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _erro(erro);
    }
  }

  void _erro(Object erro) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(erro.toString()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pacotes de serviços'),
        actions: [
          IconButton(
            tooltip: 'Alertas',
            onPressed: _mostrarAlertas,
            icon: const Icon(Icons.notifications_outlined),
          ),
          IconButton(
            tooltip: 'Relatório',
            onPressed: _mostrarRelatorio,
            icon: const Icon(Icons.bar_chart),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Modelos'),
            Tab(text: 'Pacotes vendidos'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _tabs.index == 0 ? _novoModelo : _venderPacote,
        icon: Icon(_tabs.index == 0 ? Icons.add : Icons.shopping_cart),
        label: Text(_tabs.index == 0 ? 'Novo pacote' : 'Vender pacote'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: TabBarView(
                controller: _tabs,
                children: [_listaModelos(), _listaVendas()],
              ),
            ),
    );
  }

  Widget _listaModelos() {
    if (_modelos.isEmpty) {
      return const _Vazio(
        titulo: 'Nenhum pacote cadastrado',
        texto: 'Crie uma combinação de serviços para começar.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _modelos.length,
      itemBuilder: (_, index) {
        final item = _modelos[index];
        final ativo = item.ativo;
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Icon(ativo ? Icons.auto_awesome : Icons.pause),
            ),
            title: Text(item.nome),
            subtitle: Text(
              '${item.itensResumo}\n'
              '${item.totalSessoes} sessões • '
              'R\$ ${item.preco.toStringAsFixed(2)} • '
              '${item.validadeDias ?? '-'} dias',
            ),
            isThreeLine: true,
            trailing: PopupMenuButton<String>(
              onSelected: (acao) async {
                try {
                  if (acao == 'vender') await _vender(item);
                  if (acao == 'status') {
                    await _repository.alterarModeloAtivo(item.id, !ativo);
                    await _carregar();
                  }
                } catch (erro) {
                  _erro(erro);
                }
              },
              itemBuilder: (_) => [
                if (ativo)
                  const PopupMenuItem(
                    value: 'vender',
                    child: Text('Vender este pacote'),
                  ),
                PopupMenuItem(
                  value: 'status',
                  child: Text(ativo ? 'Desativar' : 'Reativar'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _listaVendas() {
    if (_vendas.isEmpty) {
      return const _Vazio(
        titulo: 'Nenhum pacote vendido',
        texto: 'A venda cria os créditos; o agendamento é feito depois.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _vendas.length,
      itemBuilder: (_, index) {
        final venda = _vendas[index];
        return Card(
          child: InkWell(
            onTap: () => _detalhar(venda),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          venda.pacoteNome,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Chip(label: Text(venda.status)),
                    ],
                  ),
                  Text(venda.clienteNome),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: venda.progresso),
                  const SizedBox(height: 6),
                  Text(
                    '${venda.realizadas}/${venda.contratadas} realizadas • '
                    '${venda.agendadas} agendadas • ${venda.disponiveis} disponíveis',
                  ),
                  Text(
                    'Pago: R\$ ${venda.valorPago.toStringAsFixed(2)} • '
                    'Pendente: R\$ ${venda.valorPendente.toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _novoModelo() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NovoPacotePage()),
    );
    if (result == true && mounted) {
      _carregar();
    }
  }

  Future<void> _vender(PacoteModeloRegistro modelo) async {
    final clientes = await _repository.listarClientesAtivos();
    final profissionais = await _repository.listarProfissionaisAtivos();
    if (!mounted) return;
    if (clientes.isEmpty || profissionais.isEmpty) {
      throw StateError('Cadastre cliente e profissional antes da venda.');
    }
    String clienteId = clientes.first['id'] as String;
    String profissionalId = profissionais.first['id'] as String;
    final desconto = TextEditingController(text: '0');
    final pago = TextEditingController(text: '0');
    final parcelas = TextEditingController(text: '1');
    String forma = 'Pix';
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Vender ${modelo.nome}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: clienteId,
                  decoration: const InputDecoration(labelText: 'Cliente'),
                  items: clientes
                      .map(
                        (c) => DropdownMenuItem(
                          value: c['id'] as String,
                          child: Text(c['nome'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => clienteId = v!,
                ),
                DropdownButtonFormField<String>(
                  initialValue: profissionalId,
                  decoration: const InputDecoration(labelText: 'Vendedor'),
                  items: profissionais
                      .map(
                        (p) => DropdownMenuItem(
                          value: p['id'] as String,
                          child: Text(p['nome'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => profissionalId = v!,
                ),
                TextField(
                  controller: desconto,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Desconto'),
                ),
                TextField(
                  controller: pago,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Valor recebido agora',
                  ),
                ),
                TextField(
                  controller: parcelas,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Parcelas'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: forma,
                  decoration: const InputDecoration(labelText: 'Pagamento'),
                  items: const ['Pix', 'Dinheiro', 'Cartão', 'Transferência']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setLocal(() => forma = v!),
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
              child: const Text('Confirmar venda'),
            ),
          ],
        ),
      ),
    );
    if (confirmou != true) return;
    final valorPago = double.tryParse(pago.text.replaceAll(',', '.')) ?? 0;
    final vendaId = await _repository.vender(
      VendaPacoteEntrada(
        pacoteId: modelo.id,
        clienteId: clienteId,
        vendedorProfissionalId: profissionalId,
        desconto: double.tryParse(desconto.text.replaceAll(',', '.')) ?? 0,
        sinal: valorPago,
        valorPagoInicial: valorPago,
        parcelas: int.tryParse(parcelas.text) ?? 1,
        formaPagamento: forma,
        dataCompra: DateTime.now(),
      ),
    );
    await _carregar();
    if (!mounted) return;
    final agendar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Venda registrada'),
        content: const Text(
          'Os créditos foram criados sem consumir sessões. '
          'Deseja agendar as sessões agora?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Depois'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Agendar'),
          ),
        ],
      ),
    );
    if (agendar == true && mounted) await _agendar(vendaId);
  }

  Future<void> _agendar(String vendaId) async {
    final vendas = await _repository.listarVendas();
    final venda = vendas.firstWhere((v) => v.id == vendaId);

    final clientes = await _repository.listarClientesAtivos();
    final cRow = clientes.firstWhere(
      (c) => c['nome'] == venda.clienteNome,
      orElse: () => <String, Object?>{},
    );
    if (cRow.isEmpty || !mounted) return;

    final clienteRegistro = ClienteRegistro(
      id: cRow['id'] as String,
      nome: cRow['nome'] as String,
      telefone: cRow['telefone'] as String? ?? '',
      whatsapp: cRow['telefone'] as String? ?? '',
      profissional: '',
      ultimoServico: '',
      totalGasto: 0.0,
      totalAtendimentos: 0,
      observacoes: '',
      dataCadastro: DateTime.now(),
    );

    final profissionais = await _repository.listarProfissionaisAtivos();
    if (!mounted || profissionais.isEmpty) return;

    final profList = profissionais
        .map(
          (p) => ProfissionalBasicoRegistro(
            id: p['id'] as String,
            nome: p['nome'] as String,
            cargo: p['cargo'] as String? ?? 'Profissional',
            percentualComissao:
                (p['percentual_comissao'] as num?)?.toDouble() ?? 0.0,
            ativo: (p['ativo'] as int?) == 1,
            whatsapp: p['whatsapp'] as String? ?? '',
          ),
        )
        .toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NovoAgendamentoSheet(
        dataBase: DateTime.now(),
        profissionais: profList,
        clienteInicial: clienteRegistro,
      ),
    );

    if (mounted) await _carregar();
  }

  Future<void> _detalhar(ResumoVendaPacote venda) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PacoteVendidoDetalhePage(venda: venda)),
    );
    if (mounted) await _carregar();
  }

  Future<void> _mostrarAlertas() async {
    try {
      await _repository.gerarAlertas();
      final alertas = await _repository.listarAlertas();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Alertas de pacotes'),
          content: SizedBox(
            width: 520,
            child: alertas.isEmpty
                ? const Text('Nenhum alerta pendente.')
                : ListView(
                    shrinkWrap: true,
                    children: alertas
                        .map(
                          (a) => ListTile(
                            leading: const Icon(
                              Icons.notification_important_outlined,
                            ),
                            title: Text(a['mensagem'] as String),
                            subtitle: Text(
                              '${a['cliente_nome']} • ${a['pacote_nome']}',
                            ),
                          ),
                        )
                        .toList(),
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
      if (mounted) _erro(erro);
    }
  }

  Future<void> _mostrarRelatorio() async {
    try {
      final dados = await _repository.relatorio();
      final vendas = dados['vendas'] as Map<String, Object?>;
      final sessoes = dados['sessoes'] as List<Map<String, Object?>>;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Relatório de pacotes'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pacotes vendidos: ${vendas['quantidade']}'),
              Text(
                'Contratado: R\$ ${(vendas['vendido'] as num).toStringAsFixed(2)}',
              ),
              Text(
                'Recebido: R\$ ${(vendas['recebido'] as num).toStringAsFixed(2)}',
              ),
              Text(
                'Pendente: R\$ ${(vendas['pendente'] as num).toStringAsFixed(2)}',
              ),
              const Divider(),
              ...sessoes.map((s) => Text('${s['status']}: ${s['quantidade']}')),
            ],
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
      if (mounted) _erro(erro);
    }
  }

  // ignore: unused_element
  Future<void> _cancelarVenda(ResumoVendaPacote venda) async {
    final motivo = TextEditingController();
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar pacote?'),
        content: TextField(
          controller: motivo,
          decoration: const InputDecoration(labelText: 'Motivo *'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar cancelamento'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;
    if (motivo.text.trim().isEmpty) {
      _erro(ArgumentError('Informe o motivo do cancelamento.'));
      return;
    }
    try {
      await _repository.alterarStatusVenda(
        venda.id,
        'cancelado',
        motivo: motivo.text,
      );
      await _carregar();
    } catch (erro) {
      if (mounted) _erro(erro);
    }
  }

  // ignore: unused_element
  Future<void> _transferirVenda(ResumoVendaPacote venda) async {
    try {
      final clientes = await _repository.listarClientesAtivos();
      clientes.removeWhere((c) => c['nome'] == venda.clienteNome);
      if (!mounted) return;
      if (clientes.isEmpty) {
        throw StateError('Não há outro cliente ativo para receber o pacote.');
      }
      var clienteId = clientes.first['id'] as String;
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Transferir pacote'),
          content: DropdownButtonFormField<String>(
            initialValue: clienteId,
            decoration: const InputDecoration(labelText: 'Novo cliente'),
            items: clientes
                .map(
                  (c) => DropdownMenuItem(
                    value: c['id'] as String,
                    child: Text(c['nome'] as String),
                  ),
                )
                .toList(),
            onChanged: (v) => clienteId = v!,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Transferir'),
            ),
          ],
        ),
      );
      if (confirmou == true) {
        await _repository.transferir(venda.id, clienteId);
        await _carregar();
      }
    } catch (erro) {
      if (mounted) _erro(erro);
    }
  }

  // ignore: unused_element
  Future<void> _agendarSessaoIndividual(
    ResumoVendaPacote venda,
    Map<String, Object?> sessao,
  ) async {
    try {
      final profissionais = await _repository.listarProfissionaisAtivos();
      if (!mounted || profissionais.isEmpty) return;

      var inicio = sessao['data_agendada'] != null
          ? DateTime.parse(sessao['data_agendada'] as String)
          : DateTime.now();

      var profissionalId =
          sessao['profissional_id'] as String? ??
          profissionais.first['id'] as String;

      final hora = TextEditingController(
        text: sessao['data_agendada'] != null
            ? '${inicio.hour.toString().padLeft(2, '0')}:${inicio.minute.toString().padLeft(2, '0')}'
            : '09:00',
      );

      final isNova = sessao['status'] == 'disponivel';

      final confirmou = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text(
              '${isNova ? 'Agendar' : 'Reagendar'} ${sessao['servico_nome']}',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Data'),
                    subtitle: Text(
                      '${inicio.day}/${inicio.month}/${inicio.year}',
                    ),
                    onTap: () async {
                      final data = await showDatePicker(
                        context: context,
                        initialDate: inicio,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 1),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                      );
                      if (data != null) {
                        setLocal(
                          () => inicio = DateTime(
                            data.year,
                            data.month,
                            data.day,
                            inicio.hour,
                            inicio.minute,
                          ),
                        );
                      }
                    },
                  ),
                  TextField(
                    controller: hora,
                    decoration: const InputDecoration(
                      labelText: 'Horário (HH:mm)',
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: profissionalId,
                    decoration: const InputDecoration(
                      labelText: 'Profissional',
                    ),
                    items: profissionais
                        .map(
                          (p) => DropdownMenuItem(
                            value: p['id'] as String,
                            child: Text(p['nome'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => profissionalId = v!,
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
                child: Text(isNova ? 'Agendar' : 'Salvar'),
              ),
            ],
          ),
        ),
      );
      if (confirmou != true) return;
      final partes = hora.text.split(':');
      final novoInicio = DateTime(
        inicio.year,
        inicio.month,
        inicio.day,
        int.tryParse(partes.first) ?? inicio.hour,
        partes.length > 1
            ? int.tryParse(partes[1]) ?? inicio.minute
            : inicio.minute,
      );
      if (isNova) {
        await _repository.agendarSessao(
          sessaoId: sessao['id'] as String,
          inicio: novoInicio,
          profissionalId: profissionalId,
        );
      } else {
        await _repository.reagendarSessoes(
          sessaoId: sessao['id'] as String,
          novoInicio: novoInicio,
          profissionalId: profissionalId,
          escopo: EscopoReagendamentoPacote.somenteEsta,
        );
      }
      await _carregar();
      if (mounted) {
        await _detalhar(
          (await _repository.listarVendas()).firstWhere(
            (v) => v.id == venda.id,
          ),
        );
      }
    } catch (erro) {
      if (mounted) _erro(erro);
    }
  }

  // ignore: unused_element
  Future<void> _receber(ResumoVendaPacote venda) async {
    final valor = TextEditingController(
      text: venda.valorPendente.toStringAsFixed(2),
    );
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar pagamento'),
        content: TextField(
          controller: valor,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Valor recebido'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Receber via Pix'),
          ),
        ],
      ),
    );
    if (confirmou == true) {
      await _repository.registrarPagamento(
        vendaId: venda.id,
        valor: double.tryParse(valor.text.replaceAll(',', '.')) ?? 0,
        formaPagamento: 'Pix',
      );
      if (mounted) Navigator.pop(context);
      await _carregar();
    }
  }
}

class _Vazio extends StatelessWidget {
  final String titulo;
  final String texto;

  const _Vazio({required this.titulo, required this.texto});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 100),
        const Icon(Icons.card_giftcard, size: 64),
        const SizedBox(height: 16),
        Center(
          child: Text(titulo, style: Theme.of(context).textTheme.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(texto, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}
