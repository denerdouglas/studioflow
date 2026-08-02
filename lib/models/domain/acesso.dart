enum TipoEstabelecimento {
  salao,
  barbearia,
  estetica,
  nailDesigner,
  lashDesigner,
  podologia,
  spa,
  massagem,
  micropigmentacao,
  bronzeamento,
  outro,
}

extension TipoEstabelecimentoDados on TipoEstabelecimento {
  String get nome => switch (this) {
    TipoEstabelecimento.salao => 'Salão',
    TipoEstabelecimento.barbearia => 'Barbearia',
    TipoEstabelecimento.estetica => 'Estética',
    TipoEstabelecimento.nailDesigner => 'Nail Designer',
    TipoEstabelecimento.lashDesigner => 'Lash Designer',
    TipoEstabelecimento.podologia => 'Podologia',
    TipoEstabelecimento.spa => 'Spa',
    TipoEstabelecimento.massagem => 'Massagem',
    TipoEstabelecimento.micropigmentacao => 'Micropigmentação',
    TipoEstabelecimento.bronzeamento => 'Bronzeamento',
    TipoEstabelecimento.outro => 'Outro',
  };

  static TipoEstabelecimento pelaChave(String? chave) =>
      TipoEstabelecimento.values.firstWhere(
        (item) => item.name == chave,
        orElse: () => TipoEstabelecimento.salao,
      );
}

enum FuncaoUsuario { dono, gerente, colaborador }

extension FuncaoUsuarioDados on FuncaoUsuario {
  String get nome => switch (this) {
    FuncaoUsuario.dono => 'Dono',
    FuncaoUsuario.gerente => 'Gerente',
    FuncaoUsuario.colaborador => 'Colaborador',
  };

  static FuncaoUsuario pelaChave(String? chave) {
    return FuncaoUsuario.values.firstWhere(
      (item) => item.name == chave,
      orElse: () => FuncaoUsuario.colaborador,
    );
  }
}

enum ModuloPermissao {
  agenda,
  clientes,
  servicos,
  funcionarios,
  caixa,
  financeiro,
  relatorios,
  estoque,
  lojaSalao,
  configuracoes,
  administracaoUsuarios,
}

enum AcaoPermissao {
  visualizarEstoque,
  visualizarCusto,
  cadastrarProduto,
  editarProduto,
  movimentarEstoque,
  realizarVenda,
  aplicarDesconto,
  cancelarVenda,
  cadastrarFornecedor,
  criarPedido,
  aprovarPedido,
  receberPedido,
  acessarConsignacao,
  acessarRelatorios,
  configurarIa,
  visualizarConversas,
  configurarPix,
  gerenciarAgenda,
  excluirAgendamento,
  acessarFinanceiro,
  visualizarPacotes,
  criarPacotes,
  editarPacotes,
  venderPacotes,
  aplicarDescontoPacote,
  alterarValidadePacote,
  cancelarPacote,
  baixarSessaoPacote,
  estornarPagamentoPacote,
  transferirPacote,
  consultarRelatoriosPacotes,
}

extension AcaoPermissaoDados on AcaoPermissao {
  String get nome => switch (this) {
    AcaoPermissao.visualizarEstoque => 'Visualizar estoque',
    AcaoPermissao.visualizarCusto => 'Visualizar custo',
    AcaoPermissao.cadastrarProduto => 'Cadastrar produto',
    AcaoPermissao.editarProduto => 'Editar produto',
    AcaoPermissao.movimentarEstoque => 'Movimentar estoque',
    AcaoPermissao.realizarVenda => 'Realizar venda',
    AcaoPermissao.aplicarDesconto => 'Aplicar desconto',
    AcaoPermissao.cancelarVenda => 'Cancelar venda',
    AcaoPermissao.cadastrarFornecedor => 'Cadastrar fornecedor',
    AcaoPermissao.criarPedido => 'Criar pedido',
    AcaoPermissao.aprovarPedido => 'Aprovar pedido',
    AcaoPermissao.receberPedido => 'Receber pedido',
    AcaoPermissao.acessarConsignacao => 'Acessar consignação',
    AcaoPermissao.acessarRelatorios => 'Acessar relatórios',
    AcaoPermissao.configurarIa => 'Configurar IA',
    AcaoPermissao.visualizarConversas => 'Visualizar conversas',
    AcaoPermissao.configurarPix => 'Configurar Pix',
    AcaoPermissao.gerenciarAgenda => 'Gerenciar agenda',
    AcaoPermissao.excluirAgendamento => 'Excluir agendamento',
    AcaoPermissao.acessarFinanceiro => 'Acessar financeiro',
    AcaoPermissao.visualizarPacotes => 'Visualizar pacotes',
    AcaoPermissao.criarPacotes => 'Criar pacotes',
    AcaoPermissao.editarPacotes => 'Editar pacotes',
    AcaoPermissao.venderPacotes => 'Vender pacotes',
    AcaoPermissao.aplicarDescontoPacote => 'Aplicar desconto em pacote',
    AcaoPermissao.alterarValidadePacote => 'Alterar validade de pacote',
    AcaoPermissao.cancelarPacote => 'Cancelar pacote',
    AcaoPermissao.baixarSessaoPacote => 'Dar baixa em sessão de pacote',
    AcaoPermissao.estornarPagamentoPacote => 'Estornar pagamento de pacote',
    AcaoPermissao.transferirPacote => 'Transferir pacote',
    AcaoPermissao.consultarRelatoriosPacotes =>
      'Consultar relatórios de pacotes',
  };

  String get grupo => switch (this) {
    AcaoPermissao.visualizarEstoque ||
    AcaoPermissao.visualizarCusto ||
    AcaoPermissao.cadastrarProduto ||
    AcaoPermissao.editarProduto ||
    AcaoPermissao.movimentarEstoque => 'Estoque e produtos',
    AcaoPermissao.realizarVenda ||
    AcaoPermissao.aplicarDesconto ||
    AcaoPermissao.cancelarVenda => 'Vendas',
    AcaoPermissao.cadastrarFornecedor ||
    AcaoPermissao.criarPedido ||
    AcaoPermissao.aprovarPedido ||
    AcaoPermissao.receberPedido => 'Compras e fornecedores',
    AcaoPermissao.acessarConsignacao => 'Consignação',
    AcaoPermissao.acessarRelatorios => 'Relatórios',
    AcaoPermissao.configurarIa ||
    AcaoPermissao.visualizarConversas => 'Inteligência artificial',
    AcaoPermissao.configurarPix ||
    AcaoPermissao.acessarFinanceiro => 'Financeiro e Pix',
    AcaoPermissao.gerenciarAgenda ||
    AcaoPermissao.excluirAgendamento => 'Agenda',
    AcaoPermissao.visualizarPacotes ||
    AcaoPermissao.criarPacotes ||
    AcaoPermissao.editarPacotes ||
    AcaoPermissao.venderPacotes ||
    AcaoPermissao.aplicarDescontoPacote ||
    AcaoPermissao.alterarValidadePacote ||
    AcaoPermissao.cancelarPacote ||
    AcaoPermissao.baixarSessaoPacote ||
    AcaoPermissao.estornarPagamentoPacote ||
    AcaoPermissao.transferirPacote ||
    AcaoPermissao.consultarRelatoriosPacotes => 'Pacotes de serviços',
  };
}

Set<AcaoPermissao> acoesPadrao(FuncaoUsuario funcao) {
  return switch (funcao) {
    FuncaoUsuario.dono => AcaoPermissao.values.toSet(),
    FuncaoUsuario.gerente =>
      AcaoPermissao.values
          .where((acao) => acao != AcaoPermissao.visualizarCusto)
          .toSet(),
    FuncaoUsuario.colaborador => {
      AcaoPermissao.visualizarEstoque,
      AcaoPermissao.realizarVenda,
      AcaoPermissao.gerenciarAgenda,
    },
  };
}

extension ModuloPermissaoDados on ModuloPermissao {
  String get nome => switch (this) {
    ModuloPermissao.agenda => 'Agenda',
    ModuloPermissao.clientes => 'Clientes',
    ModuloPermissao.servicos => 'Serviços',
    ModuloPermissao.funcionarios => 'Funcionários',
    ModuloPermissao.caixa => 'Caixa',
    ModuloPermissao.financeiro => 'Financeiro',
    ModuloPermissao.relatorios => 'Relatórios',
    ModuloPermissao.estoque => 'Estoque',
    ModuloPermissao.lojaSalao => 'Loja do salão',
    ModuloPermissao.configuracoes => 'Configurações',
    ModuloPermissao.administracaoUsuarios => 'Administração de usuários',
  };
}

Set<ModuloPermissao> permissoesPadrao(FuncaoUsuario funcao) {
  return switch (funcao) {
    FuncaoUsuario.dono => ModuloPermissao.values.toSet(),
    FuncaoUsuario.gerente => {
      ModuloPermissao.agenda,
      ModuloPermissao.clientes,
      ModuloPermissao.servicos,
      ModuloPermissao.funcionarios,
      ModuloPermissao.caixa,
      ModuloPermissao.financeiro,
      ModuloPermissao.relatorios,
      ModuloPermissao.estoque,
      ModuloPermissao.configuracoes,
    },
    FuncaoUsuario.colaborador => {
      ModuloPermissao.agenda,
      ModuloPermissao.clientes,
      ModuloPermissao.servicos,
    },
  };
}

class UsuarioAcesso {
  final String id;
  final String comercioId;
  final String codigoComercio;
  final String nomeComercio;
  final String nomeExibicao;
  final String nome;
  final String telefone;
  final String emailLogin;
  final FuncaoUsuario funcao;
  final bool ativo;
  final Set<ModuloPermissao> permissoes;
  final Set<AcaoPermissao> acoes;
  final TipoEstabelecimento tipoEstabelecimento;
  final String logoPath;
  final String corPrincipal;
  final String corSecundaria;
  final String corDestaque;
  final String temaModo;
  final bool temaAutomatico;
  final String capaUrl;

  const UsuarioAcesso({
    required this.id,
    required this.comercioId,
    required this.codigoComercio,
    required this.nomeComercio,
    required this.nomeExibicao,
    required this.nome,
    required this.telefone,
    required this.emailLogin,
    required this.funcao,
    required this.ativo,
    required this.permissoes,
    required this.acoes,
    this.tipoEstabelecimento = TipoEstabelecimento.salao,
    this.logoPath = '',
    this.corPrincipal = '#70569A',
    this.corSecundaria = '#8B5CF6',
    this.corDestaque = '#D9C7F2',
    this.temaModo = 'claro',
    this.temaAutomatico = true,
    this.capaUrl = '',
  });

  bool pode(ModuloPermissao modulo) {
    return ativo &&
        (funcao == FuncaoUsuario.dono || permissoes.contains(modulo));
  }

  bool podeAcao(AcaoPermissao acao) {
    return ativo && (funcao == FuncaoUsuario.dono || acoes.contains(acao));
  }
}

class UsuarioGerenciavel {
  final String id;
  final String comercioId;
  final String? profissionalId;
  final String nome;
  final String telefone;
  final String emailLogin;
  final FuncaoUsuario funcao;
  final bool ativo;
  final Set<ModuloPermissao> permissoes;
  final Set<AcaoPermissao> acoes;
  final TipoEstabelecimento tipoEstabelecimento;
  final String logoPath;
  final String corPrincipal;
  final String corSecundaria;
  final String corDestaque;
  final String temaModo;
  final bool temaAutomatico;
  final String capaUrl;

  const UsuarioGerenciavel({
    required this.id,
    required this.comercioId,
    required this.profissionalId,
    required this.nome,
    required this.telefone,
    required this.emailLogin,
    required this.funcao,
    required this.ativo,
    required this.permissoes,
    required this.acoes,
    this.tipoEstabelecimento = TipoEstabelecimento.salao,
    this.logoPath = '',
    this.corPrincipal = '#70569A',
    this.corSecundaria = '#8B5CF6',
    this.corDestaque = '#D9C7F2',
    this.temaModo = 'claro',
    this.temaAutomatico = true,
    this.capaUrl = '',
  });
}

class CadastroComercioEntrada {
  final String nomeComercio;
  final String nomeExibicao;
  final String responsavel;
  final String telefone;
  final String email;
  final String senha;
  final bool permanecerConectado;
  final TipoEstabelecimento tipoEstabelecimento;

  const CadastroComercioEntrada({
    required this.nomeComercio,
    required this.nomeExibicao,
    required this.responsavel,
    required this.telefone,
    required this.email,
    required this.senha,
    required this.permanecerConectado,
    this.tipoEstabelecimento = TipoEstabelecimento.salao,
  });
}
