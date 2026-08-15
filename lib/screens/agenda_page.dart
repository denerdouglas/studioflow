import 'package:flutter/material.dart';

import '../repositories/agenda_completa_repository.dart';
import '../repositories/agenda_repository.dart';
import '../repositories/modalidades_repository.dart';
import 'disponibilidade_page.dart';
import '../repositories/cadastros_basicos_repository.dart';
import '../repositories/cliente_repository.dart';
import '../models/domain/configuracao_comercio.dart';
import '../models/domain/acesso.dart';
import '../models/domain/mensagem_modelo.dart';
import '../models/domain/atendimento.dart';
import '../repositories/configuracoes_repository.dart';
import '../repositories/modelos_mensagens_repository.dart';
import '../repositories/pagamento_repository.dart';
import '../services/mensagem_service.dart';
import '../services/session_controller.dart';
import '../services/whatsapp_queue_service.dart';
import '../widgets/mensagem_revisao_dialog.dart';
import 'novo_agendamento_sheet.dart';

class AgendaPage extends StatefulWidget {
  final ClienteRegistro? clienteInicial;

  const AgendaPage({super.key, this.clienteInicial});

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  Color get _corPrincipal => Theme.of(context).colorScheme.primary;
  Color get _corFundo => Theme.of(context).colorScheme.surface;
  Color get _textoEscuro => Theme.of(context).colorScheme.onSurface;
  Color get _textoClaro => Theme.of(context).colorScheme.onSurfaceVariant;

  final AgendaRepository _agendaRepository = AgendaRepository();
  final ModalidadesRepository _modalidadesRepository = ModalidadesRepository();
  final AgendaCompletaRepository _agendaCompletaRepository =
      AgendaCompletaRepository();
  final PagamentoRepository _pagamentoRepository = PagamentoRepository();

  final CadastrosBasicosRepository _cadastrosRepository =
      CadastrosBasicosRepository();

  final ClienteRepository _clienteRepository = ClienteRepository();

  DateTime _dataSelecionada = DateTime.now();

  List<AgendamentoRegistro> _agendamentos = [];
  List<BloqueioAgenda> _bloqueios = [];
  List<ClienteRegistro> _clientes = [];
  List<ProfissionalBasicoRegistro> _profissionais = [];
  List<ModalidadeRegistro> _modalidades = const [];
  String? _modalidadeId;
  Set<String> _servicosModalidade = const {};
  Set<String> _profissionaisModalidade = const {};

  bool _carregando = true;
  bool _abriuFormularioInicial = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarTudo();
  }

  Future<void> _carregarTudo() async {
    try {
      await _cadastrosRepository.garantirDadosIniciais();

      final resultados = await Future.wait([
        _agendaRepository.listarPorDia(_dataSelecionada),
        _clienteRepository.listar(),
        _cadastrosRepository.listarProfissionais(),
        _modalidadesRepository.listar(incluirInativas: false),
        _agendaCompletaRepository.listarBloqueios(
          aPartirDe: DateTime(
            _dataSelecionada.year,
            _dataSelecionada.month,
            _dataSelecionada.day,
          ),
        ),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _agendamentos = resultados[0] as List<AgendamentoRegistro>;

        _clientes = resultados[1] as List<ClienteRegistro>;

        _profissionais = resultados[2] as List<ProfissionalBasicoRegistro>;

        _modalidades = resultados[3] as List<ModalidadeRegistro>;
        final inicioDia = DateTime(
          _dataSelecionada.year,
          _dataSelecionada.month,
          _dataSelecionada.day,
        );
        final fimDia = inicioDia.add(const Duration(days: 1));
        _bloqueios = (resultados[4] as List<BloqueioAgenda>)
            .where(
              (bloqueio) =>
                  bloqueio.inicio.isBefore(fimDia) &&
                  bloqueio.fim.isAfter(inicioDia),
            )
            .toList();

        _carregando = false;
        _erro = null;
      });

      if (widget.clienteInicial != null && !_abriuFormularioInicial) {
        _abriuFormularioInicial = true;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _novoAgendamento(clienteInicial: widget.clienteInicial);
          }
        });
      }
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
        _erro = 'Não foi possível carregar a agenda.';
      });
    }
  }

  Future<void> _selecionarData() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataSelecionada,
      firstDate: DateTime(2025),
      lastDate: DateTime(2035),
      locale: const Locale('pt', 'BR'),
    );

    if (data == null) {
      return;
    }

    setState(() {
      _dataSelecionada = data;
      _carregando = true;
    });

    await _carregarTudo();
  }

  Future<void> _novoAgendamento({ClienteRegistro? clienteInicial}) async {
    if (_profissionais.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não existem profissionais cadastrados.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    ClienteRegistro? clienteSelecionada = clienteInicial;

    if (clienteSelecionada != null) {
      final existeNaLista = _clientes.any(
        (cliente) => cliente.id == clienteSelecionada!.id,
      );

      if (!existeNaLista) {
        clienteSelecionada = null;
      }
    }

    final novo = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return NovoAgendamentoSheet(
          dataBase: _dataSelecionada,
          profissionais: _profissionais,
          clienteInicial: clienteSelecionada,
        );
      },
    );

    if (novo == true) {
      setState(() {
        _carregando = true;
      });
      await _carregarTudo();
    }
  }

  Future<void> _abrirOpcoesAgendamento(AgendamentoRegistro agendamento) async {
    final acao = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return OpcoesAgendamentoSheet(
          agendamento: agendamento,
          podeExcluir:
              SessionController.instance.usuario?.podeAcao(
                AcaoPermissao.excluirAgendamento,
              ) ??
              false,
        );
      },
    );

    if (acao == null) {
      return;
    }

    if (acao == 'concluir') {
      await _concluirAgendamento(agendamento);
      return;
    }

    if (acao == 'registrar_pagamento') {
      await _registrarPagamento(agendamento);
      return;
    }

    if (acao == 'reagendar') {
      await _reagendarAgendamento(agendamento);
      return;
    }

    if (acao == 'reagendar_grupo' && agendamento.grupoAgendamentoId != null) {
      await _reagendarAgendamento(agendamento, reagendarGrupo: true);
      return;
    }

    if (acao == 'historico') {
      await _mostrarHistorico(agendamento);
      return;
    }

    try {
      if (acao == 'confirmar') {
        await _agendaCompletaRepository.registrarStatus(
          agendamentoId: agendamento.id,
          status: 'confirmado',
        );
      }

      if (acao == 'cancelar') {
        final motivo = await _solicitarMotivo(
          titulo: 'Cancelar agendamento',
          mensagem:
              'Informe o motivo. As mensagens pendentes deste horário serão canceladas.',
          rotuloBotao: 'Cancelar',
        );
        if (motivo == null) return;
        await _agendaCompletaRepository.registrarStatus(
          agendamentoId: agendamento.id,
          status: 'cancelado',
          detalhes: motivo,
        );
      }

      if (acao == 'cancelar_grupo' && agendamento.grupoAgendamentoId != null) {
        final motivo = await _solicitarMotivo(
          titulo: 'Cancelar grupo inteiro',
          mensagem:
              'Deseja cancelar o atendimento completo de ${agendamento.clienteNome}? Todos os serviços serão cancelados.',
          rotuloBotao: 'Cancelar grupo',
        );
        if (motivo == null) return;

        await _agendaRepository.cancelarGrupo(agendamento.grupoAgendamentoId!);
      }

      if (acao == 'lembrete') {
        await _mostrarOpcoesLembrete(agendamento);
        return;
      }

      if (acao == 'faltou') {
        await _agendaCompletaRepository.registrarStatus(
          agendamentoId: agendamento.id,
          status: 'faltou',
        );
      }

      if (acao == 'excluir') {
        final motivo = await _confirmarExclusao(agendamento);
        if (motivo == null) return;
        await _agendaCompletaRepository.excluirSeguro(
          agendamentoId: agendamento.id,
          motivo: motivo,
        );
      }

      setState(() {
        _carregando = true;
      });

      await _carregarTudo();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensagemDaAcao(acao)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível atualizar o agendamento.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _concluirAgendamento(AgendamentoRegistro agendamento) async {
    final valorRecebido = await showDialog<double>(
      context: context,
      builder: (_) {
        return ConcluirAgendamentoDialog(
          valorInicial: (agendamento.valorFinal - agendamento.valorRecebido)
              .clamp(0, double.infinity),
        );
      },
    );

    if (valorRecebido == null) {
      return;
    }

    try {
      await _agendaRepository.concluirAgendamento(
        agendamentoId: agendamento.id,
        valorRecebido: valorRecebido,
      );

      setState(() {
        _carregando = true;
      });

      await _carregarTudo();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Atendimento concluído.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _mostrarConclusao(agendamento, valorRecebido);
    } catch (erro) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível concluir o atendimento.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _registrarPagamento(AgendamentoRegistro agendamento) async {
    final saldo = (agendamento.valorFinal - agendamento.valorRecebido)
        .clamp(0, double.infinity)
        .toDouble();
    final valor = await showDialog<double>(
      context: context,
      builder: (_) => ConcluirAgendamentoDialog(
        valorInicial: saldo,
        titulo: 'Registrar pagamento',
        instrucao: 'Informe o valor efetivamente recebido.',
        rotuloBotao: 'Registrar',
      ),
    );
    if (valor == null || valor <= 0) return;
    try {
      await _pagamentoRepository.registrarPagamentoAtendimento(
        agendamentoId: agendamento.id,
        valor: valor,
        formaPagamento: agendamento.formaPagamento ?? 'Não informado',
        referencia:
            '${agendamento.id}_${DateTime.now().microsecondsSinceEpoch}',
      );
      await _carregarTudo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pagamento registrado no financeiro.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível registrar o pagamento.'),
        ),
      );
    }
  }

  Future<void> _mostrarConclusao(
    AgendamentoRegistro agendamento,
    double valorRecebido,
  ) async {
    final comercioId = SessionController.instance.usuario!.comercioId;
    final resultados = await Future.wait([
      ModelosMensagensRepository().porChave(comercioId, 'resumo_comanda'),
      ConfiguracoesRepository().carregar(comercioId),
      ClienteRepository().buscarPorId(agendamento.clienteId),
    ]);
    final modelo = resultados[0] as ModeloMensagem;
    final comercio = resultados[1] as ConfiguracaoComercio;
    final cliente = resultados[2] as ClienteRegistro?;
    final dados = DadosMensagem(
      cliente: agendamento.clienteNome,
      salao: comercio.nomeExibicao,
      profissional: agendamento.profissionalNome,
      servico: agendamento.servicoNome,
      formaPagamento: agendamento.formaPagamento == 'Pacote'
          ? 'Pacote'
          : 'Conforme registrado no caixa',
      valorPago: valorRecebido,
      servicos: [
        ItemResumoMensagem(
          nome: agendamento.formaPagamento == 'Pacote'
              ? 'Sessão de Pacote [${agendamento.servicoNome}]'
              : agendamento.servicoNome,
          profissional: agendamento.profissionalNome,
          valorUnitario: agendamento.formaPagamento == 'Pacote'
              ? 0.0
              : agendamento.valorServico,
          desconto: agendamento.desconto,
        ),
      ],
    );
    final mensagem = const MensagemService().montar(modelo.texto, dados);
    if (!mounted) return;
    await mostrarRevisaoMensagem(
      context,
      titulo: 'Conclusão do atendimento',
      mensagem: mensagem,
      telefone: cliente?.whatsapp,
    );
  }

  Future<void> _reagendarAgendamento(
    AgendamentoRegistro agendamento, {
    bool reagendarGrupo = false,
  }) async {
    var data = agendamento.inicio;
    var horario = TimeOfDay.fromDateTime(agendamento.inicio);
    final motivo = TextEditingController();
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(
            reagendarGrupo
                ? 'Reagendar grupo completo'
                : 'Reagendar atendimento',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('Nova data'),
                subtitle: Text('${data.day}/${data.month}/${data.year}'),
                onTap: () async {
                  final valor = await showDatePicker(
                    context: context,
                    initialDate: data,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (valor != null) setLocal(() => data = valor);
                },
              ),
              ListTile(
                title: Text('Novo horário'),
                subtitle: Text(horario.format(context)),
                onTap: () async {
                  final valor = await showTimePicker(
                    context: context,
                    initialTime: horario,
                  );
                  if (valor != null) setLocal(() => horario = valor);
                },
              ),
              TextField(
                controller: motivo,
                decoration: const InputDecoration(
                  labelText: 'Motivo ou observação',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Reagendar'),
            ),
          ],
        ),
      ),
    );
    if (confirmou != true) return;
    final inicio = DateTime(
      data.year,
      data.month,
      data.day,
      horario.hour,
      horario.minute,
    );
    try {
      if (reagendarGrupo) {
        await _agendaRepository.remarcarGrupo(
          agendamento.grupoAgendamentoId!,
          inicio,
        );
      } else {
        await _agendaCompletaRepository.reagendar(
          agendamentoId: agendamento.id,
          novoInicio: inicio,
          novoFim: inicio.add(agendamento.fim.difference(agendamento.inicio)),
          motivo: motivo.text.trim(),
        );
      }

      _dataSelecionada = inicio;
      await _carregarTudo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Agendamento reagendado.')),
        );
      }
    } on ConflitoAgendaException catch (erro) {
      if (mounted) {
        await _mostrarResolucaoConflito(erro, (novoInicio, novoFim) async {
          try {
            if (reagendarGrupo) {
              await _agendaRepository.remarcarGrupo(
                agendamento.grupoAgendamentoId!,
                novoInicio,
              );
            } else {
              await _agendaCompletaRepository.reagendar(
                agendamentoId: agendamento.id,
                novoInicio: novoInicio,
                novoFim: novoFim,
              );
            }
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Agendamento reagendado com sucesso.'),
              ),
            );
            setState(() {
              _dataSelecionada = novoInicio;
              _carregando = true;
            });
            _carregarTudo();
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Erro ao reagendar: $e')));
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _mostrarHistorico(AgendamentoRegistro agendamento) async {
    final eventos = await _agendaCompletaRepository.listarHistorico(
      agendamento.id,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Histórico do agendamento'),
        content: SizedBox(
          width: double.maxFinite,
          child: eventos.isEmpty
              ? Text('Nenhuma alteração registrada ainda.')
              : ListView(
                  shrinkWrap: true,
                  children: eventos
                      .map(
                        (e) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.history),
                          title: Text(e.acao),
                          subtitle: Text(
                            '${e.data.day}/${e.data.month}/${e.data.year} ${e.data.hour.toString().padLeft(2, '0')}:${e.data.minute.toString().padLeft(2, '0')}\n${e.detalhes}',
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<String?> _confirmarExclusao(AgendamentoRegistro agendamento) async {
    final diagnostico = await _agendaCompletaRepository.diagnosticarExclusao(
      agendamento.id,
    );
    if (!mounted) return null;
    if (diagnostico.bloqueado) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Exclusão bloqueada'),
          content: Text(
            'Este horário possui atendimento concluído, recebimento, comissão, cobrança paga ou sessão de pacote. Faça os estornos necessários ou apenas cancele o agendamento.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Entendi'),
            ),
          ],
        ),
      );
      return null;
    }
    return _solicitarMotivo(
      titulo: 'Excluir agendamento de ${agendamento.clienteNome}?',
      mensagem:
          'A exclusão será lógica, auditada e preservará o histórico. Mensagens e cobranças pendentes serão canceladas.',
      rotuloBotao: 'Excluir com segurança',
      perigo: true,
    );
  }

  Future<String?> _solicitarMotivo({
    required String titulo,
    required String mensagem,
    required String rotuloBotao,
    bool perigo = false,
  }) async {
    final controller = TextEditingController();
    String? erro;
    final resultado = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(titulo),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(mensagem),
              SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Motivo obrigatório',
                  errorText: erro,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Voltar'),
            ),
            FilledButton(
              style: perigo
                  ? FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD64D64),
                    )
                  : null,
              onPressed: () {
                final motivo = controller.text.trim();
                if (motivo.length < 5) {
                  setLocal(() => erro = 'Informe pelo menos 5 caracteres.');
                  return;
                }
                Navigator.pop(context, motivo);
              },
              child: Text(rotuloBotao),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return resultado;
  }

  Future<void> _mostrarOpcoesLembrete(AgendamentoRegistro agendamento) async {
    final comercioId = SessionController.instance.usuario!.comercioId;
    final modelos = await ModelosMensagensRepository().listar(comercioId);

    if (!mounted) return;

    if (modelos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum modelo de mensagem cadastrado.')),
      );
      return;
    }

    final modeloSelecionado = await showDialog<ModeloMensagem>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Enviar lembrete'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: modelos.where((m) => m.ativo).map((modelo) {
              return ListTile(
                title: Text(modelo.nome),
                subtitle: Text(
                  modelo.texto,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, modelo),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar'),
          ),
        ],
      ),
    );

    if (modeloSelecionado == null) return;

    final configuracao = await ConfiguracoesRepository().carregar(comercioId);
    final cliente = await ClienteRepository().buscarPorId(
      agendamento.clienteId,
    );

    final dados = DadosMensagem(
      cliente: agendamento.clienteNome,
      salao: configuracao.nomeExibicao,
      profissional: agendamento.profissionalNome,
      servico: agendamento.servicoNome,
      data:
          '${agendamento.inicio.day.toString().padLeft(2, '0')}/${agendamento.inicio.month.toString().padLeft(2, '0')}/${agendamento.inicio.year}',
      hora:
          '${agendamento.inicio.hour.toString().padLeft(2, '0')}:${agendamento.inicio.minute.toString().padLeft(2, '0')}',
      formaPagamento: 'Conforme configurado',
      valorPago: 0.0,
      servicos: [
        ItemResumoMensagem(
          nome: agendamento.servicoNome,
          profissional: agendamento.profissionalNome,
          valorUnitario: agendamento.valorServico,
          desconto: agendamento.desconto,
        ),
      ],
    );

    final mensagem = const MensagemService().montar(
      modeloSelecionado.texto,
      dados,
    );

    if (!mounted) return;

    await mostrarRevisaoMensagem(
      context,
      titulo: 'Revisar lembrete',
      mensagem: mensagem,
      telefone: cliente?.whatsapp,
      onEnqueue: cliente?.whatsapp != null && cliente!.whatsapp.isNotEmpty
          ? (textoFinal) async {
              await WhatsappQueueService().enfileirarDireto(
                comercioId: comercioId,
                destinatario: cliente.whatsapp,
                texto: textoFinal,
                agendamentoId: agendamento.id,
              );
            }
          : null,
    );
  }

  String _mensagemDaAcao(String acao) {
    switch (acao) {
      case 'confirmar':
        return 'Agendamento confirmado.';
      case 'cancelar':
        return 'Agendamento cancelado.';
      case 'faltou':
        return 'Falta registrada.';
      case 'excluir':
        return 'Agendamento excluído.';
      default:
        return 'Agendamento atualizado.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _corFundo,
      body: SafeArea(
        child: Column(
          children: [
            _cabecalho(),
            _seletorData(),
            SizedBox(height: 10),
            _filtroModalidade(),
            SizedBox(height: 12),
            Expanded(child: _conteudo()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () {
          _novoAgendamento();
        },
        backgroundColor: _corPrincipal,
        foregroundColor: Colors.white,
        icon: Icon(Icons.add),
        label: Text(
          'Novo agendamento',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Future<void> _mostrarResolucaoConflito(
    ConflitoAgendaException erro,
    Function(DateTime, DateTime) onResolvido,
  ) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Conflito de Horário'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(erro.mensagem),
              SizedBox(height: 16),
              if (erro.sugestoes.isNotEmpty) ...[
                Text(
                  'Sugestões de horários livres:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                ...erro.sugestoes.take(5).map((alt) {
                  final dataStr =
                      '${alt.day.toString().padLeft(2, '0')}/${alt.month.toString().padLeft(2, '0')}';
                  final horaStr =
                      '${alt.hour.toString().padLeft(2, '0')}:${alt.minute.toString().padLeft(2, '0')}';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.check_circle_outline,
                      color: _corPrincipal,
                    ),
                    title: Text('$dataStr às $horaStr'),
                    onTap: () {
                      Navigator.of(context).pop();
                      // ConflitoAgendaException sugestoes are DateTime, but we need start and end.
                      // We can just assume duration was kept, so we re-add duration.
                      onResolvido(
                        alt,
                        alt.add(Duration(minutes: 30)),
                      ); // We need to calculate duration from agendamento
                    },
                  );
                }),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Widget _cabecalho() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Agenda',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _textoEscuro,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Horários, clientes e profissionais',
                  style: TextStyle(fontSize: 13, color: _textoClaro),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Jornadas e bloqueios',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DisponibilidadePage()),
            ),
            icon: Icon(Icons.event_available),
          ),
        ],
      ),
    );
  }

  Widget _seletorData() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: _selecionarData,
          borderRadius: BorderRadius.circular(17),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: const Color(0xFFE8E1EE)),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_month_outlined, color: _corPrincipal),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _formatarData(_dataSelecionada),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _textoEscuro,
                    ),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, color: _textoClaro),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filtroModalidade() => SizedBox(
    height: 40,
    child: ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      scrollDirection: Axis.horizontal,
      children: [
        ChoiceChip(
          label: Text('Todos'),
          selected: _modalidadeId == null,
          onSelected: (_) => setState(() {
            _modalidadeId = null;
            _servicosModalidade = const {};
            _profissionaisModalidade = const {};
          }),
        ),
        SizedBox(width: 8),
        ..._modalidades.map(
          (item) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(item.nome),
              selected: _modalidadeId == item.id,
              onSelected: (_) async {
                final links = await _modalidadesRepository.opcoesVinculos(
                  item.id,
                );
                if (!mounted) return;
                setState(() {
                  _modalidadeId = item.id;
                  _servicosModalidade = links['servicos']!
                      .where((row) => row['selecionado'] == 1)
                      .map((row) => row['id'] as String)
                      .toSet();
                  _profissionaisModalidade = links['profissionais']!
                      .where((row) => row['selecionado'] == 1)
                      .map((row) => row['id'] as String)
                      .toSet();
                });
              },
            ),
          ),
        ),
      ],
    ),
  );
  Widget _conteudo() {
    if (_carregando) {
      return Center(child: CircularProgressIndicator(color: _corPrincipal));
    }

    if (_erro != null) {
      return Center(child: Text(_erro!));
    }

    final visible = _modalidadeId == null
        ? _agendamentos
        : _agendamentos
              .where(
                (item) =>
                    _servicosModalidade.contains(item.servicoId) ||
                    _profissionaisModalidade.contains(item.profissionalId),
              )
              .toList();
    if (visible.isEmpty && _bloqueios.isEmpty) {
      return Center(
        child: Text('Nenhum agendamento ou bloqueio para este filtro.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
      itemCount: _bloqueios.length + visible.length,
      itemBuilder: (context, index) {
        if (index < _bloqueios.length) {
          final bloqueio = _bloqueios[index];
          return _BloqueioCard(
            bloqueio: bloqueio,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DisponibilidadePage()),
              );
              await _carregarTudo();
            },
          );
        }
        final agendamento = visible[index - _bloqueios.length];

        return _AgendamentoCard(
          agendamento: agendamento,
          onTap: () {
            _abrirOpcoesAgendamento(agendamento);
          },
        );
      },
    );
  }

  String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');

    final mes = data.month.toString().padLeft(2, '0');

    return '$dia/$mes/${data.year}';
  }
}

class _BloqueioCard extends StatelessWidget {
  final BloqueioAgenda bloqueio;
  final VoidCallback onTap;

  const _BloqueioCard({required this.bloqueio, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    color: const Color(0xFFFFF1F1),
    child: ListTile(
      onTap: onTap,
      leading: Icon(Icons.block, color: Colors.redAccent),
      title: Text(
        bloqueio.motivo.isEmpty ? 'Horário bloqueado' : bloqueio.motivo,
      ),
      subtitle: Text(
        '${bloqueio.profissionalNome} • ${_hora(bloqueio.inicio)}–${_hora(bloqueio.fim)}',
      ),
      trailing: Icon(Icons.edit_outlined),
    ),
  );

  static String _hora(DateTime data) =>
      '${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}';
}

class _AgendamentoCard extends StatelessWidget {
  final AgendamentoRegistro agendamento;
  final VoidCallback onTap;

  const _AgendamentoCard({required this.agendamento, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final corPrincipal = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE8E1EE)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 62,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: corPrincipal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _formatarHora(agendamento.inicio),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: corPrincipal,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        _formatarHora(agendamento.fim),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agendamento.clienteNome,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            Icons.content_cut,
                            size: 16,
                            color: corPrincipal,
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              agendamento.servicoNome,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.badge_outlined,
                            size: 16,
                            color: corPrincipal,
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              agendamento.profissionalNome,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 9),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          _StatusAgendamento(
                            texto: _textoStatus(agendamento.status),
                            cor: _corStatus(agendamento.status),
                          ),
                          if (agendamento.encaixe)
                            const _StatusAgendamento(
                              texto: 'Encaixe',
                              cor: Color(0xFFE58A25),
                            ),
                          _StatusAgendamento(
                            texto:
                                'R\$ ${agendamento.valorFinal.toStringAsFixed(2)}',
                            cor: corPrincipal,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.more_vert, color: Color(0xFF968AA5)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatarHora(DateTime data) {
    final hora = data.hour.toString().padLeft(2, '0');

    final minuto = data.minute.toString().padLeft(2, '0');

    return '$hora:$minuto';
  }

  String _textoStatus(String status) {
    switch (status) {
      case 'confirmado':
        return 'Confirmado';
      case 'concluido':
        return 'Concluído';
      case 'cancelado':
        return 'Cancelado';
      default:
        return 'Agendado';
    }
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'confirmado':
        return const Color(0xFF2EA779);
      case 'concluido':
        return const Color(0xFF2B83C6);
      case 'cancelado':
        return const Color(0xFFD64D64);
      default:
        return const Color(0xFFE58A25);
    }
  }
}

class _StatusAgendamento extends StatelessWidget {
  final String texto;
  final Color cor;

  const _StatusAgendamento({required this.texto, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cor),
      ),
    );
  }
}

class OpcoesAgendamentoSheet extends StatelessWidget {
  final AgendamentoRegistro agendamento;
  final bool podeExcluir;

  const OpcoesAgendamentoSheet({
    super.key,
    required this.agendamento,
    required this.podeExcluir,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                SizedBox(height: 20),
                Text(
                  agendamento.clienteNome,
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '${agendamento.servicoNome} • '
                  '${_formatarHora(agendamento.inicio)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: 22),
                _OpcaoAgendamento(
                  titulo: 'Confirmar',
                  icone: Icons.check_circle_outline,
                  cor: const Color(0xFF2EA779),
                  onTap: () {
                    Navigator.pop(context, 'confirmar');
                  },
                ),
                _OpcaoAgendamento(
                  titulo: 'Concluir atendimento',
                  icone: Icons.done_all,
                  cor: const Color(0xFF2B83C6),
                  onTap: () {
                    Navigator.pop(context, 'concluir');
                  },
                ),
                if (agendamento.status == 'concluido' &&
                    agendamento.pagamentoPendente &&
                    agendamento.formaPagamento != 'Pacote')
                  _OpcaoAgendamento(
                    titulo: 'Registrar pagamento',
                    icone: Icons.payments_outlined,
                    cor: const Color(0xFF2EA779),
                    onTap: () {
                      Navigator.pop(context, 'registrar_pagamento');
                    },
                  ),
                _OpcaoAgendamento(
                  titulo: 'Reagendar este serviço',
                  icone: Icons.edit_calendar_outlined,
                  cor: Theme.of(context).colorScheme.primary,
                  onTap: () {
                    Navigator.pop(context, 'reagendar');
                  },
                ),
                if (agendamento.grupoAgendamentoId != null)
                  _OpcaoAgendamento(
                    titulo:
                        'Reagendar o atendimento completo (todos os serviços)',
                    icone: Icons.calendar_month,
                    cor: const Color(0xFF5D408B),
                    onTap: () {
                      Navigator.pop(context, 'reagendar_grupo');
                    },
                  ),
                _OpcaoAgendamento(
                  titulo: 'Registrar falta',
                  icone: Icons.person_off_outlined,
                  cor: const Color(0xFF8D6E63),
                  onTap: () {
                    Navigator.pop(context, 'faltou');
                  },
                ),
                _OpcaoAgendamento(
                  titulo: 'Histórico',
                  icone: Icons.history,
                  cor: const Color(0xFF546E7A),
                  onTap: () {
                    Navigator.pop(context, 'historico');
                  },
                ),
                _OpcaoAgendamento(
                  titulo: 'Cancelar este serviço',
                  icone: Icons.cancel_outlined,
                  cor: const Color(0xFFE58A25),
                  onTap: () {
                    Navigator.pop(context, 'cancelar');
                  },
                ),
                if (agendamento.grupoAgendamentoId != null)
                  _OpcaoAgendamento(
                    titulo:
                        'Cancelar o atendimento completo (todos os serviços)',
                    icone: Icons.cancel,
                    cor: const Color(0xFFC76C12),
                    onTap: () {
                      Navigator.pop(context, 'cancelar_grupo');
                    },
                  ),
                _OpcaoAgendamento(
                  titulo: 'Enviar lembrete',
                  icone: Icons.chat_bubble_outline,
                  cor: const Color(0xFF00C853),
                  onTap: () {
                    Navigator.pop(context, 'lembrete');
                  },
                ),
                if (podeExcluir)
                  _OpcaoAgendamento(
                    titulo: 'Excluir agendamento',
                    icone: Icons.delete_outline,
                    cor: const Color(0xFFD64D64),
                    onTap: () {
                      Navigator.pop(context, 'excluir');
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatarHora(DateTime data) {
    final hora = data.hour.toString().padLeft(2, '0');

    final minuto = data.minute.toString().padLeft(2, '0');

    return '$hora:$minuto';
  }
}

class _OpcaoAgendamento extends StatelessWidget {
  final String titulo;
  final IconData icone;
  final Color cor;
  final VoidCallback onTap;

  const _OpcaoAgendamento({
    required this.titulo,
    required this.icone,
    required this.cor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icone, color: cor),
      ),
      title: Text(
        titulo,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      trailing: Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class ConcluirAgendamentoDialog extends StatefulWidget {
  final double valorInicial;
  final String titulo;
  final String instrucao;
  final String rotuloBotao;

  const ConcluirAgendamentoDialog({
    super.key,
    required this.valorInicial,
    this.titulo = 'Concluir atendimento',
    this.instrucao = 'Informe o valor recebido.',
    this.rotuloBotao = 'Concluir',
  });

  @override
  State<ConcluirAgendamentoDialog> createState() =>
      _ConcluirAgendamentoDialogState();
}

class _ConcluirAgendamentoDialogState extends State<ConcluirAgendamentoDialog> {
  late final TextEditingController _valorController;

  @override
  void initState() {
    super.initState();

    _valorController = TextEditingController(
      text: widget.valorInicial.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _valorController.dispose();
    super.dispose();
  }

  void _confirmar() {
    final texto = _valorController.text.trim().replaceAll(',', '.');

    final valor = double.tryParse(texto);

    if (valor == null || valor < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Digite um valor válido.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    Navigator.pop(context, valor);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.instrucao),
          SizedBox(height: 14),
          TextField(
            controller: _valorController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Valor recebido',
              prefixText: 'R\$ ',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text('Cancelar'),
        ),
        FilledButton(onPressed: _confirmar, child: Text(widget.rotuloBotao)),
      ],
    );
  }
}
