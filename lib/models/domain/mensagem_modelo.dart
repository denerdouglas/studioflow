class ModeloMensagem {
  final String id;
  final String comercioId;
  final String chave;
  final String nome;
  final String texto;
  final String textoPadrao;
  final bool ativo;

  const ModeloMensagem({
    required this.id,
    required this.comercioId,
    required this.chave,
    required this.nome,
    required this.texto,
    required this.textoPadrao,
    required this.ativo,
  });
}

class ItemResumoMensagem {
  final String nome;
  final int quantidade;
  final double valorUnitario;
  final double desconto;
  final String profissional;

  const ItemResumoMensagem({
    required this.nome,
    this.quantidade = 1,
    required this.valorUnitario,
    this.desconto = 0,
    this.profissional = '',
  });

  double get subtotal => (quantidade * valorUnitario - desconto)
      .clamp(0, double.infinity)
      .toDouble();
}

class DadosMensagem {
  final String cliente;
  final String salao;
  final String data;
  final String hora;
  final String profissional;
  final String servico;
  final List<ItemResumoMensagem> servicos;
  final List<ItemResumoMensagem> produtos;
  final double valorPago;
  final String formaPagamento;
  final double valorSinal;
  final String pix;
  final String nomeRecebedor;
  final String banco;
  final String endereco;
  final String pontoReferencia;
  final String linkRota;
  final String telefoneSalao;

  const DadosMensagem({
    this.cliente = '',
    this.salao = '',
    this.data = '',
    this.hora = '',
    this.profissional = '',
    this.servico = '',
    this.servicos = const [],
    this.produtos = const [],
    this.valorPago = 0,
    this.formaPagamento = '',
    this.valorSinal = 0,
    this.pix = '',
    this.nomeRecebedor = '',
    this.banco = '',
    this.endereco = '',
    this.pontoReferencia = '',
    this.linkRota = '',
    this.telefoneSalao = '',
  });

  double get totalServicos =>
      servicos.fold(0, (total, item) => total + item.subtotal);
  double get totalProdutos =>
      produtos.fold(0, (total, item) => total + item.subtotal);
  double get totalGeral => totalServicos + totalProdutos;
  double get valorPendente =>
      (totalGeral - valorPago).clamp(0, double.infinity).toDouble();
}

const modelosMensagensPadrao = <String, ({String nome, String texto})>{
  'confirmacao_agendamento': (
    nome: 'Confirmação de agendamento',
    texto:
        'Olá, [cliente]! Seu horário no [salão] está confirmado para [data] às [hora], com [profissional]. Serviço: [serviço].',
  ),
  'lembrete_horario': (
    nome: 'Lembrete de horário',
    texto:
        'Olá, [cliente]! Passando para lembrar do seu horário no [salão] em [data] às [hora]. Esperamos você!',
  ),
  'solicitacao_confirmacao': (
    nome: 'Solicitação de confirmação',
    texto:
        'Olá, [cliente]! Pode confirmar seu horário no [salão] para [data] às [hora]?',
  ),
  'cancelamento': (
    nome: 'Cancelamento',
    texto:
        'Olá, [cliente]. Seu horário de [data] às [hora] no [salão] foi cancelado. Fale conosco se quiser reagendar.',
  ),
  'reagendamento': (
    nome: 'Reagendamento',
    texto:
        'Olá, [cliente]! Seu novo horário no [salão] ficou para [data] às [hora].',
  ),
  'cobranca_sinal': (
    nome: 'Cobrança de sinal',
    texto:
        'Olá, [cliente]! Para confirmar seu horário, envie o sinal de R\$ [valor_sinal] via Pix [pix]. Recebedor: [nome_recebedor].',
  ),
  'envio_pix': (
    nome: 'Envio da chave Pix',
    texto:
        'Olá, [cliente]! Chave Pix: [pix]\nRecebedor: [nome_recebedor]\nBanco: [banco]. Após o pagamento, envie o comprovante por aqui.',
  ),
  'envio_endereco': (
    nome: 'Envio do endereço',
    texto:
        'Olá! Este é o endereço do [salão]:\n[endereço]\nPonto de referência: [ponto_referencia]\nRota: [link_rota]\nTelefone: [telefone_salao].',
  ),
  'agradecimento': (
    nome: 'Agradecimento após atendimento',
    texto:
        'Olá, [cliente]! Obrigado pela preferência. Foi um prazer atender você no [salão]!',
  ),
  'nao_compareceu': (
    nome: 'Cliente não compareceu',
    texto:
        'Olá, [cliente]. Sentimos sua falta no horário de hoje. Fale conosco para organizar um novo agendamento.',
  ),
  'cobranca_pos_atendimento': (
    nome: 'Cobrança após atendimento',
    texto:
        'Olá, [cliente]! Ficou pendente R\$ [valor_pendente] do seu atendimento no [salão]. Pix: [pix].',
  ),
  'resumo_comanda': (
    nome: 'Resumo da comanda',
    texto:
        'Olá, [cliente]!\n\nSegue o resumo da sua comanda de hoje no [salão]:\n\n[secao_servicos][secao_produtos]Total geral:\nR\$ [total_geral]\n\nForma de pagamento:\n[forma_pagamento]\n\n[status_pagamento]\n\nMuito obrigado pela preferência.\n\nEquipe [salão].',
  ),
  'resumo_atendimento': (
    nome: 'Resumo do atendimento',
    texto:
        'Olá, [cliente]!\n\nServiços realizados no [salão]:\n[lista_servicos]\n\nTotal: R\$ [total_servicos]. Obrigado pela preferência!',
  ),
  'resumo_produtos': (
    nome: 'Resumo de produtos comprados',
    texto:
        'Olá, [cliente]!\n\nProdutos adquiridos:\n[lista_produtos]\n\nTotal dos produtos: R\$ [total_produtos].',
  ),
  'valor_pendente': (
    nome: 'Valor pendente',
    texto:
        'Olá, [cliente]!\n\nFicou um valor pendente referente ao seu atendimento no [salão]:\n\nValor pendente:\nR\$ [valor_pendente]\n\nPix:\n[pix]\n\nRecebedor:\n[nome_recebedor]\n\nBanco:\n[banco]\n\nApós o pagamento, envie o comprovante por aqui.\n\nObrigado!',
  ),
  'pagamento_concluido': (
    nome: 'Pagamento concluído',
    texto:
        'Olá, [cliente]!\n\nRecebemos o pagamento referente ao seu atendimento no [salão].\n\nValor:\nR\$ [valor_pago]\n\nForma de pagamento:\n[forma_pagamento]\n\nPagamento concluído com sucesso.\n\nMuito obrigado pela preferência!',
  ),
  'convite_novo_agendamento': (
    nome: 'Convite para novo agendamento',
    texto:
        'Olá, [cliente]! Que tal reservar seu próximo horário no [salão]? Fale conosco para agendar.',
  ),
  'lembrete_dia_anterior': (
    nome: 'Lembrete automático — dia anterior às 16h',
    texto:
        'Olá, [cliente]! Seu atendimento no [salao] é amanhã, [data], às [hora], com [profissional]. Serviço: [servico]. Local: [localizacao]. Confirmar: [confirmacao] | Reagendar: [reagendamento] | Cancelar: [cancelamento].',
  ),
  'lembrete_duas_horas': (
    nome: 'Lembrete automático — duas horas antes',
    texto:
        'Olá, [cliente]! Faltam 2 horas para seu atendimento no [salao], hoje às [hora], com [profissional]. Serviço: [servico]. Local: [localizacao]. Confirmar: [confirmacao] | Reagendar: [reagendamento] | Cancelar: [cancelamento].',
  ),
  'alerta_aniversario_dona': (
    nome: 'Alerta diário de aniversários — proprietária',
    texto:
        'Aniversariante de hoje: [cliente]. Idade: [idade]. Cliente há [tempo_cliente_dias]. Último atendimento: [ultimo_atendimento]. Valor gasto: R\$ [valor_gasto]. Serviços favoritos: [servico_favorito].',
  ),
  'aniversario_cliente': (
    nome: 'Mensagem automática de aniversário — cliente',
    texto:
        'Parabéns, [cliente]! 🎉 A equipe do [salao] deseja um ciclo maravilhoso. Temos um carinho especial para você: [presente]. Cupom: [cupom]. Agende em [link_agendamento]. [imagem]',
  ),
  'conta_dia': (
    nome: 'Conta do dia',
    texto:
        'Olá, [cliente]!\n\nSua conta de hoje no [salão] ficou assim:\n\n[secao_servicos][secao_produtos]Total final:\nR\$ [total_geral]\n\nForma de pagamento:\n[forma_pagamento]\n\nObrigado pela preferência!',
  ),
};
