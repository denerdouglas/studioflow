import 'dart:async';
import 'package:flutter/widgets.dart';

import '../models/domain/acesso.dart';
import '../repositories/acesso_repository.dart';
import 'backend_sync_service.dart';
import 'backend_token_vault.dart';

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

  Object? _erroInicializacao;
  Object? get erroInicializacao => _erroInicializacao;

  String? _unidadeAtiva;
  String? get unidadeAtiva => _unidadeAtiva;

  void setUnidadeAtiva(String? id) {
    if (_unidadeAtiva == id) return;
    _unidadeAtiva = id;
    notifyListeners();
  }

  Future<void> inicializar() async {
    try {
      _usuario = await _repository.restaurarSessao();
      _carregando = false;
      _configurarSyncBackground();
      notifyListeners();
    } catch (e) {
      _erroInicializacao = e;
      _carregando = false;
      notifyListeners();
    }
  }

  void entrar(UsuarioAcesso usuario) {
    _usuario = usuario;
    _carregando = false;
    _configurarSyncBackground();
    notifyListeners();
  }

  Future<void> trocarBusiness(UsuarioAcesso destino) async {
    final atual = _usuario;
    if (atual == null) throw StateError('Sessão não autenticada.');
    final db = await _repository.database;
    final membership = await db.query(
      'business_memberships',
      columns: ['status'],
      where: 'usuario_id=? AND business_id=? AND status=?',
      whereArgs: [destino.id, destino.comercioId, 'active'],
      limit: 1,
    );
    if (membership.isEmpty) throw StateError('Unidade não autorizada.');
    final online = await db.query(
      'integracoes_configuracao',
      columns: ['sincronizacao_ativa'],
      where: 'comercio_id=? AND sincronizacao_ativa=1',
      whereArgs: [destino.comercioId],
      limit: 1,
    );
    if (online.isNotEmpty &&
        await const SecureBackendTokenVault().read(destino.comercioId) ==
            null) {
      throw StateError('Entre online nesta unidade antes de alternar.');
    }
    _syncTimer?.cancel();
    _unidadeAtiva = null;
    _usuario = await _repository.iniciarSessao(
      usuario: destino,
      permanecerConectado: true,
    );
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

  @visibleForTesting
  void cancelarSincronizacaoEmTeste() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
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
