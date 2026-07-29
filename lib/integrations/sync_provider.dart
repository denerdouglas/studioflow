import '../models/domain/infraestrutura.dart';

abstract interface class SyncProvider {
  String get nome;
  bool get configurado;

  Future<void> enviar(List<OperacaoSincronizacao> operacoes);
}

class BackendNaoConfiguradoProvider implements SyncProvider {
  const BackendNaoConfiguradoProvider();

  @override
  String get nome => 'Backend não configurado';

  @override
  bool get configurado => false;

  @override
  Future<void> enviar(List<OperacaoSincronizacao> operacoes) {
    throw StateError(
      'A sincronização online depende de um backend seguro e credenciais externas.',
    );
  }
}

abstract interface class AssinaturaProvider {
  bool get configurado;

  Future<String> consultarPlano(String comercioId);
}

abstract interface class PainelAdministrativoProvider {
  bool get configurado;
}
