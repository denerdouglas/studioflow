import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/studioflow_theme.dart';
import '../models/domain/acesso.dart';
import '../services/auto_sync_controller.dart';
import '../services/session_controller.dart';
import '../database/database_service.dart';
import 'acesso_page.dart';
import 'dashboard_premium_page.dart';

enum BootstrapState { inicializando, pronto, erro }

class AppBootstrapPage extends StatefulWidget {
  const AppBootstrapPage({super.key});

  @override
  State<AppBootstrapPage> createState() => _AppBootstrapPageState();
}

class _AppBootstrapPageState extends State<AppBootstrapPage> {
  String? _ultimoComercioId;
  BootstrapState _state = BootstrapState.inicializando;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _iniciarApp();
  }

  Future<void> _iniciarApp() async {
    try {
      if (mounted) {
        setState(() {
          _state = BootstrapState.inicializando;
          _error = null;
        });
      }

      // Forçar inicialização do banco com timeout
      await DatabaseService.instance.database.timeout(
        const Duration(seconds: 15),
      );

      // Inicializar sessão
      await SessionController.instance.inicializar().timeout(
        const Duration(seconds: 15),
      );

      final erroSessao = SessionController.instance.erroInicializacao;
      if (erroSessao != null) {
        throw erroSessao;
      }

      if (mounted) {
        setState(() {
          _state = BootstrapState.pronto;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = BootstrapState.erro;
          _error = e;
        });
      }
    }
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
    if (_state == BootstrapState.erro) {
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
                  'Erro ao iniciar o aplicativo.',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _error.toString(),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _iniciarApp,
                  child: const Text('Tentar Novamente'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_state == BootstrapState.inicializando) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Iniciando o StudioFlow...'),
            ],
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: SessionController.instance,
      builder: (context, _) {
        final sessao = SessionController.instance;
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
