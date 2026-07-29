import 'package:flutter/material.dart';

import '../repositories/agenda_repository.dart';
import '../repositories/caixa_repository.dart';
import '../core/helpers/app_formatters.dart';
import '../core/theme/studioflow_theme.dart';
import 'agenda_page.dart';
import 'clientes_page.dart';
import 'mais_sprint2_page.dart';
import 'ia_local_page.dart';
import 'configuracoes_page.dart';
import '../models/domain/acesso.dart';
import '../services/session_controller.dart';

class DashboardPage extends StatefulWidget {
  final String nomeResponsavel;
  final String nomeNegocio;
  final String tipoNegocio;
  final StudioFlowTheme tema;

  const DashboardPage({
    super.key,
    required this.nomeResponsavel,
    required this.nomeNegocio,
    required this.tipoNegocio,
    required this.tema,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final AgendaRepository _agendaRepository = AgendaRepository();

  final CaixaRepository _caixaRepository = CaixaRepository();

  int _paginaSelecionada = 0;

  bool _carregandoResumo = true;
  String? _erroResumo;

  List<AgendamentoRegistro> _agendamentosHoje = [];
  ResumoCaixa _resumoCaixa = ResumoCaixa.vazio();

  @override
  void initState() {
    super.initState();
    _carregarResumo();
  }

  String get _saudacao {
    final hora = DateTime.now().hour;

    if (hora < 12) {
      return 'Bom dia';
    }

    if (hora < 18) {
      return 'Boa tarde';
    }

    return 'Boa noite';
  }

  List<AgendamentoRegistro> get _agendamentosValidos {
    return _agendamentosHoje.where((agendamento) {
      return agendamento.status != 'cancelado';
    }).toList();
  }

  double get _previsaoHoje {
    double total = 0;

    for (final agendamento in _agendamentosValidos) {
      total += agendamento.valorFinal;
    }

    return total;
  }

  AgendamentoRegistro? get _proximoAgendamento {
    final agora = DateTime.now();

    final proximos = _agendamentosValidos.where((agendamento) {
      return agendamento.inicio.isAfter(agora) ||
          agendamento.inicio.isAtSameMomentAs(agora);
    }).toList();

    proximos.sort((a, b) => a.inicio.compareTo(b.inicio));

    if (proximos.isEmpty) {
      return null;
    }

    return proximos.first;
  }

  Future<void> _carregarResumo() async {
    try {
      final agora = DateTime.now();

      final resultados = await Future.wait([
        _agendaRepository.listarPorDia(agora),
        _caixaRepository.resumoDoDia(agora),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _agendamentosHoje = resultados[0] as List<AgendamentoRegistro>;

        _resumoCaixa = resultados[1] as ResumoCaixa;

        _carregandoResumo = false;
        _erroResumo = null;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregandoResumo = false;
        _erroResumo = 'Não foi possível atualizar o resumo.';
      });
    }
  }

  void _mudarPagina(int indice) {
    setState(() {
      _paginaSelecionada = indice;
    });

    if (indice == 0) {
      _carregarResumo();
    }
  }

  @override
  Widget build(BuildContext context) {
    final paginas = [
      _construirInicio(),
      SessionController.instance.usuario!.pode(ModuloPermissao.agenda)
          ? const AgendaPage()
          : const Center(child: Text('Acesso nao permitido.')),
      SessionController.instance.usuario!.pode(ModuloPermissao.clientes)
          ? const ClientesPage()
          : const Center(child: Text('Acesso nao permitido.')),
      MaisSprint2Page(tema: widget.tema),
    ];

    return Scaffold(
      backgroundColor: widget.tema.fundo,
      appBar: _paginaSelecionada == 0
          ? AppBar(
              automaticallyImplyLeading: false,
              backgroundColor: widget.tema.fundo,
              surfaceTintColor: Colors.transparent,
              titleSpacing: 20,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_saudacao, '
                    '${widget.nomeResponsavel}! '
                    '${widget.tema.emoji}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D2140),
                    ),
                  ),
                  Text(
                    widget.nomeNegocio,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF766A85),
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Atualizar resumo',
                  onPressed: () {
                    setState(() {
                      _carregandoResumo = true;
                    });

                    _carregarResumo();
                  },
                  icon: Icon(Icons.refresh, color: widget.tema.corPrincipal),
                ),
                IconButton(
                  tooltip: 'StudioFlow IA',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const IaLocalPage()),
                    );
                  },
                  icon: Icon(
                    Icons.auto_awesome_outlined,
                    color: widget.tema.corPrincipal,
                  ),
                ),
                IconButton(
                  tooltip: 'Notificacoes',
                  onPressed: () {
                    final usuario = SessionController.instance.usuario!;
                    if (!usuario.pode(ModuloPermissao.configuracoes)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Acesso nao permitido.')),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ConfiguracoesPage(),
                      ),
                    );
                  },
                  icon: Icon(
                    Icons.notifications_none,
                    color: widget.tema.corPrincipal,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            )
          : null,
      body: IndexedStack(index: _paginaSelecionada, children: paginas),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _paginaSelecionada,
        backgroundColor: Colors.white,
        indicatorColor: widget.tema.corPrincipal.withValues(alpha: 0.14),
        onDestinationSelected: _mudarPagina,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Clientes',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Mais',
          ),
        ],
      ),
    );
  }

  Widget _construirInicio() {
    if (_carregandoResumo) {
      return Center(
        child: CircularProgressIndicator(color: widget.tema.corPrincipal),
      );
    }

    if (_erroResumo != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 62,
                color: Color(0xFFD64D64),
              ),
              const SizedBox(height: 14),
              Text(
                _erroResumo!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Color(0xFF2D2140)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _carregandoResumo = true;
                    _erroResumo = null;
                  });

                  _carregarResumo();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    final proximo = _proximoAgendamento;

    return RefreshIndicator(
      color: widget.tema.corPrincipal,
      onRefresh: _carregarResumo,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _construirResumoIa(),

            const SizedBox(height: 18),

            _construirCaixaReal(),

            const SizedBox(height: 25),

            const Text(
              'Resumo de hoje',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2140),
              ),
            ),

            const SizedBox(height: 13),

            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.92,
              children: [
                _construirIndicador(
                  titulo: 'Agendados',
                  valor: '${_agendamentosValidos.length}',
                  descricao: 'clientes hoje',
                  icone: Icons.people_alt_outlined,
                  cor: widget.tema.corPrincipal,
                ),
                _construirIndicador(
                  titulo: 'Previsão',
                  valor: AppFormatters.moeda(_previsaoHoje),
                  descricao: 'faturamento previsto',
                  icone: Icons.trending_up,
                  cor: const Color(0xFF15996B),
                ),
                _construirIndicador(
                  titulo: 'Próximo',
                  valor: proximo == null
                      ? '--:--'
                      : AppFormatters.hora(proximo.inicio),
                  descricao: proximo == null
                      ? 'nenhum horário futuro'
                      : '${proximo.clienteNome} — '
                            '${proximo.servicoNome}',
                  icone: Icons.access_time,
                  cor: const Color(0xFF3078C5),
                ),
                _construirIndicador(
                  titulo: 'Concluídos',
                  valor:
                      '${_agendamentosHoje.where((item) {
                        return item.status == 'concluido';
                      }).length}',
                  descricao: 'atendimentos finalizados',
                  icone: Icons.check_circle_outline,
                  cor: const Color(0xFFE58A25),
                ),
              ],
            ),

            const SizedBox(height: 25),

            const Text(
              'Alertas de hoje',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2140),
              ),
            ),

            const SizedBox(height: 13),

            if (_agendamentosValidos.isEmpty)
              _construirAlerta(
                titulo: 'Agenda livre',
                descricao: 'Nenhum atendimento ativo foi agendado para hoje.',
                icone: Icons.event_available_outlined,
                cor: const Color(0xFF3078C5),
              ),

            if (_agendamentosValidos.isNotEmpty)
              _construirAlerta(
                titulo: 'Agenda do dia',
                descricao:
                    '${_agendamentosValidos.length} atendimento(s) ativo(s) hoje.',
                icone: Icons.calendar_month_outlined,
                cor: widget.tema.corPrincipal,
              ),

            const SizedBox(height: 10),

            _construirAlerta(
              titulo: 'Entradas registradas',
              descricao:
                  '${_resumoCaixa.quantidadeEntradas} entrada(s), totalizando '
                  '${AppFormatters.moeda(_resumoCaixa.totalEntradas)}.',
              icone: Icons.arrow_downward_rounded,
              cor: const Color(0xFF15996B),
            ),

            const SizedBox(height: 10),

            _construirAlerta(
              titulo: 'Saídas registradas',
              descricao:
                  '${_resumoCaixa.quantidadeSaidas} saída(s), totalizando '
                  '${AppFormatters.moeda(_resumoCaixa.totalSaidas)}.',
              icone: Icons.arrow_upward_rounded,
              cor: const Color(0xFFD64D64),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirResumoIa() {
    final quantidade = _agendamentosValidos.length;

    final mensagem = quantidade == 0
        ? 'Sua agenda está livre hoje. Você pode divulgar os horários disponíveis.'
        : 'Você possui $quantidade atendimento(s) ativo(s) hoje, com previsão de '
              '${AppFormatters.moeda(_previsaoHoje)}.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6DFF0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: widget.tema.corPrincipal,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Resumo StudioFlow',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Color(0xFF2D2140),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  mensagem,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF766A85),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirCaixaReal() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [widget.tema.corPrincipal, widget.tema.corSecundaria],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Caixa de hoje',
            style: TextStyle(color: Colors.white70, fontSize: 18),
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              AppFormatters.moeda(_resumoCaixa.saldo),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Entradas: '
            '${AppFormatters.moeda(_resumoCaixa.totalEntradas)}'
            ' • Saídas: '
            '${AppFormatters.moeda(_resumoCaixa.totalSaidas)}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirIndicador({
    required String titulo,
    required String valor,
    required String descricao,
    required IconData icone,
    required Color cor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6DFF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cor, size: 30),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2140),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D2140),
            ),
          ),
          const SizedBox(height: 3),
          Expanded(
            child: Text(
              descricao,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF766A85),
                fontSize: 12,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirAlerta({
    required String titulo,
    required String descricao,
    required IconData icone,
    required Color cor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6DFF0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: cor.withValues(alpha: 0.12),
            child: Icon(icone, color: cor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D2140),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  descricao,
                  style: const TextStyle(
                    color: Color(0xFF766A85),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
