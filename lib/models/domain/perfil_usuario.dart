enum TipoPerfil { proprietario, gerente, profissional, recepcao }

extension TipoPerfilDados on TipoPerfil {
  String get nome {
    switch (this) {
      case TipoPerfil.proprietario:
        return 'Proprietário';
      case TipoPerfil.gerente:
        return 'Gerente';
      case TipoPerfil.profissional:
        return 'Profissional';
      case TipoPerfil.recepcao:
        return 'Recepção';
    }
  }

  String get descricao {
    switch (this) {
      case TipoPerfil.proprietario:
        return 'Acesso completo ao negócio, financeiro e configurações.';
      case TipoPerfil.gerente:
        return 'Gerencia equipe, agenda, clientes, estoque e financeiro.';
      case TipoPerfil.profissional:
        return 'Acessa agenda própria, clientes vinculados, metas e comissão.';
      case TipoPerfil.recepcao:
        return 'Gerencia agenda, clientes, confirmações e reagendamentos.';
    }
  }
}

enum PermissaoUsuario {
  visualizarAgendaGeral,
  visualizarAgendaPropria,
  criarAgendamento,
  editarAgendamento,
  cancelarAgendamento,
  bloquearHorarios,
  visualizarTodosClientes,
  visualizarClientesVinculados,
  cadastrarCliente,
  editarCliente,
  visualizarAnamnese,
  editarAnamnese,
  visualizarCaixaGeral,
  registrarEntrada,
  registrarSaida,
  visualizarComissoesGerais,
  visualizarPropriaComissao,
  visualizarEstoque,
  editarEstoque,
  visualizarRelatorios,
  gerenciarProfissionais,
  gerenciarPermissoes,
  alterarConfiguracoes,
  usarStudioFlowIa,
}

class PerfilUsuario {
  final String id;
  final String nome;
  final String email;
  final String whatsapp;
  final TipoPerfil tipo;
  final String? profissionalId;
  final bool ativo;
  final Set<PermissaoUsuario> permissoesExtras;

  const PerfilUsuario({
    required this.id,
    required this.nome,
    required this.email,
    required this.whatsapp,
    required this.tipo,
    this.profissionalId,
    this.ativo = true,
    this.permissoesExtras = const {},
  });

  Set<PermissaoUsuario> get permissoes {
    return {..._permissoesPadrao(tipo), ...permissoesExtras};
  }

  bool possuiPermissao(PermissaoUsuario permissao) {
    return ativo && permissoes.contains(permissao);
  }

  static Set<PermissaoUsuario> _permissoesPadrao(TipoPerfil tipo) {
    switch (tipo) {
      case TipoPerfil.proprietario:
        return PermissaoUsuario.values.toSet();

      case TipoPerfil.gerente:
        return {
          PermissaoUsuario.visualizarAgendaGeral,
          PermissaoUsuario.visualizarAgendaPropria,
          PermissaoUsuario.criarAgendamento,
          PermissaoUsuario.editarAgendamento,
          PermissaoUsuario.cancelarAgendamento,
          PermissaoUsuario.bloquearHorarios,
          PermissaoUsuario.visualizarTodosClientes,
          PermissaoUsuario.visualizarClientesVinculados,
          PermissaoUsuario.cadastrarCliente,
          PermissaoUsuario.editarCliente,
          PermissaoUsuario.visualizarAnamnese,
          PermissaoUsuario.editarAnamnese,
          PermissaoUsuario.visualizarCaixaGeral,
          PermissaoUsuario.registrarEntrada,
          PermissaoUsuario.registrarSaida,
          PermissaoUsuario.visualizarComissoesGerais,
          PermissaoUsuario.visualizarPropriaComissao,
          PermissaoUsuario.visualizarEstoque,
          PermissaoUsuario.editarEstoque,
          PermissaoUsuario.visualizarRelatorios,
          PermissaoUsuario.gerenciarProfissionais,
          PermissaoUsuario.usarStudioFlowIa,
        };

      case TipoPerfil.profissional:
        return {
          PermissaoUsuario.visualizarAgendaPropria,
          PermissaoUsuario.criarAgendamento,
          PermissaoUsuario.editarAgendamento,
          PermissaoUsuario.cancelarAgendamento,
          PermissaoUsuario.bloquearHorarios,
          PermissaoUsuario.visualizarClientesVinculados,
          PermissaoUsuario.cadastrarCliente,
          PermissaoUsuario.editarCliente,
          PermissaoUsuario.visualizarAnamnese,
          PermissaoUsuario.editarAnamnese,
          PermissaoUsuario.visualizarPropriaComissao,
          PermissaoUsuario.usarStudioFlowIa,
        };

      case TipoPerfil.recepcao:
        return {
          PermissaoUsuario.visualizarAgendaGeral,
          PermissaoUsuario.criarAgendamento,
          PermissaoUsuario.editarAgendamento,
          PermissaoUsuario.cancelarAgendamento,
          PermissaoUsuario.bloquearHorarios,
          PermissaoUsuario.visualizarTodosClientes,
          PermissaoUsuario.cadastrarCliente,
          PermissaoUsuario.editarCliente,
          PermissaoUsuario.visualizarAnamnese,
          PermissaoUsuario.registrarEntrada,
          PermissaoUsuario.usarStudioFlowIa,
        };
    }
  }
}
