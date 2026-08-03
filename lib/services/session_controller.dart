import 'dart:async';
import 'package:flutter/widgets.dart';

import '../models/domain/acesso.dart';
import '../repositories/acesso_repository.dart';
import 'backend_sync_service.dart';

class SessionController extends ChangeNotifier {
  static final SessionController instance = SessionController._();

  SessionController._();

  final AcessoRepository _repository = AcessoRepository();
  UsuarioAcesso? _usuario;
  bool _carregando = true;
  Timer? _syncTimer;
  AppLifecycleListener? _lifecycleListener;

  UsuarioAcesso? get usuario => _usuario;
  bool get carregando => _carregando;
  bool get autenticado => _usuario != null;

  String? _unidadeAtiva;
  String? get unidadeAtiva => _unidadeAtiva;

  void setUnidadeAtiva(String? id) {
    if (_unidadeAtiva == id) return;
    _unidadeAtiva = id;
    notifyListeners();
  }

  Future<void> inicializar() async {
    _usuario = await _repository.restaurarSessao();
    _carregando = false;
    _configurarSyncBackground();
    notifyListeners();
  }

  void entrar(UsuarioAcesso usuario) {
    _usuario = usuario;
    _carregando = false;
    _configurarSyncBackground();
    notifyListeners();
  }

  Future<void> atualizarUsuario() async {
    final atual = _usuario;
    if (atual == null) return;
    _usuario = await _repository.carregarUsuario(atual.id);
    notifyListeners();
  }

  Future<void> sair() async {
    final atual = _usuario;
    if (atual != null) {
      await _repository.logout(atual.id);
    }
    _usuario = null;
    _syncTimer?.cancel();
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    notifyListeners();
  }

  void _configurarSyncBackground() {
    _syncTimer?.cancel();
    _lifecycleListener?.dispose();

    if (_usuario != null) {
      _iniciarTimer();
      try {
        _lifecycleListener = AppLifecycleListener(
          onResume: () {
            _sincronizarAgora();
            _iniciarTimer();
          },
          onPause: () {
            _syncTimer?.cancel();
          },
        );
      } catch (_) {
        // Ignora em testes onde o WidgetsBinding não foi inicializado
      }
    }
  }

  void _iniciarTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _sincronizarAgora();
    });
    // Call once immediately
    _sincronizarAgora();
  }

  Future<void> _sincronizarAgora() async {
    final comercioId = _usuario?.comercioId;
    if (comercioId != null) {
      try {
        await BackendSyncService().sincronizar(comercioId);
      } catch (_) {
        // Falha silenciosa no background
      }
    }
  }
}
