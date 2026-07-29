import '../../models/domain/acesso.dart';
import '../../services/session_controller.dart';

abstract final class AutorizacaoService {
  static UsuarioAcesso exigir(AcaoPermissao acao) {
    final usuario = SessionController.instance.usuario;
    if (usuario == null) {
      throw StateError('Entre em sua conta para continuar.');
    }
    if (!usuario.podeAcao(acao)) {
      throw StateError(
        'Você não possui permissão para ${acao.nome.toLowerCase()}.',
      );
    }
    return usuario;
  }

  static bool permite(AcaoPermissao acao) {
    return SessionController.instance.usuario?.podeAcao(acao) ?? false;
  }
}
