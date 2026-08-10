import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/domain/agendamento_grupo_registro.dart';
import '../repositories/agenda_repository.dart';
import '../repositories/cadastros_basicos_repository.dart';
import '../repositories/cliente_repository.dart';
import '../repositories/servicos_repository.dart';
import '../widgets/selectors/cliente_smart_selector.dart';
import '../widgets/selectors/servico_smart_selector.dart';
import '../repositories/agenda_completa_repository.dart';

class NovoAgendamentoSheet extends StatefulWidget {
  final DateTime dataBase;
  final List<ProfissionalBasicoRegistro> profissionais;
  final ClienteRegistro? clienteInicial;

  const NovoAgendamentoSheet({
    super.key,
    required this.dataBase,
    required this.profissionais,
    this.clienteInicial,
  });

  @override
  State<NovoAgendamentoSheet> createState() => _NovoAgendamentoSheetState();
}

class _ItemServico {
  ServicoRegistro? servico;
  ProfissionalBasicoRegistro? profissional;
  DateTime? inicioPrevisto;
  DateTime? fimPrevisto;

  _ItemServico({this.profissional})
    : servico = null,
      inicioPrevisto = null,
      fimPrevisto = null;
}

class _NovoAgendamentoSheetState extends State<NovoAgendamentoSheet> {
  static const Color _corFundo = Color(0xFFF9F6FC);

  final TextEditingController _observacoesController = TextEditingController();
  final AgendaRepository _agendaRepository = AgendaRepository();

  ClienteRegistro? _clienteSelecionado;
  late DateTime _dataSelecionada;
  TimeOfDay _horarioSelecionado = const TimeOfDay(hour: 9, minute: 0);

  final List<_ItemServico> _itens = [];

  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _dataSelecionada = DateTime(
      widget.dataBase.year,
      widget.dataBase.month,
      widget.dataBase.day,
    );
    _clienteSelecionado = widget.clienteInicial;
    _adicionarItem();
  }

  void _adicionarItem() {
    setState(() {
      _itens.add(
        _ItemServico(
          profissional: widget.profissionais.isNotEmpty
              ? widget.profissionais.first
              : null,
        ),
      );
      _recalcularHorarios();
    });
  }

  void _removerItem(int index) {
    if (_itens.length <= 1) return;
    setState(() {
      _itens.removeAt(index);
      _recalcularHorarios();
    });
  }

  void _recalcularHorarios() {
    DateTime current = DateTime(
      _dataSelecionada.year,
      _dataSelecionada.month,
      _dataSelecionada.day,
      _horarioSelecionado.hour,
      _horarioSelecionado.minute,
    );

    for (var item in _itens) {
      item.inicioPrevisto = current;
      if (item.servico != null) {
        current = current.add(Duration(minutes: item.servico!.duracaoMinutos));
      } else {
        current = current.add(const Duration(minutes: 30));
      }
      item.fimPrevisto = current;
    }
  }

  Future<void> _salvar() async {
    if (_clienteSelecionado == null) {
      _mostrarErro('Selecione um cliente.');
      return;
    }
    if (_itens.any((i) => i.servico == null || i.profissional == null)) {
      _mostrarErro('Preencha todos os serviços e profissionais.');
      return;
    }

    setState(() => _salvando = true);

    try {
      final agora = DateTime.now();
      final grupoId = agora.microsecondsSinceEpoch.toString();

      final grupo = AgendamentoGrupoRegistro(
        id: grupoId,
        businessId:
            '', // O repository injeta o comercioId real, podemos deixar vazio aqui e o banco fará se o repositório suportar, ou preenchemos.
        // Na verdade o inserirGrupo no AgendaRepository já ignora o business_id da classe e injeta o _comercioId da sessão.
        clienteId: _clienteSelecionado!.id,
        status: 'agendado',
        observacoes: _observacoesController.text.trim(),
        createdAt: agora,
        updatedAt: agora,
      );

      final listaAgendamentos = <AgendamentoRegistro>[];
      for (var i = 0; i < _itens.length; i++) {
        final item = _itens[i];
        listaAgendamentos.add(
          AgendamentoRegistro(
            id: '${grupoId}_$i',
            clienteId: _clienteSelecionado!.id,
            clienteNome: _clienteSelecionado!.nome,
            profissionalId: item.profissional!.id,
            profissionalNome: item.profissional!.nome,
            servicoId: item.servico!.id,
            servicoNome: item.servico!.nome,
            inicio: item.inicioPrevisto!,
            fim: item.fimPrevisto!,
            status: 'agendado',
            valorServico: item.servico!.preco,
            desconto: 0,
            valorRecebido: 0,
            confirmado: false,
            compareceu: false,
            grupoAgendamentoId: grupoId,
            ordemNoGrupo: i,
            observacoes: '',
            dataCriacao: agora,
          ),
        );
      }

      await _agendaRepository.inserirGrupo(grupo, listaAgendamentos);

      // Registrar log (só o grupo ou só o principal, aqui faremos p/ o primeiro)
      final agendaCompleta = AgendaCompletaRepository();
      for (var item in listaAgendamentos) {
        await agendaCompleta.registrarStatus(
          agendamentoId: item.id,
          status: 'agendado',
          detalhes: 'Agendamento criado via grupo.',
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } on ConflitoAgendaException catch (e) {
      _mostrarErro(e.mensagem);
    } catch (e) {
      _mostrarErro('Erro inesperado: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _mostrarErro(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;

    double valorTotal = 0;
    Duration duracaoTotal = Duration.zero;
    for (var i in _itens) {
      if (i.servico != null) {
        valorTotal += i.servico!.preco;
        duracaoTotal += Duration(minutes: i.servico!.duracaoMinutos);
      }
    }

    return Container(
      padding: EdgeInsets.fromLTRB(22, 22, 22, teclado + 25),
      decoration: const BoxDecoration(
        color: _corFundo,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6CDDD),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Novo Agendamento',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D2140),
                  ),
                ),
                TextButton.icon(
                  onPressed: _adicionarItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Serviço'),
                ),
              ],
            ),
            const SizedBox(height: 22),
            InkWell(
              onTap: () async {
                final cliente = await ClienteSmartSelector.show(context);
                if (cliente != null) {
                  setState(() => _clienteSelecionado = cliente);
                }
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Cliente',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                child: Text(
                  _clienteSelecionado?.nome ?? 'Selecione um cliente...',
                  style: TextStyle(
                    color: _clienteSelecionado == null
                        ? Colors.grey
                        : Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final data = await showDatePicker(
                        context: context,
                        initialDate: _dataSelecionada,
                        firstDate: DateTime(2025),
                        lastDate: DateTime(2035),
                        locale: const Locale('pt', 'BR'),
                      );
                      if (data != null) {
                        setState(() {
                          _dataSelecionada = data;
                          _recalcularHorarios();
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Data',
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        DateFormat('dd/MM/yyyy').format(_dataSelecionada),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final horario = await showTimePicker(
                        context: context,
                        initialTime: _horarioSelecionado,
                      );
                      if (horario != null) {
                        setState(() {
                          _horarioSelecionado = horario;
                          _recalcularHorarios();
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Horário Início',
                        prefixIcon: Icon(Icons.access_time),
                      ),
                      child: Text(_horarioSelecionado.format(context)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Reorderable list of services
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _itens.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _itens.removeAt(oldIndex);
                  _itens.insert(newIndex, item);
                  _recalcularHorarios();
                });
              },
              itemBuilder: (ctx, index) {
                final item = _itens[index];
                return Card(
                  key: ValueKey(item),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.drag_handle, color: Colors.grey),
                            const SizedBox(width: 8),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final servico =
                                      await ServicoSmartSelector.show(context);
                                  if (servico != null) {
                                    setState(() {
                                      item.servico = servico;
                                      _recalcularHorarios();
                                    });
                                  }
                                },
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Serviço',
                                    isDense: true,
                                    contentPadding: EdgeInsets.all(8),
                                  ),
                                  child: Text(
                                    item.servico?.nome ?? 'Selecionar...',
                                  ),
                                ),
                              ),
                            ),
                            if (_itens.length > 1)
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () => _removerItem(index),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(width: 32),
                            Expanded(
                              child:
                                  DropdownButtonFormField<
                                    ProfissionalBasicoRegistro
                                  >(
                                    decoration: const InputDecoration(
                                      labelText: 'Profissional',
                                      isDense: true,
                                      contentPadding: EdgeInsets.all(8),
                                    ),
                                    initialValue: item.profissional,
                                    items: widget.profissionais
                                        .map(
                                          (p) => DropdownMenuItem(
                                            value: p,
                                            child: Text(p.nome),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (p) =>
                                        setState(() => item.profissional = p),
                                  ),
                            ),
                          ],
                        ),
                        if (item.inicioPrevisto != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 32),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${DateFormat('HH:mm').format(item.inicioPrevisto!)} às ${DateFormat('HH:mm').format(item.fimPrevisto!)}',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0EBF7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Duração Total',
                        style: TextStyle(color: Color(0xFF70569A)),
                      ),
                      Text(
                        '${duracaoTotal.inHours}h ${duracaoTotal.inMinutes.remainder(60)}m',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Total Previsto',
                        style: TextStyle(color: Color(0xFF70569A)),
                      ),
                      Text(
                        'R\$ ${valorTotal.toStringAsFixed(2).replaceAll('.', ',')}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _salvando ? null : _salvar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5D408B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _salvando
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Confirmar Agendamento',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
