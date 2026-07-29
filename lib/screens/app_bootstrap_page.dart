import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/studioflow_theme.dart';
import '../models/domain/acesso.dart';
import '../services/auto_sync_controller.dart';
import '../services/session_controller.dart';
import 'acesso_page.dart';
import 'dashboard_page.dart';

class AppBootstrapPage extends StatefulWidget {
  const AppBootstrapPage({super.key});

  @override
  State<AppBootstrapPage> createState() => _AppBootstrapPageState();
}

class _AppBootstrapPageState extends State<AppBootstrapPage> {
  String? _ultimoComercioId;
  @override
  void initState() {
    super.initState();
    SessionController.instance.inicializar();
  }

  void _atualizarAutoSync(UsuarioAcesso? usuario) {
    final comercioId = usuario?.comercioId;
    if (_ultimoComercioId == comercioId) return;
    _ultimoComercioId = comercioId;
    if (comercioId == null) {
      unawaited(AutoSyncController.instance.parar());
    } else {
      unawaited(AutoSyncController.instance.iniciar(comercioId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SessionController.instance,
      builder: (context, _) {
        final sessao = SessionController.instance;
        if (sessao.carregando) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final usuario = sessao.usuario;
        _atualizarAutoSync(usuario);
        if (usuario == null) return const AcessoPage();
        return DashboardPage(
          nomeResponsavel: usuario.nome,
          nomeNegocio: usuario.nomeExibicao,
          tipoNegocio: usuario.funcao.nome,
          tema: StudioFlowThemeData.sugeridoParaCategoria(
            usuario.tipoEstabelecimento.nome,
          ),
        );
      },
    );
  }
}
