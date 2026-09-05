import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/domain/agendamento_grupo_registro.dart';
import '../models/domain/pacote_servico.dart';
import '../models/domain/atendimento.dart';
import '../repositories/agenda_repository.dart';
import '../repositories/cadastros_basicos_repository.dart';
import '../repositories/cliente_repository.dart';
import '../repositories/pacotes_repository.dart';
import '../repositories/servicos_repository.dart';
import '../widgets/selectors/cliente_smart_selector.dart';
import '../widgets/selectors/servico_smart_selector.dart';
import '../repositories/agenda_completa_repository.dart';

class NovoAgendamentoSheet extends StatefulWidget {
  final DateTime dataBase;
  final List<ProfissionalBasicoRegistro> profissionais;
  final ClienteRegistro? clienteInicial;
  final ResumoVendaPacote? pacoteInicial;
  final SessaoPacoteDetalheRegistro? sessaoInicial;
  final AgendamentoRegistro? agendamentoInicial;
  final DateTime? horarioInicial;
  final String? profissionalInicialId;

  const NovoAgendamentoSheet({
    super.key,
    required this.dataBase,
    required this.profissionais,
    this.clienteInicial,
    this.pacoteInicial,
    this.sessaoInicial,
    this.agendamentoInicial,
    this.horarioInicial,
    this.profissionalInicialId,
  });

  @override
  State<NovoAgendamentoSheet> createState() => _NovoAgendamentoSheetState();
}

class _ItemServico {
  ServicoRegistro? servico;
  SessaoDisponivelRegistro? sessao;
  ProfissionalBasicoRegistro? profissional;
  DateTime? inicioPrevisto;
  DateTime? fimPrevisto;
  bool selecionado = true;

  _ItemServico({this.profissional})
    : servico = null,
      inicioPrevisto = null,
      fimPrevisto = null;
}

class _NovoAgendamentoSheetState extends State<NovoAgendamentoSheet> {
  static const Color _corFundo = Color(0xFFF9F6FC);

  final TextEditingController _observacoesController = TextEditingController();
  final AgendaRepository _agendaRepository = AgendaRepository();
  final PacotesRepository _pacotesRepository = PacotesRepository();
  final AgendaCompletaRepository _agendaCompletaRepository =
      AgendaCompletaRepository();
  final TextEditingController _bloqueioDescricaoController =
      TextEditingController();

  ClienteRegistro? _clienteSelecionado;
  late DateTime _dataSelecionada;
  TimeOfDay _horarioSelecionado = const TimeOfDay(hour: 9, minute: 0);

  bool _modoPacote = false;
  bool _modoBloqueio = false;
  bool _bloqueioDiaInteiro = false;
  TimeOfDay _bloqueioFim = const TimeOfDay(hour: 10, minute: 0);
  ProfissionalBasicoRegistro? _profissionalBloqueio;
  List<ResumoVendaPacote> _pacotesAtivos = [];
  ResumoVendaPacote? _pacoteSelecionado;
  bool _carregandoSessoes = false;

  final List<_ItemServico> _itens = [];

  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _dataSelecionada =
        widget.agendamentoInicial?.inicio ??
        DateTime(
          widget.dataBase.year,
          widget.dataBase.month,
          widget.dataBase.day,
        );
    _horarioSelecionado = widget.agendamentoInicial != null
        ? TimeOfDay(
            hour: widget.agendamentoInicial!.inicio.hour,
            minute: widget.agendamentoInicial!.inicio.minute,
          )
        : widget.horarioInicial != null
        ? TimeOfDay.fromDateTime(widget.horarioInicial!)
        : const TimeOfDay(hour: 9, minute: 0);
    _clienteSelecionado =
        widget.clienteInicial ??
        (widget.agendamentoInicial != null
            ? ClienteRegistro(
                id: widget.agendamentoInicial!.clienteId,
                nome: widget.agendamentoInicial!.clienteNome,
                telefone: '',
                dataCadastro: DateTime.now(),
                observacoes: '',
                totalAtendimentos: 0,
                totalGasto: 0,
                ultimoServico: '',
                profissional: '',
                whatsapp: '',
              )
            : null);
    if (widget.agendamentoInicial != null) {
      _observacoesController.text = widget.agendamentoInicial!.observacoes;
    }
    _profissionalBloqueio = widget.profissionais.isNotEmpty
        ? widget.profissionais.first
        : null;
    _modoPacote = widget.pacoteInicial != null || widget.sessaoInicial != null;

    if (widget.pacoteInicial != null) {
      _pacoteSelecionado = widget.pacoteInicial;
      _pacotesAtivos = [widget.pacoteInicial!];
      _carregarSessoesDoPacote().then((_) {
        if (widget.sessaoInicial != null) {
          if (!mounted) return;
          setState(() {
            for (final item in _itens) {
              item.selecionado =
                  item.sessao?.sessaoId == widget.sessaoInicial!.id;
            }
          });
        }
      });
    } else {
      if (widget.agendamentoInicial != null) {
        _carregarEdicao(widget.agendamentoInicial!);
      } else {
        _adicionarItem();
      }
      if (_clienteSelecionado != null && _modoPacote) {
        _carregarPacotesAtivos();
      }
    }
  }

  Future<void> _carregarEdicao(AgendamentoRegistro ag) async {
    final srvRepo = ServicosRepository();
    final cliRepo = ClienteRepository();
    try {
      final srv = await srvRepo.listar().then(
        (l) => l.firstWhere((s) => s.id == ag.servicoId),
      );
      final cli = await cliRepo.buscarPorId(ag.clienteId);

      if (!mounted) return;
      setState(() {
        if (cli != null) {
          _clienteSelecionado = cli;
        }
        _itens.add(
          _ItemServico(
              profissional: widget.profissionais.firstWhere(
                (p) => p.id == ag.profissionalId,
                orElse: () => widget.profissionais.first,
              ),
            )
            ..servico = srv
            ..inicioPrevisto = ag.inicio
            ..fimPrevisto = ag.fim,
        );
      });
    } catch (e) {
      _adicionarItem();
    }
  }

  Future<void> _carregarPacotesAtivos() async {
    if (_clienteSelecionado == null) return;
    setState(() {
      _carregandoSessoes = true;
      _pacotesAtivos = [];
      _pacoteSelecionado = null;
      for (var item in _itens) {
        item.sessao = null;
      }
    });
    try {
      final pacotes = await _pacotesRepository
          .listarPacotesVendidosAtivosDoCliente(_clienteSelecionado!.id);
      if (mounted) {
        setState(() {
          _pacotesAtivos = pacotes;
        });
      }
    } catch (e) {
      _mostrarErro('Erro ao carregar pacotes: $e');
    } finally {
      if (mounted) setState(() => _carregandoSessoes = false);
    }
  }

  Future<void> _carregarSessoesDoPacote() async {
    if (_pacoteSelecionado == null) return;
    setState(() => _carregandoSessoes = true);
    try {
      final todasSessoes = await _pacotesRepository
          .listarSessoesDisponiveisDoPacote(_pacoteSelecionado!.id);
      final sessoes = todasSessoes
          .map(
            (s) => SessaoDisponivelRegistro(
              sessaoId: s.id,
              pacoteNome: _pacoteSelecionado!.pacoteNome,
              servicoId: s.servicoId,
              servicoNome: s.servicoNome,
              pacoteVendidoId: _pacoteSelecionado!.id,
              duracaoMinutos: s.duracaoMinutos,
            ),
          )
          .toList();
      if (mounted) {
        setState(() {
          _itens
            ..clear()
            ..addAll(
              sessoes.map(
                (sessao) => _ItemServico(
                  profissional: widget.profissionais.isNotEmpty
                      ? widget.profissionais.first
                      : null,
                )..sessao = sessao,
              ),
            );
          _recalcularHorarios();
        });
      }
    } catch (e) {
      _mostrarErro('Erro ao carregar sessões: $e');
    } finally {
      if (mounted) setState(() => _carregandoSessoes = false);
    }
  }

  void _adicionarItem() {
    setState(() {
      _itens.add(
        _ItemServico(
          profissional:
              widget.profissionais
                  .where((item) => item.id == widget.profissionalInicialId)
                  .firstOrNull ??
              (widget.profissionais.isNotEmpty
                  ? widget.profissionais.first
                  : null),
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
      if (_modoPacote && item.inicioPrevisto != null) {
        final duracao = item.sessao?.duracaoMinutos ?? 30;
        item.fimPrevisto = item.inicioPrevisto!.add(Duration(minutes: duracao));
        continue;
      }
      item.inicioPrevisto = current;
      int duracao = 30;
      if (_modoPacote && item.sessao != null) {
        duracao = item.sessao!.duracaoMinutos;
      } else if (item.servico != null) {
        duracao = item.servico!.duracaoMinutos;
      }
      current = current.add(Duration(minutes: duracao));
      item.fimPrevisto = current;
    }
  }

  Future<void> _selecionarHorarioDoItem(_ItemServico item) async {
    final atual =
        item.inicioPrevisto ??
        DateTime(
          _dataSelecionada.year,
          _dataSelecionada.month,
          _dataSelecionada.day,
          _horarioSelecionado.hour,
          _horarioSelecionado.minute,
        );
    final data = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      locale: const Locale('pt', 'BR'),
    );
    if (data == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(atual),
    );
    if (hora == null) return;
    setState(() {
      item.inicioPrevisto = DateTime(
        data.year,
        data.month,
        data.day,
        hora.hour,
        hora.minute,
      );
      final duracao = item.sessao?.duracaoMinutos ?? 30;
      item.fimPrevisto = item.inicioPrevisto!.add(Duration(minutes: duracao));
    });
  }

  Future<void> _salvar() async {
    final itensSelecionados = _modoPacote
        ? _itens.where((item) => item.selecionado).toList()
        : _itens;
    if (_clienteSelecionado == null) {
      _mostrarErro('Selecione um cliente.');
      return;
    }
    if (itensSelecionados.isEmpty) {
      _mostrarErro('Selecione pelo menos uma sessão.');
      return;
    }
    if (itensSelecionados.any(
      (i) =>
          (_modoPacote ? i.sessao == null : i.servico == null) ||
          i.profissional == null,
    )) {
      _mostrarErro('Preencha todos os serviços/sessões e profissionais.');
      return;
    }
    if (_modoPacote) {
      final ids = itensSelecionados
          .map((item) => item.sessao!.sessaoId)
          .toList();
      if (ids.toSet().length != ids.length) {
        _mostrarErro('Selecione cada sessão apenas uma vez.');
        return;
      }
    }

    setState(() => _salvando = true);

    try {
      final agora = DateTime.now();
      if (_modoPacote) {
        final drafts = itensSelecionados.map((item) {
          return SessaoPacoteAgendamentoDraft(
            sessaoId: item.sessao!.sessaoId,
            inicio: item.inicioPrevisto!,
            profissionalId: item.profissional!.id,
            duracaoMinutos: item.sessao!.duracaoMinutos,
          );
        }).toList();

        await _pacotesRepository.agendarSessoesLote(drafts);
      } else if (widget.agendamentoInicial != null) {
        // EDICAO DE UM AGENDAMENTO
        final item = _itens.first;
        final ag = AgendamentoRegistro(
          id: widget.agendamentoInicial!.id,
          clienteId: _clienteSelecionado!.id,
          clienteNome: _clienteSelecionado!.nome,
          profissionalId: item.profissional!.id,
          profissionalNome: item.profissional!.nome,
          servicoId: item.servico!.id,
          servicoNome: item.servico!.nome,
          inicio: item.inicioPrevisto!,
          fim: item.fimPrevisto!,
          status: widget.agendamentoInicial!.status,
          valorServico: item.servico!.preco,
          desconto: widget.agendamentoInicial!.desconto,
          valorRecebido: widget.agendamentoInicial!.valorRecebido,
          confirmado: widget.agendamentoInicial!.confirmado,
          compareceu: widget.agendamentoInicial!.compareceu,
          dataCriacao: widget.agendamentoInicial!.dataCriacao,
          grupoAgendamentoId: widget.agendamentoInicial!.grupoAgendamentoId,
          ordemNoGrupo: widget.agendamentoInicial!.ordemNoGrupo,
          observacoes: _observacoesController.text.trim(),
        );
        await _agendaCompletaRepository.atualizarCompleto(ag);
      } else {
        final grupoId = agora.microsecondsSinceEpoch.toString();

        final grupo = AgendamentoGrupoRegistro(
          id: grupoId,
          businessId: '',
          clienteId: _clienteSelecionado!.id,
          status: 'agendado',
          observacoes: _observacoesController.text.trim(),
          createdAt: agora,
          updatedAt: agora,
        );

        final listaAgendamentos = <AgendamentoRegistro>[];
        for (var i = 0; i < _itens.length; i++) {
          final item = _itens[i];
          final servId = item.servico!.id;
          final servNome = item.servico!.nome;
          final servValor = item.servico!.preco;

          listaAgendamentos.add(
            AgendamentoRegistro(
              id: '${grupoId}_$i',
              clienteId: _clienteSelecionado!.id,
              clienteNome: _clienteSelecionado!.nome,
              profissionalId: item.profissional!.id,
              profissionalNome: item.profissional!.nome,
              servicoId: servId,
              servicoNome: servNome,
              inicio: item.inicioPrevisto!,
              fim: item.fimPrevisto!,
              status: 'agendado',
              valorServico: servValor,
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

        final agendaCompleta = AgendaCompletaRepository();
        for (var i = 0; i < listaAgendamentos.length; i++) {
          final ag = listaAgendamentos[i];
          await agendaCompleta.registrarStatus(
            agendamentoId: ag.id,
            status: 'agendado',
            detalhes: 'Agendamento criado via grupo.',
          );
        }
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

  Future<void> _salvarBloqueio() async {
    if (_profissionalBloqueio == null) {
      _mostrarErro('Selecione o profissional do bloqueio.');
      return;
    }
    final inicio = _bloqueioDiaInteiro
        ? DateTime(
            _dataSelecionada.year,
            _dataSelecionada.month,
            _dataSelecionada.day,
          )
        : DateTime(
            _dataSelecionada.year,
            _dataSelecionada.month,
            _dataSelecionada.day,
            _horarioSelecionado.hour,
            _horarioSelecionado.minute,
          );
    final fim = _bloqueioDiaInteiro
        ? inicio.add(const Duration(days: 1))
        : DateTime(
            _dataSelecionada.year,
            _dataSelecionada.month,
            _dataSelecionada.day,
            _bloqueioFim.hour,
            _bloqueioFim.minute,
          );
    if (!fim.isAfter(inicio)) {
      _mostrarErro('O fim do bloqueio deve ser posterior ao início.');
      return;
    }
    setState(() => _salvando = true);
    try {
      await _agendaCompletaRepository.adicionarBloqueio(
        BloqueioAgenda(
          id: '',
          profissionalId: _profissionalBloqueio!.id,
          profissionalNome: _profissionalBloqueio!.nome,
          inicio: inicio,
          fim: fim,
          tipo: _bloqueioDiaInteiro ? 'dia_inteiro' : 'bloqueio',
          motivo: _bloqueioDescricaoController.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (erro) {
      _mostrarErro('Não foi possível salvar o bloqueio: $erro');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _seletorModoPrincipal() => SegmentedButton<bool>(
    segments: const [
      ButtonSegment(
        value: false,
        label: Text('Agendamento'),
        icon: Icon(Icons.event_available),
      ),
      ButtonSegment(
        value: true,
        label: Text('Bloqueio'),
        icon: Icon(Icons.event_busy),
      ),
    ],
    selected: {_modoBloqueio},
    onSelectionChanged: (valor) => setState(() => _modoBloqueio = valor.first),
  );

  Widget _buildBloqueio(double teclado) => Container(
    padding: EdgeInsets.fromLTRB(22, 22, 22, teclado + 25),
    decoration: const BoxDecoration(
      color: _corFundo,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Novo item da agenda',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          _seletorModoPrincipal(),
          const SizedBox(height: 18),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Dia inteiro')),
              ButtonSegment(value: false, label: Text('Por horário')),
            ],
            selected: {_bloqueioDiaInteiro},
            onSelectionChanged: (valor) =>
                setState(() => _bloqueioDiaInteiro = valor.first),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<ProfissionalBasicoRegistro>(
            initialValue: _profissionalBloqueio,
            decoration: const InputDecoration(labelText: 'Profissional'),
            items: widget.profissionais
                .map((p) => DropdownMenuItem(value: p, child: Text(p.nome)))
                .toList(),
            onChanged: (valor) => setState(() => _profissionalBloqueio = valor),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Data'),
            subtitle: Text(DateFormat('dd/MM/yyyy').format(_dataSelecionada)),
            onTap: () async {
              final data = await showDatePicker(
                context: context,
                initialDate: _dataSelecionada,
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 730)),
              );
              if (data != null) setState(() => _dataSelecionada = data);
            },
          ),
          if (!_bloqueioDiaInteiro)
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Início'),
                    subtitle: Text(_horarioSelecionado.format(context)),
                    onTap: () async {
                      final hora = await showTimePicker(
                        context: context,
                        initialTime: _horarioSelecionado,
                      );
                      if (hora != null) {
                        setState(() => _horarioSelecionado = hora);
                      }
                    },
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fim'),
                    subtitle: Text(_bloqueioFim.format(context)),
                    onTap: () async {
                      final hora = await showTimePicker(
                        context: context,
                        initialTime: _bloqueioFim,
                      );
                      if (hora != null) setState(() => _bloqueioFim = hora);
                    },
                  ),
                ),
              ],
            ),
          TextField(
            controller: _bloqueioDescricaoController,
            decoration: const InputDecoration(
              labelText: 'Descrição (opcional)',
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _salvando ? null : _salvarBloqueio,
            icon: const Icon(Icons.block),
            label: const Text('Salvar bloqueio'),
          ),
        ],
      ),
    ),
  );

  void _mostrarErro(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    if (_modoBloqueio) return _buildBloqueio(teclado);

    double valorTotal = 0;
    Duration duracaoTotal = Duration.zero;
    for (var i in _itens) {
      if (_modoPacote && i.sessao != null) {
        duracaoTotal += Duration(minutes: i.sessao!.duracaoMinutos);
        // Pacote não soma valor
      } else if (!_modoPacote && i.servico != null) {
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
                Expanded(
                  child: Text(
                    widget.agendamentoInicial != null
                        ? 'Editar Agendamento'
                        : (_modoBloqueio
                              ? 'Novo Bloqueio'
                              : 'Novo Agendamento'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Serviço'),
                      icon: Icon(Icons.add),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Pacote'),
                      icon: Icon(Icons.add_box),
                    ),
                  ],
                  selected: {_modoPacote},
                  onSelectionChanged: (Set<bool> newSelection) {
                    setState(() {
                      _modoPacote = newSelection.first;
                      _itens.clear();
                      _adicionarItem();
                    });
                    if (_modoPacote &&
                        _clienteSelecionado != null &&
                        _pacotesAtivos.isEmpty) {
                      _carregarPacotesAtivos();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            _seletorModoPrincipal(),
            const SizedBox(height: 22),
            InkWell(
              onTap: () async {
                final cliente = await ClienteSmartSelector.show(context);
                if (cliente != null) {
                  setState(() => _clienteSelecionado = cliente);
                  if (_modoPacote) _carregarPacotesAtivos();
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
            if (_modoPacote) ...[
              const SizedBox(height: 14),
              Text(
                _carregandoSessoes && _pacoteSelecionado == null
                    ? 'Carregando pacotes...'
                    : 'Pacotes vendidos ativos',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (!_carregandoSessoes && _pacotesAtivos.isEmpty)
                const Card(
                  child: ListTile(
                    title: Text('Nenhum pacote vendido com saldo disponível.'),
                  ),
                ),
              ..._pacotesAtivos.map(
                (pacote) => Card(
                  color: _pacoteSelecionado?.id == pacote.id
                      ? const Color(0xFFEDE4F5)
                      : null,
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(pacote.pacoteNome),
                    subtitle: Text(
                      '${pacote.disponiveis} de ${pacote.contratadas} disponíveis',
                    ),
                    trailing: _pacoteSelecionado?.id == pacote.id
                        ? const Icon(Icons.check_circle)
                        : const Icon(Icons.chevron_right),
                    onTap: () {
                      setState(() => _pacoteSelecionado = pacote);
                      _carregarSessoesDoPacote();
                    },
                  ),
                ),
              ),
            ],
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
                              child: _modoPacote
                                  ? CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      value: item.selecionado,
                                      title: Text(
                                        item.sessao?.servicoNome ?? 'Sessão',
                                      ),
                                      subtitle: const Text('DISPONÍVEL'),
                                      onChanged: (valor) => setState(
                                        () => item.selecionado = valor ?? false,
                                      ),
                                    )
                                  : InkWell(
                                      onTap: () async {
                                        final servico =
                                            await ServicoSmartSelector.show(
                                              context,
                                            );
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
                            if (!_modoPacote)
                              IconButton(
                                icon: const Icon(
                                  Icons.add_circle,
                                  color: Color(0xFF5D408B),
                                ),
                                onPressed: _adicionarItem,
                              ),
                            if (!_modoPacote && _itens.length > 1)
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
                        if (_modoPacote && item.inicioPrevisto != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 32),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () => _selecionarHorarioDoItem(item),
                                icon: const Icon(Icons.edit_calendar_outlined),
                                label: Text(
                                  '${DateFormat('dd/MM HH:mm').format(item.inicioPrevisto!)} às ${DateFormat('HH:mm').format(item.fimPrevisto!)}',
                                ),
                              ),
                            ),
                          )
                        else if (item.inicioPrevisto != null)
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
