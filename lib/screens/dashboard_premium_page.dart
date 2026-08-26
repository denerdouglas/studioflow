import 'package:flutter/material.dart';

import '../core/theme/studioflow_theme.dart';
import '../models/domain/acesso.dart';
import '../models/domain/business_profile.dart';
import '../services/session_controller.dart';
import 'agenda_page.dart';
import 'home_premium_page.dart';
import 'mais_premium_page.dart';
import 'loja_salao_page.dart';

class DashboardPremiumPage extends StatefulWidget {
  final String nomeResponsavel;
  final String nomeNegocio;
  final String tipoNegocio;
  final StudioFlowTheme tema;

  const DashboardPremiumPage({
    super.key,
    required this.nomeResponsavel,
    required this.nomeNegocio,
    required this.tipoNegocio,
    required this.tema,
  });

  @override
  State<DashboardPremiumPage> createState() => _DashboardPremiumPageState();
}

class _DashboardPremiumPageState extends State<DashboardPremiumPage> {
  int _paginaSelecionada = 0;

  void _mudarPagina(int indice) {
    setState(() {
      _paginaSelecionada = indice;
    });
  }

  @override
  Widget build(BuildContext context) {
    final usuario = SessionController.instance.usuario!;
    final exibeAgenda = usuario.moduloAtivo(BusinessModule.agenda);
    final exibeLoja = usuario.moduloAtivo(BusinessModule.loja);

    final paginas = <Widget>[
      HomePremiumPage(
        nomeResponsavel: widget.nomeResponsavel,
        nomeNegocio: widget.nomeNegocio,
        tema: widget.tema,
      ),
      if (exibeAgenda)
        usuario.pode(ModuloPermissao.agenda)
            ? const AgendaPage()
            : const Center(child: Text('Acesso não permitido.')),
      if (exibeLoja)
        usuario.pode(ModuloPermissao.lojaSalao)
            ? const LojaSalaoPage()
            : const Center(child: Text('Acesso não permitido.')),
      MaisPremiumPage(tema: widget.tema),
    ];

    final destinations = <NavigationDestination>[
      if (exibeLoja)
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Início',
        ),
      if (exibeAgenda)
        const NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month),
          label: 'Agenda',
        ),
      const NavigationDestination(
        icon: Icon(Icons.storefront_outlined),
        selectedIcon: Icon(Icons.storefront),
        label: 'Loja',
      ),
      const NavigationDestination(
        icon: Icon(Icons.menu),
        selectedIcon: Icon(Icons.menu_open),
        label: 'Mais',
      ),
    ];

    return Scaffold(
      backgroundColor: widget.tema.fundo,
      body: IndexedStack(index: _paginaSelecionada, children: paginas),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _paginaSelecionada,
        backgroundColor: Colors.white,
        indicatorColor: widget.tema.corPrincipal.withValues(alpha: 0.14),
        onDestinationSelected: _mudarPagina,
        destinations: destinations,
      ),
    );
  }
}
