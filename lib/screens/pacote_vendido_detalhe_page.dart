import 'package:flutter/material.dart';
import '../models/domain/pacote_servico.dart';
import '../repositories/pacotes_repository.dart';
import '../repositories/cliente_repository.dart';
import '../repositories/cadastros_basicos_repository.dart';
import 'novo_agendamento_sheet.dart';

class PacoteVendidoDetalhePage extends StatefulWidget {
  final ResumoVendaPacote venda;

  const PacoteVendidoDetalhePage({super.key, required this.venda});

  @override
  State<PacoteVendidoDetalhePage> createState() =>
      _PacoteVendidoDetalhePageState();
}

class _PacoteVendidoDetalhePageState extends State<PacoteVendidoDetalhePage> {
  final _repository = PacotesRepository();
  final _clienteRepository = ClienteRepository();
  final _cadastrosRepository = CadastrosBasicosRepository();

  bool _loading = true;
  List<SessaoPacoteDetalheRegistro> _sessoes = [];
  late ResumoVendaPacote _venda;

  @override
  void initState() {
    super.initState();
    _venda = widget.venda;
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final sessoes = await _repository.listarSessoes(_venda.id);

      // Attempt to refresh the ResumoVendaPacote as well
      final vendas = await _repository.listarVendas(
        clienteId: _venda.clienteId,
      );
      final vendaAtualizada = vendas.firstWhere(
        (v) => v.id == _venda.id,
        orElse: () => _venda,
      );

      if (mounted) {
        setState(() {
          _sessoes = sessoes;
          _venda = vendaAtualizada;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _agendarSessao(SessaoPacoteDetalheRegistro sessao) async {
    final clienteRegistro = await _clienteRepository.buscarPorId(
      _venda.clienteId,
    );
    final profList = await _cadastrosRepository.listarProfissionais();

    if (!mounted || clienteRegistro == null || profList.isEmpty) return;

    if (sessao.status == 'agendada') {
      var inicio = DateTime.parse(sessao.dataAgendada!);
      var profissionalId = profList.first.id;
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text('Editar ${sessao.servicoNome}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
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
                ListTile(
                  title: const Text('Horário'),
                  subtitle: Text(
                    '${inicio.hour.toString().padLeft(2, '0')}:${inicio.minute.toString().padLeft(2, '0')}',
                  ),
                  onTap: () async {
                    final hora = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(inicio),
                    );
                    if (hora != null) {
                      setLocal(
                        () => inicio = DateTime(
                          inicio.year,
                          inicio.month,
                          inicio.day,
                          hora.hour,
                          hora.minute,
                        ),
                      );
                    }
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: profissionalId,
                  decoration: const InputDecoration(labelText: 'Profissional'),
                  items: profList
                      .map(
                        (p) =>
                            DropdownMenuItem(value: p.id, child: Text(p.nome)),
                      )
                      .toList(),
                  onChanged: (value) => profissionalId = value!,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Salvar'),
              ),
            ],
          ),
        ),
      );
      if (confirmou == true) {
        try {
          await _repository.reagendarSessoes(
            sessaoId: sessao.id,
            novoInicio: inicio,
            profissionalId: profissionalId,
          );
          await _carregar();
        } catch (erro) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Não foi possível reagendar: $erro')),
            );
          }
        }
      }
      return;
    }

    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NovoAgendamentoSheet(
        dataBase: DateTime.now(),
        profissionais: profList,
        clienteInicial: clienteRegistro,
        pacoteInicial: _venda,
        sessaoInicial: sessao,
      ),
    );

    if (result == true && mounted) {
      await _carregar();
    }
  }

  Future<void> _receber() async {
    final valor = TextEditingController(
      text: _venda.valorPendente.toStringAsFixed(2),
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
    if (confirmou != true) return;
    await _repository.registrarPagamento(
      vendaId: _venda.id,
      valor: double.tryParse(valor.text.replaceAll(',', '.')) ?? 0,
      formaPagamento: 'Pix',
    );
    await _carregar();
  }

  Future<void> _transferir() async {
    final clientes = await _repository.listarClientesAtivos();
    clientes.removeWhere((cliente) => cliente['id'] == _venda.clienteId);
    if (!mounted || clientes.isEmpty) return;
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
                (cliente) => DropdownMenuItem(
                  value: cliente['id'] as String,
                  child: Text(cliente['nome'] as String),
                ),
              )
              .toList(),
          onChanged: (value) => clienteId = value!,
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
    if (confirmou != true) return;
    await _repository.transferir(_venda.id, clienteId);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _cancelar() async {
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
    if (confirmou != true || motivo.text.trim().isEmpty) return;
    await _repository.alterarStatusVenda(
      _venda.id,
      'cancelado',
      motivo: motivo.text.trim(),
    );
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_venda.pacoteNome)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildCabecalho(),
                const SizedBox(height: 16),
                _buildAcoes(),
                const Divider(height: 32),
                const Text(
                  'Sessões',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 16),
                ..._sessoes.map(_buildSessaoCard),
              ],
            ),
    );
  }

  Widget _buildAcoes() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_venda.valorPendente > 0)
          OutlinedButton(
            onPressed: _receber,
            child: const Text('Registrar pagamento'),
          ),
        OutlinedButton(
          onPressed: () async {
            await _repository.alterarStatusVenda(
              _venda.id,
              _venda.status == 'pausado' ? 'ativo' : 'pausado',
            );
            await _carregar();
          },
          child: Text(_venda.status == 'pausado' ? 'Retomar' : 'Pausar'),
        ),
        OutlinedButton(
          onPressed: () async {
            await _repository.estenderValidade(_venda.id, 30);
            await _carregar();
          },
          child: const Text('+30 dias'),
        ),
        if (_venda.status != 'cancelado' && _venda.status != 'concluido')
          OutlinedButton(
            onPressed: _transferir,
            child: const Text('Transferir'),
          ),
        if (_venda.status != 'cancelado' && _venda.status != 'concluido')
          OutlinedButton(
            onPressed: _cancelar,
            child: const Text('Cancelar pacote'),
          ),
      ],
    );
  }

  Widget _buildCabecalho() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cliente: ${_venda.clienteNome}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Validade: ${_venda.validade != null ? '${_venda.validade!.day}/${_venda.validade!.month}/${_venda.validade!.year}' : 'Vitalícia'}',
            ),
            const SizedBox(height: 8),
            Text('Valor: R\$ ${_venda.valorContratado.toStringAsFixed(2)}'),
            Text('Pago: R\$ ${_venda.valorPago.toStringAsFixed(2)}'),
            Text('Pendente: R\$ ${_venda.valorPendente.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total: ${_venda.contratadas}'),
                Text('Realizadas: ${_venda.realizadas}'),
                Text('Agendadas: ${_venda.agendadas}'),
                Text('Disponíveis: ${_venda.disponiveis}'),
              ],
            ),
            const SizedBox(height: 16),
            Text('Status da venda: ${_venda.status.toUpperCase()}'),
          ],
        ),
      ),
    );
  }

  Widget _buildSessaoCard(SessaoPacoteDetalheRegistro sessao) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.event_available),
        title: Text(
          sessao.ordem != null
              ? '${sessao.ordem}. ${sessao.servicoNome}'
              : sessao.servicoNome,
        ),
        subtitle: Text(
          '${sessao.status.toUpperCase()}'
          '${sessao.dataAgendada == null ? '' : ' • ${sessao.dataAgendada} às ${sessao.horarioInicio}'}'
          '${sessao.profissionalNome == null ? '' : ' com ${sessao.profissionalNome}'}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sessao.status == 'agendada' || sessao.status == 'disponivel')
              TextButton(
                onPressed: () => _agendarSessao(sessao),
                child: Text(sessao.status == 'agendada' ? 'Editar' : 'Agendar'),
              ),
          ],
        ),
      ),
    );
  }
}
