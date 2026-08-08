import 'package:flutter/material.dart';
import '../core/helpers/app_formatters.dart';
import '../core/theme/studioflow_theme.dart';
import '../models/domain/acesso.dart';
import '../repositories/modalidades_repository.dart';
import '../services/session_controller.dart';
import '../services/dashboard_summary_service.dart';
import '../widgets/shared/premium_card.dart';
import '../registry/widget_registry.dart';
import '../registry/dashboard_configuration.dart';
import 'ia_local_page.dart';
import 'modalidades_page.dart';
import 'configuracoes_page.dart';

class HomePremiumPage extends StatefulWidget {
  final String nomeResponsavel;
  final String nomeNegocio;
  final StudioFlowTheme tema;

  const HomePremiumPage({
    super.key,
    required this.nomeResponsavel,
    required this.nomeNegocio,
    required this.tema,
  });

  @override
  State<HomePremiumPage> createState() => _HomePremiumPageState();
}

class _HomePremiumPageState extends State<HomePremiumPage> {
  final DashboardSummaryService _summaryService = DashboardSummaryService();
  final ModalidadesRepository _modalidadesRepository = ModalidadesRepository();
  final WidgetRegistry _registry = WidgetRegistry();
  final DashboardConfiguration _config = DashboardConfiguration.defaultLayout();

  DashboardSummary? _summary;
  List<ModalidadeRegistro> _modalidades = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _registerWidgets();
    _loadData();
  }

  void _registerWidgets() {
    _registry.register('ia_panel', (context, data) => _buildIaPanel());
    _registry.register('modalidades', (context, data) {
      if (_modalidades.isEmpty) return const SizedBox.shrink();
      return Column(
        children: [const SizedBox(height: 20), _buildModalidades()],
      );
    });
    _registry.register(
      'caixa',
      (context, data) => Column(
        children: [
          const SizedBox(height: 24),
          _buildSectionTitle('Caixa'),
          const SizedBox(height: 12),
          _buildCaixa(),
        ],
      ),
    );
    _registry.register(
      'agenda',
      (context, data) => Column(
        children: [
          const SizedBox(height: 24),
          _buildSectionTitle('Agenda de Hoje'),
          const SizedBox(height: 12),
          _buildAgenda(),
        ],
      ),
    );
    _registry.register(
      'estoque_alerts',
      (context, data) => Column(
        children: [
          const SizedBox(height: 24),
          _buildSectionTitle('Alertas de Estoque'),
          const SizedBox(height: 12),
          _buildEstoqueAlerts(),
        ],
      ),
    );
    _registry.register(
      'indicadores',
      (context, data) => Column(
        children: [
          const SizedBox(height: 24),
          _buildSectionTitle('Indicadores'),
          const SizedBox(height: 12),
          _buildIndicadores(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final summary = await _summaryService.loadSummary(DateTime.now());
      List<ModalidadeRegistro> modalidades = [];
      try {
        modalidades = await _modalidadesRepository.listar(
          incluirInativas: false,
        );
      } catch (e, st) {
        debugPrint('Erro ao carregar modalidades na Home: $e\n$st');
      }
      
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _modalidades = modalidades.where((item) => item.exibirHome).toList();
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('Erro ao carregar painel inteligente: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = 'Ocorreu um erro ao carregar o painel inteligente.';
        _isLoading = false;
      });
    }
  }

  String get _saudacao {
    final hora = DateTime.now().hour;
    if (hora < 12) return 'Bom dia';
    if (hora < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.tema.fundo,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: widget.tema.corPrincipal,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildAppBar(),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(child: _buildErrorState())
            else
              _buildContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: widget.tema.fundo,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 20,
      expandedHeight: 80,
      toolbarHeight: 70,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$_saudacao, ${widget.nomeResponsavel}! ${widget.tema.emoji}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D2140),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.nomeNegocio,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Color(0xFF766A85)),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Pesquisa Global (Em breve)',
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Pesquisa Global estará disponível em breve!'),
              ),
            );
          },
          icon: Icon(Icons.search, color: widget.tema.corPrincipal),
        ),
        IconButton(
          tooltip: 'Atualizar',
          onPressed: _loadData,
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
          tooltip: 'Notificações',
          onPressed: () {
            final usuario = SessionController.instance.usuario!;
            if (!usuario.pode(ModuloPermissao.configuracoes)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Acesso não permitido.')),
              );
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ConfiguracoesPage()),
            );
          },
          icon: Icon(Icons.notifications_none, color: widget.tema.corPrincipal),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Color(0xFFD64D64)),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Color(0xFF2D2140)),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final type = _config.layout[index];
          return _registry.buildWidget(context, type);
        }, childCount: _config.layout.length),
      ),
    );
  }

  Widget _buildModalidades() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Áreas do estabelecimento',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          if (SessionController.instance.usuario!.pode(
            ModuloPermissao.configuracoes,
          ))
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ModalidadesPage()),
              ).then((_) => _loadData()),
              child: const Text('Organizar'),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _modalidades
            .map(
              (item) => Chip(
                avatar: Icon(
                  item.favorita ? Icons.star : Icons.category_outlined,
                  size: 18,
                ),
                label: Text(item.nome),
              ),
            )
            .toList(),
      ),
    ],
  );
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF2D2140),
      ),
    );
  }

  Widget _buildIaPanel() {
    final resumo = _summary!;
    final agendamentos = resumo.agendamentosValidos.length;
    final receita = AppFormatters.moeda(resumo.receitaPrevista);
    final estoqueCount = resumo.produtosBaixoEstoque.length;

    String mensagem = 'Bom dia! ';
    if (agendamentos > 0) {
      mensagem +=
          'Você tem $agendamentos atendimento(s) planejado(s) para hoje, com receita prevista de $receita. ';
    } else {
      mensagem +=
          'Sua agenda está livre hoje. Que tal aproveitar para engajar seus clientes? ';
    }

    if (estoqueCount > 0) {
      mensagem +=
          'Atenção: $estoqueCount produto(s) no estoque estão abaixo do limite mínimo.';
    }

    return PremiumCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: widget.tema.corPrincipal,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'IA StudioFlow',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF2D2140),
                  ),
                ),
                const SizedBox(height: 6),
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

  Widget _buildCaixa() {
    final caixa = _summary!.resumoCaixa;
    return PremiumCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [widget.tema.corPrincipal, widget.tema.corSecundaria],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Saldo Atual',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ),
                Text(
                  AppFormatters.moeda(caixa.saldo),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: _buildMetricMini(
                    title: 'Entradas',
                    value: AppFormatters.moeda(caixa.totalEntradas),
                    icon: Icons.arrow_downward,
                    color: const Color(0xFF15996B),
                  ),
                ),
                Container(width: 1, height: 40, color: Colors.grey.shade200),
                Expanded(
                  child: _buildMetricMini(
                    title: 'Saídas',
                    value: AppFormatters.moeda(caixa.totalSaidas),
                    icon: Icons.arrow_upward,
                    color: const Color(0xFFD64D64),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricMini({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF766A85),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D2140),
          ),
        ),
      ],
    );
  }

  Widget _buildAgenda() {
    final validos = _summary!.agendamentosValidos;
    if (validos.isEmpty) {
      return const PremiumCard(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Nenhum agendamento para hoje.',
            style: TextStyle(color: Color(0xFF766A85)),
          ),
        ),
      );
    }

    return Column(
      children: validos
          .take(3)
          .map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: PremiumCard(
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: widget.tema.corPrincipal.withValues(
                        alpha: 0.1,
                      ),
                      child: Text(
                        a.clienteNome.isNotEmpty
                            ? a.clienteNome[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: widget.tema.corPrincipal,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.clienteNome,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${AppFormatters.hora(a.inicio)} - ${a.servicoNome}',
                            style: const TextStyle(
                              color: Color(0xFF766A85),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.chat, color: Color(0xFF15996B)),
                      tooltip: 'WhatsApp',
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildEstoqueAlerts() {
    final baixos = _summary!.produtosBaixoEstoque;
    if (baixos.isEmpty) {
      return const PremiumCard(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Estoque regularizado.',
            style: TextStyle(color: Color(0xFF766A85)),
          ),
        ),
      );
    }

    return Column(
      children: baixos
          .take(3)
          .map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: PremiumCard(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD64D64).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFD64D64),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.nome,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Apenas ${p.quantidadeAtual} ${p.unidade} (Mín: ${p.estoqueMinimo})',
                            style: const TextStyle(
                              color: Color(0xFFD64D64),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildIndicadores() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.1,
      children: [
        _buildIndicadorCard(
          'Atendimentos',
          _summary!.agendamentosValidos.length.toString(),
          Icons.people_alt,
          widget.tema.corPrincipal,
        ),
        _buildIndicadorCard(
          'Receita Prevista',
          AppFormatters.moeda(_summary!.receitaPrevista),
          Icons.trending_up,
          const Color(0xFF15996B),
        ),
        _buildIndicadorCard(
          'Alertas Estoque',
          _summary!.produtosBaixoEstoque.length.toString(),
          Icons.inventory_2,
          const Color(0xFFD64D64),
        ),
        _buildIndicadorCard(
          'Receita Realizada',
          AppFormatters.moeda(_summary!.resumoCaixa.totalEntradas),
          Icons.account_balance_wallet,
          const Color(0xFF3078C5),
        ),
      ],
    );
  }

  Widget _buildIndicadorCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2140),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF766A85),
            ),
          ),
        ],
      ),
    );
  }
}
