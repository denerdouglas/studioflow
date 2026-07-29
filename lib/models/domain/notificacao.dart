enum CanalNotificacao { aplicativo, whatsapp, email, push }

enum TipoNotificacao {
  resumoDiario,
  confirmacaoAgendamento,
  lembreteAgendamento,
  cancelamentoAgendamento,
  estoqueBaixo,
  produtoVencendo,
  manutencao,
  contaVencendo,
  meta,
  aniversarioCliente,
  clienteSemRetorno,
  comissao,
  alertaIa,
  campanha,
  outro,
}

enum StatusNotificacao {
  pendente,
  agendada,
  enviada,
  entregue,
  lida,
  falhou,
  cancelada,
}

class NotificacaoStudioFlow {
  final String id;
  final String negocioId;
  final TipoNotificacao tipo;

  final String titulo;
  final String mensagem;

  final List<CanalNotificacao> canais;
  final StatusNotificacao status;

  final DateTime dataCriacao;
  final DateTime? dataAgendada;
  final DateTime? dataEnvio;
  final DateTime? dataLeitura;

  final String? usuarioDestinoId;
  final String? clienteDestinoId;
  final String? profissionalDestinoId;
  final String? whatsappDestino;

  final String? referenciaId;
  final String? acao;
  final Map<String, String> dadosExtras;

  const NotificacaoStudioFlow({
    required this.id,
    required this.negocioId,
    required this.tipo,
    required this.titulo,
    required this.mensagem,
    this.canais = const [CanalNotificacao.aplicativo],
    this.status = StatusNotificacao.pendente,
    required this.dataCriacao,
    this.dataAgendada,
    this.dataEnvio,
    this.dataLeitura,
    this.usuarioDestinoId,
    this.clienteDestinoId,
    this.profissionalDestinoId,
    this.whatsappDestino,
    this.referenciaId,
    this.acao,
    this.dadosExtras = const {},
  });

  bool get foiEnviada {
    return status == StatusNotificacao.enviada ||
        status == StatusNotificacao.entregue ||
        status == StatusNotificacao.lida;
  }

  bool get foiLida {
    return status == StatusNotificacao.lida;
  }

  bool get estaAtrasada {
    if (dataAgendada == null || foiEnviada) {
      return false;
    }

    return dataAgendada!.isBefore(DateTime.now());
  }

  NotificacaoStudioFlow copiarCom({
    StatusNotificacao? status,
    DateTime? dataAgendada,
    DateTime? dataEnvio,
    DateTime? dataLeitura,
  }) {
    return NotificacaoStudioFlow(
      id: id,
      negocioId: negocioId,
      tipo: tipo,
      titulo: titulo,
      mensagem: mensagem,
      canais: canais,
      status: status ?? this.status,
      dataCriacao: dataCriacao,
      dataAgendada: dataAgendada ?? this.dataAgendada,
      dataEnvio: dataEnvio ?? this.dataEnvio,
      dataLeitura: dataLeitura ?? this.dataLeitura,
      usuarioDestinoId: usuarioDestinoId,
      clienteDestinoId: clienteDestinoId,
      profissionalDestinoId: profissionalDestinoId,
      whatsappDestino: whatsappDestino,
      referenciaId: referenciaId,
      acao: acao,
      dadosExtras: dadosExtras,
    );
  }
}

class ConfiguracaoResumoDiario {
  final String negocioId;

  final bool ativo;
  final int hora;
  final int minuto;

  final List<int> diasSemana;
  final List<CanalNotificacao> canais;

  final bool incluirAgenda;
  final bool incluirFaturamentoPrevisto;
  final bool incluirCaixa;
  final bool incluirEstoque;
  final bool incluirManutencoes;
  final bool incluirMetas;
  final bool incluirAniversarios;
  final bool incluirClientesSemRetorno;
  final bool incluirDicaIa;

  final List<String> usuariosDestinatariosIds;
  final List<String> whatsappsDestinatarios;

  const ConfiguracaoResumoDiario({
    required this.negocioId,
    this.ativo = true,
    this.hora = 7,
    this.minuto = 0,
    this.diasSemana = const [
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
      DateTime.saturday,
    ],
    this.canais = const [
      CanalNotificacao.aplicativo,
      CanalNotificacao.whatsapp,
    ],
    this.incluirAgenda = true,
    this.incluirFaturamentoPrevisto = true,
    this.incluirCaixa = true,
    this.incluirEstoque = true,
    this.incluirManutencoes = true,
    this.incluirMetas = true,
    this.incluirAniversarios = true,
    this.incluirClientesSemRetorno = true,
    this.incluirDicaIa = true,
    this.usuariosDestinatariosIds = const [],
    this.whatsappsDestinatarios = const [],
  });

  bool deveEnviarHoje(DateTime data) {
    return ativo && diasSemana.contains(data.weekday);
  }

  DateTime proximoHorario(DateTime agora) {
    DateTime horario = DateTime(
      agora.year,
      agora.month,
      agora.day,
      hora,
      minuto,
    );

    if (horario.isBefore(agora)) {
      horario = horario.add(const Duration(days: 1));
    }

    while (!diasSemana.contains(horario.weekday)) {
      horario = horario.add(const Duration(days: 1));
    }

    return horario;
  }
}

class ResumoInteligenteDiario {
  final String negocioId;
  final String nomeResponsavel;
  final String nomeNegocio;

  final DateTime dataReferencia;

  final int totalAgendamentos;
  final int totalConfirmados;
  final int horariosLivres;

  final double faturamentoPrevisto;
  final double caixaAtual;
  final double metaMensal;
  final double faturamentoMes;

  final List<String> alertasEstoque;
  final List<String> alertasManutencao;
  final List<String> aniversariantes;
  final List<String> clientesSemRetorno;

  final String? primeiroAtendimento;
  final String? dicaIa;

  const ResumoInteligenteDiario({
    required this.negocioId,
    required this.nomeResponsavel,
    required this.nomeNegocio,
    required this.dataReferencia,
    this.totalAgendamentos = 0,
    this.totalConfirmados = 0,
    this.horariosLivres = 0,
    this.faturamentoPrevisto = 0,
    this.caixaAtual = 0,
    this.metaMensal = 0,
    this.faturamentoMes = 0,
    this.alertasEstoque = const [],
    this.alertasManutencao = const [],
    this.aniversariantes = const [],
    this.clientesSemRetorno = const [],
    this.primeiroAtendimento,
    this.dicaIa,
  });

  double get percentualMeta {
    if (metaMensal <= 0) {
      return 0;
    }

    return (faturamentoMes / metaMensal) * 100;
  }

  double get valorRestanteMeta {
    final restante = metaMensal - faturamentoMes;

    return restante > 0 ? restante : 0;
  }

  String gerarMensagem() {
    final buffer = StringBuffer();

    buffer.writeln('Bom dia, $nomeResponsavel! ✨');

    buffer.writeln();
    buffer.writeln(
      '📅 Hoje você tem $totalAgendamentos agendamentos, sendo $totalConfirmados confirmados.',
    );

    buffer.writeln(
      '💰 Faturamento previsto: R\$ ${faturamentoPrevisto.toStringAsFixed(2)}.',
    );

    buffer.writeln('💵 Caixa atual: R\$ ${caixaAtual.toStringAsFixed(2)}.');

    if (primeiroAtendimento != null) {
      buffer.writeln('⏰ Primeiro atendimento: $primeiroAtendimento.');
    }

    if (horariosLivres > 0) {
      buffer.writeln('🕒 Horários livres hoje: $horariosLivres.');
    }

    if (metaMensal > 0) {
      buffer.writeln(
        '🎯 Meta mensal: ${percentualMeta.toStringAsFixed(1)}% atingida.',
      );

      if (valorRestanteMeta > 0) {
        buffer.writeln(
          'Faltam R\$ ${valorRestanteMeta.toStringAsFixed(2)} para alcançar a meta.',
        );
      }
    }

    if (alertasEstoque.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('📦 Estoque:');

      for (final alerta in alertasEstoque) {
        buffer.writeln('• $alerta');
      }
    }

    if (alertasManutencao.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('🔧 Manutenção:');

      for (final alerta in alertasManutencao) {
        buffer.writeln('• $alerta');
      }
    }

    if (aniversariantes.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('🎂 Aniversariantes: ${aniversariantes.join(', ')}.');
    }

    if (clientesSemRetorno.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(
        '📣 ${clientesSemRetorno.length} clientes estão há bastante tempo sem retornar.',
      );
    }

    if (dicaIa != null && dicaIa!.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('🤖 Dica StudioFlow IA:');
      buffer.writeln(dicaIa);
    }

    return buffer.toString().trim();
  }
}

class ModeloMensagemWhatsApp {
  final String id;
  final String nome;
  final TipoNotificacao tipo;

  final String texto;
  final bool ativo;

  final List<String> variaveis;

  const ModeloMensagemWhatsApp({
    required this.id,
    required this.nome,
    required this.tipo,
    required this.texto,
    this.ativo = true,
    this.variaveis = const [],
  });

  String preencher(Map<String, String> valores) {
    String mensagemFinal = texto;

    for (final entrada in valores.entries) {
      mensagemFinal = mensagemFinal.replaceAll(
        '{{${entrada.key}}}',
        entrada.value,
      );
    }

    return mensagemFinal;
  }
}

class MensagemWhatsApp {
  final String id;
  final String negocioId;

  final String numeroDestino;
  final String mensagem;

  final TipoNotificacao tipo;
  final StatusNotificacao status;

  final DateTime dataCriacao;
  final DateTime? dataAgendada;
  final DateTime? dataEnvio;

  final String? clienteId;
  final String? profissionalId;
  final String? agendamentoId;

  final String? erro;

  const MensagemWhatsApp({
    required this.id,
    required this.negocioId,
    required this.numeroDestino,
    required this.mensagem,
    required this.tipo,
    this.status = StatusNotificacao.pendente,
    required this.dataCriacao,
    this.dataAgendada,
    this.dataEnvio,
    this.clienteId,
    this.profissionalId,
    this.agendamentoId,
    this.erro,
  });

  bool get podeEnviar {
    return status == StatusNotificacao.pendente ||
        status == StatusNotificacao.agendada;
  }
}
