abstract interface class MessagingProvider {
  bool get configurado;
  Future<void> enviarMensagem({required String destino, required String texto});
}

abstract interface class AIProvider {
  bool get online;
  Future<String> responder({
    required String comercioId,
    required String conversaId,
    required String mensagem,
  });
}

abstract interface class PaymentProvider {
  bool get confirmacaoAutomaticaDisponivel;
  Future<String?> criarLink({
    required String referencia,
    required double valor,
    required String descricao,
  });
  Future<bool?> consultarConfirmacao(String referencia);
}

abstract interface class SchedulingProvider {
  Future<List<DateTime>> horariosDisponiveis({
    required String comercioId,
    required String profissionalId,
    required DateTime data,
    required int duracaoMinutos,
  });
}

class IntegracaoNaoConfigurada implements Exception {
  final String mensagem;
  const IntegracaoNaoConfigurada(this.mensagem);
  @override
  String toString() => mensagem;
}

class WhatsAppBackendProvider implements MessagingProvider {
  @override
  bool get configurado => false;

  @override
  Future<void> enviarMensagem({
    required String destino,
    required String texto,
  }) => throw const IntegracaoNaoConfigurada(
    'WhatsApp oficial ainda não configurado. Use o simulador ou o compartilhamento manual.',
  );
}

class OnlineAIBackendProvider implements AIProvider {
  @override
  bool get online => false;

  @override
  Future<String> responder({
    required String comercioId,
    required String conversaId,
    required String mensagem,
  }) => throw const IntegracaoNaoConfigurada(
    'IA online ainda não configurada. Nenhuma chave está armazenada no aplicativo.',
  );
}

class PagamentoBackendProvider implements PaymentProvider {
  @override
  bool get confirmacaoAutomaticaDisponivel => false;

  @override
  Future<String?> criarLink({
    required String referencia,
    required double valor,
    required String descricao,
  }) => throw const IntegracaoNaoConfigurada(
    'Provedor de pagamento ainda não configurado.',
  );

  @override
  Future<bool?> consultarConfirmacao(String referencia) async => null;
}
