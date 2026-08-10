import 'package:flutter/material.dart';

import '../models/domain/pacote_servico.dart';
import '../repositories/pacotes_repository.dart';
import 'pacotes/novo_pacote_page.dart';
import 'pacotes/venda_pacote_page.dart';

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
          'Deseja montar agora uma prévia automática da agenda?',
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
    final profissionais = await _repository.listarProfissionaisAtivos();
    if (!mounted || profissionais.isEmpty) return;
    String profissionalId = profissionais.first['id'] as String;
    var data = DateTime.now().add(const Duration(days: 1));
    final hora = TextEditingController(text: '09:00');
    final intervalo = TextEditingController(text: '1');
    final dias = <int>{1, 2, 3, 4, 5, 6};
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Preferências da agenda'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: profissionalId,
                  decoration: const InputDecoration(labelText: 'Profissional'),
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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Primeira data'),
                  subtitle: Text('${data.day}/${data.month}/${data.year}'),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final escolhida = await showDatePicker(
                      context: context,
                      initialDate: data,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (escolhida != null) setLocal(() => data = escolhida);
                  },
                ),
                TextField(
                  controller: hora,
                  decoration: const InputDecoration(
                    labelText: 'Horário preferido (HH:mm)',
                  ),
                ),
                TextField(
                  controller: intervalo,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Intervalo em semanas',
                  ),
                ),
                Wrap(
                  spacing: 4,
                  children: List.generate(7, (i) {
                    const nomes = [
                      'Seg',
                      'Ter',
                      'Qua',
                      'Qui',
                      'Sex',
                      'Sáb',
                      'Dom',
                    ];
                    final dia = i + 1;
                    return FilterChip(
                      label: Text(nomes[i]),
                      selected: dias.contains(dia),
                      onSelected: (v) =>
                          setLocal(() => v ? dias.add(dia) : dias.remove(dia)),
                    );
                  }),
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
              child: const Text('Gerar prévia'),
            ),
          ],
        ),
      ),
    );
    if (confirmou != true) return;
    final partes = hora.text.split(':');
    final previa = await _repository.gerarPrevia(
      SolicitacaoAgendaPacote(
        vendaId: vendaId,
        primeiraData: data,
        diasSemana: dias,
        horaPreferida: int.tryParse(partes.first) ?? 9,
        minutoPreferido: partes.length > 1 ? int.tryParse(partes[1]) ?? 0 : 0,
        profissionalId: profissionalId,
        intervalo: int.tryParse(intervalo.text) ?? 1,
      ),
    );
    if (!mounted) return;
    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Prévia — confirme antes de salvar'),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: [
              ...previa.sessoes.map(
                (s) => ListTile(
                  leading: Icon(
                    s.horarioAlternativo ? Icons.schedule : Icons.check_circle,
                  ),
                  title: Text(s.servicoNome),
                  subtitle: Text(
                    '${s.inicio.day}/${s.inicio.month}/${s.inicio.year} '
                    '${s.inicio.hour.toString().padLeft(2, '0')}:'
                    '${s.inicio.minute.toString().padLeft(2, '0')} • '
                    '${s.profissionalNome}${s.aviso == null ? '' : '\n${s.aviso}'}',
                  ),
                ),
              ),
              ...previa.naoEncaixadas.map(
                (texto) => ListTile(
                  leading: const Icon(
                    Icons.warning_amber,
                    color: Colors.orange,
                  ),
                  title: Text(texto),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ajustar'),
          ),
          FilledButton(
            onPressed: previa.sessoes.isEmpty
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('Confirmar horários'),
          ),
        ],
      ),
    );
    if (salvar == true) {
      await _repository.confirmarPrevia(previa);
      await _carregar();
    }
  }

  Future<void> _detalhar(ResumoVendaPacote venda) async {
    final sessoes = await _repository.listarSessoes(venda.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .75,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              venda.pacoteNome,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              '${venda.clienteNome} • validade ${venda.validade.day}/'
              '${venda.validade.month}/${venda.validade.year}',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (venda.disponiveis > 0 && venda.status == 'ativo')
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _agendar(venda.id);
                    },
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Agenda automática'),
                  ),
                if (venda.valorPendente > 0)
                  OutlinedButton(
                    onPressed: () => _receber(venda),
                    child: const Text('Registrar pagamento'),
                  ),
                OutlinedButton(
                  onPressed: () async {
                    await _repository.alterarStatusVenda(
                      venda.id,
                      venda.status == 'pausado' ? 'ativo' : 'pausado',
                    );
                    if (context.mounted) Navigator.pop(context);
                    await _carregar();
                  },
                  child: Text(venda.status == 'pausado' ? 'Retomar' : 'Pausar'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await _repository.estenderValidade(venda.id, 30);
                    if (context.mounted) Navigator.pop(context);
                    await _carregar();
                  },
                  child: const Text('+30 dias'),
                ),
                if (venda.status != 'cancelado' && venda.status != 'concluido')
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _transferirVenda(venda);
                    },
                    child: const Text('Transferir'),
                  ),
                if (venda.status != 'cancelado' && venda.status != 'concluido')
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _cancelarVenda(venda);
                    },
                    child: const Text('Cancelar pacote'),
                  ),
              ],
            ),
            const Divider(height: 32),
            const Text(
              'Sessões',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ...sessoes.map(
              (s) => ListTile(
                leading: const Icon(Icons.event_available),
                title: Text('${s['numero']}. ${s['servico_nome']}'),
                subtitle: Text(
                  '${s['status']}'
                  '${s['inicio_planejado'] == null ? '' : ' • ${s['inicio_planejado']}'}',
                ),
                trailing: s['status'] == 'agendada'
                    ? IconButton(
                        tooltip: 'Reagendar',
                        icon: const Icon(Icons.edit_calendar_outlined),
                        onPressed: () {
                          Navigator.pop(context);
                          _reagendarSessao(venda, s);
                        },
                      )
                    : Text(
                        '${((s['credito_consumido'] as num) * 100).round()}%',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
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

  Future<void> _reagendarSessao(
    ResumoVendaPacote venda,
    Map<String, Object?> sessao,
  ) async {
    try {
      final profissionais = await _repository.listarProfissionaisAtivos();
      if (!mounted || profissionais.isEmpty) return;
      var inicio = DateTime.parse(sessao['inicio_planejado'] as String);
      var profissionalId =
          sessao['profissional_id'] as String? ??
          profissionais.first['id'] as String;
      var escopo = EscopoReagendamentoPacote.somenteEsta;
      final hora = TextEditingController(
        text:
            '${inicio.hour.toString().padLeft(2, '0')}:${inicio.minute.toString().padLeft(2, '0')}',
      );
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text('Reagendar ${sessao['servico_nome']}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Nova data'),
                    subtitle: Text(
                      '${inicio.day}/${inicio.month}/${inicio.year}',
                    ),
                    onTap: () async {
                      final data = await showDatePicker(
                        context: context,
                        initialDate: inicio,
                        firstDate: DateTime.now(),
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
                  DropdownButtonFormField<EscopoReagendamentoPacote>(
                    initialValue: escopo,
                    decoration: const InputDecoration(
                      labelText: 'Aplicar alteração',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: EscopoReagendamentoPacote.somenteEsta,
                        child: Text('Somente esta sessão'),
                      ),
                      DropdownMenuItem(
                        value: EscopoReagendamentoPacote.estaEProximas,
                        child: Text('Esta e as próximas'),
                      ),
                      DropdownMenuItem(
                        value: EscopoReagendamentoPacote.refazerRestante,
                        child: Text('Refazer restante'),
                      ),
                    ],
                    onChanged: (v) => escopo = v!,
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
                child: const Text('Reagendar'),
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
      await _repository.reagendarSessoes(
        sessaoId: sessao['id'] as String,
        novoInicio: novoInicio,
        profissionalId: profissionalId,
        escopo: escopo,
      );
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
