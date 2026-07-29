class HorarioProfissional {
  final String id;
  final String profissionalId;
  final String profissionalNome;
  final int diaSemana;
  final String inicio;
  final String fim;
  final String? intervaloInicio;
  final String? intervaloFim;
  final bool ativo;

  const HorarioProfissional({
    required this.id,
    required this.profissionalId,
    this.profissionalNome = '',
    required this.diaSemana,
    required this.inicio,
    required this.fim,
    this.intervaloInicio,
    this.intervaloFim,
    this.ativo = true,
  });
}

class BloqueioAgenda {
  final String id;
  final String? profissionalId;
  final String profissionalNome;
  final DateTime inicio;
  final DateTime fim;
  final String tipo;
  final String motivo;

  const BloqueioAgenda({
    required this.id,
    this.profissionalId,
    this.profissionalNome = '',
    required this.inicio,
    required this.fim,
    required this.tipo,
    this.motivo = '',
  });
}

class EventoAgendamento {
  final String acao;
  final String? statusAnterior;
  final String? statusNovo;
  final String detalhes;
  final DateTime data;
  final String usuarioId;

  const EventoAgendamento({
    required this.acao,
    this.statusAnterior,
    this.statusNovo,
    this.detalhes = '',
    required this.data,
    required this.usuarioId,
  });
}

class ConfiguracaoIaSalao {
  final String comercioId;
  final String nomeIa;
  final String mensagemApresentacao;
  final String estiloLinguagem;
  final String horarioInicio;
  final String horarioFim;
  final String politicaCancelamento;
  final String instrucaoTransferencia;
  final String transferirPalavras;
  final bool ativo;

  const ConfiguracaoIaSalao({
    required this.comercioId,
    required this.nomeIa,
    required this.mensagemApresentacao,
    required this.estiloLinguagem,
    required this.horarioInicio,
    required this.horarioFim,
    required this.politicaCancelamento,
    required this.instrucaoTransferencia,
    required this.transferirPalavras,
    this.ativo = true,
  });
}

class FaqIa {
  final String id;
  final String pergunta;
  final String resposta;
  final bool ativo;

  const FaqIa({
    required this.id,
    required this.pergunta,
    required this.resposta,
    this.ativo = true,
  });
}

class MensagemSimulada {
  final String id;
  final String remetente;
  final String conteudo;
  final DateTime criadaEm;

  const MensagemSimulada({
    required this.id,
    required this.remetente,
    required this.conteudo,
    required this.criadaEm,
  });
}

class ConfiguracaoPagamento {
  final String comercioId;
  final String chavePix;
  final String tipoChave;
  final String nomeRecebedor;
  final String cidadeRecebedor;
  final String mensagemCobranca;
  final String tipoSinal;
  final double valorSinal;
  final int prazoHoras;
  final String politicaCancelamento;
  final String linkPagamentoBase;
  final String banco;
  final String observacoes;
  final Set<String> formasAceitas;
  final double valorSinalFixo;
  final double percentualSinal;

  const ConfiguracaoPagamento({
    required this.comercioId,
    required this.chavePix,
    required this.tipoChave,
    required this.nomeRecebedor,
    required this.cidadeRecebedor,
    required this.mensagemCobranca,
    required this.tipoSinal,
    required this.valorSinal,
    required this.prazoHoras,
    required this.politicaCancelamento,
    this.linkPagamentoBase = '',
    this.banco = '',
    this.observacoes = '',
    this.formasAceitas = const {'pix', 'dinheiro'},
    this.valorSinalFixo = 0,
    this.percentualSinal = 0,
  });

  double calcularSinal(double total) => tipoSinal == 'percentual'
      ? total * valorSinal / 100
      : valorSinal.clamp(0, total);
}

class Cobranca {
  final String id;
  final String? agendamentoId;
  final String? clienteId;
  final double valor;
  final String descricao;
  final String forma;
  final String pixCopiaCola;
  final String linkPagamento;
  final String status;
  final DateTime criadaEm;
  final DateTime? confirmadaEm;

  const Cobranca({
    required this.id,
    this.agendamentoId,
    this.clienteId,
    required this.valor,
    required this.descricao,
    required this.forma,
    this.pixCopiaCola = '',
    this.linkPagamento = '',
    required this.status,
    required this.criadaEm,
    this.confirmadaEm,
  });
}

class ResumoCliente360 {
  final String clienteId;
  final String nome;
  final String whatsapp;
  final String email;
  final DateTime? aniversario;
  final String profissionalPreferido;
  final int agendamentos;
  final int faltas;
  final int cancelamentos;
  final double recebidoServicos;
  final double comprasProdutos;
  final List<Map<String, Object?>> historicoAgenda;
  final List<Map<String, Object?>> historicoCompras;

  const ResumoCliente360({
    required this.clienteId,
    required this.nome,
    required this.whatsapp,
    required this.email,
    this.aniversario,
    required this.profissionalPreferido,
    required this.agendamentos,
    required this.faltas,
    required this.cancelamentos,
    required this.recebidoServicos,
    required this.comprasProdutos,
    required this.historicoAgenda,
    required this.historicoCompras,
  });
}
