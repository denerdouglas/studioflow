import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/studioflow_theme.dart';
import '../models/domain/acesso.dart';
import '../services/auto_sync_controller.dart';
import '../services/session_controller.dart';
import 'acesso_page.dart';
import 'dashboard_premium_page.dart';

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
        if (sessao.erroInicializacao != null) {
          return Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(
                      'Erro ao inicializar o banco de dados.',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      sessao.erroInicializacao.toString(),
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (sessao.carregando) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final usuario = sessao.usuario;
        _atualizarAutoSync(usuario);
        if (usuario == null) return const AcessoPage();
        return DashboardPremiumPage(
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
