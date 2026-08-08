enum StatusFilaWhatsapp {
  solicitada,
  preparada,
  naFila,
  enviando,
  aceitaProvedor,
  entregue,
  lida,
  falhou,
  cancelada,
  configuracaoPendente;

  String get dbValue {
    switch (this) {
      case StatusFilaWhatsapp.solicitada:
        return 'solicitada';
      case StatusFilaWhatsapp.preparada:
        return 'preparada';
      case StatusFilaWhatsapp.naFila:
        return 'na_fila';
      case StatusFilaWhatsapp.enviando:
        return 'enviando';
      case StatusFilaWhatsapp.aceitaProvedor:
        return 'aceita_provedor';
      case StatusFilaWhatsapp.entregue:
        return 'entregue';
      case StatusFilaWhatsapp.lida:
        return 'lida';
      case StatusFilaWhatsapp.falhou:
        return 'falhou';
      case StatusFilaWhatsapp.cancelada:
        return 'cancelada';
      case StatusFilaWhatsapp.configuracaoPendente:
        return 'configuracao_pendente';
    }
  }

  static StatusFilaWhatsapp fromDb(String value) {
    switch (value) {
      case 'solicitada':
        return StatusFilaWhatsapp.solicitada;
      case 'preparada':
        return StatusFilaWhatsapp.preparada;
      case 'na_fila':
        return StatusFilaWhatsapp.naFila;
      case 'enviando':
        return StatusFilaWhatsapp.enviando;
      case 'aceita_provedor':
        return StatusFilaWhatsapp.aceitaProvedor;
      case 'entregue':
        return StatusFilaWhatsapp.entregue;
      case 'lida':
        return StatusFilaWhatsapp.lida;
      case 'falhou':
        return StatusFilaWhatsapp.falhou;
      case 'cancelada':
        return StatusFilaWhatsapp.cancelada;
      case 'configuracao_pendente':
        return StatusFilaWhatsapp.configuracaoPendente;
      default:
        return StatusFilaWhatsapp.falhou;
    }
  }
}

class WhatsappFilaMensagem {
  final String id;
  final String businessId;
  final String? clienteId;
  final String? destinatario;
  final String? agendamentoId;
  final StatusFilaWhatsapp status;
  final String? idempotencyKey;
  final String? provider;
  final String? providerMessageId;
  final String? conversationId;
  final String? templateId;
  final String? payload;
  final int attempt;
  final String? erro;
  final int? latencia;
  final DateTime? scheduledAt;
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? failedAt;
  final DateTime? lastAttemptAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WhatsappFilaMensagem({
    required this.id,
    required this.businessId,
    this.clienteId,
    this.destinatario,
    this.agendamentoId,
    required this.status,
    this.idempotencyKey,
    this.provider,
    this.providerMessageId,
    this.conversationId,
    this.templateId,
    this.payload,
    this.attempt = 0,
    this.erro,
    this.latencia,
    this.scheduledAt,
    this.sentAt,
    this.deliveredAt,
    this.readAt,
    this.failedAt,
    this.lastAttemptAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WhatsappFilaMensagem.fromMap(Map<String, Object?> map) {
    return WhatsappFilaMensagem(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      clienteId: map['cliente_id'] as String?,
      destinatario: map['destinatario'] as String?,
      agendamentoId: map['agendamento_id'] as String?,
      status: StatusFilaWhatsapp.fromDb(map['status'] as String),
      idempotencyKey: map['idempotency_key'] as String?,
      provider: map['provider'] as String?,
      providerMessageId: map['provider_message_id'] as String?,
      conversationId: map['conversation_id'] as String?,
      templateId: map['template_id'] as String?,
      payload: map['payload'] as String?,
      attempt: (map['attempt'] as int?) ?? 0,
      erro: map['erro'] as String?,
      latencia: map['latencia'] as int?,
      scheduledAt: map['scheduled_at'] != null
          ? DateTime.parse(map['scheduled_at'] as String)
          : null,
      sentAt: map['sent_at'] != null
          ? DateTime.parse(map['sent_at'] as String)
          : null,
      deliveredAt: map['delivered_at'] != null
          ? DateTime.parse(map['delivered_at'] as String)
          : null,
      readAt: map['read_at'] != null
          ? DateTime.parse(map['read_at'] as String)
          : null,
      failedAt: map['failed_at'] != null
          ? DateTime.parse(map['failed_at'] as String)
          : null,
      lastAttemptAt: map['last_attempt_at'] != null
          ? DateTime.parse(map['last_attempt_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'business_id': businessId,
      'comercio_id': businessId, // Compatibilidade com schema v6 (NOT NULL)
      'cliente_id': clienteId,
      'destinatario': destinatario ?? '', // Evitar NOT NULL legacy se nullable
      'agendamento_id': agendamentoId,
      'status': status.dbValue,
      'idempotency_key': idempotencyKey,
      'provider': provider,
      'provider_message_id': providerMessageId,
      'conversation_id': conversationId,
      'template_id': templateId,
      'payload': payload,
      'payload_json': payload ?? '{}', // Compatibilidade
      'attempt': attempt,
      'erro': erro,
      'latencia': latencia,
      'scheduled_at': scheduledAt?.toIso8601String(),
      'sent_at': sentAt?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
      'failed_at': failedAt?.toIso8601String(),
      'last_attempt_at': lastAttemptAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'criado_em': createdAt.toIso8601String(), // Compatibilidade
      'updated_at': updatedAt.toIso8601String(),
      'atualizado_em': updatedAt.toIso8601String(), // Compatibilidade
    };
  }
}
