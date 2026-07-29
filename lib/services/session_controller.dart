import 'package:flutter/foundation.dart';

import '../models/domain/acesso.dart';
import '../repositories/acesso_repository.dart';

class SessionController extends ChangeNotifier {
  static final SessionController instance = SessionController._();

  SessionController._();

  final AcessoRepository _repository = AcessoRepository();
  UsuarioAcesso? _usuario;
  bool _carregando = true;

  UsuarioAcesso? get usuario => _usuario;
  bool get carregando => _carregando;
  bool get autenticado => _usuario != null;

  Future<void> inicializar() async {
    _usuario = await _repository.restaurarSessao();
    _carregando = false;
    notifyListeners();
  }

  void entrar(UsuarioAcesso usuario) {
    _usuario = usuario;
    _carregando = false;
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
    notifyListeners();
  }
}
