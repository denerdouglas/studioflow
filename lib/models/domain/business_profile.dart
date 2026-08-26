import 'dart:convert';

import 'acesso.dart';

enum BusinessModule {
  agenda,
  servicos,
  equipe,
  clientes,
  caixa,
  financeiro,
  loja,
  produtos,
  estoque,
  fornecedores,
  relatorios,
}

class BusinessModuleConfiguration {
  final Set<BusinessModule> ativos;

  const BusinessModuleConfiguration(this.ativos);

  bool possui(BusinessModule module) => ativos.contains(module);

  BusinessModuleConfiguration alterar(BusinessModule module, bool ativo) {
    final modules = {...ativos};
    ativo ? modules.add(module) : modules.remove(module);
    return BusinessModuleConfiguration(Set.unmodifiable(modules));
  }

  String toJson() => jsonEncode({
    'version': 1,
    'modules': ativos.map((item) => item.name).toList()..sort(),
  });

  factory BusinessModuleConfiguration.fromJson(String value) {
    final decoded = jsonDecode(value) as Map<String, dynamic>;
    final names = (decoded['modules'] as List? ?? const []).whereType<String>();
    return BusinessModuleConfiguration(
      Set.unmodifiable(
        names.map(
          (name) => BusinessModule.values.firstWhere(
            (item) => item.name == name,
            orElse: () => BusinessModule.caixa,
          ),
        ),
      ),
    );
  }

  factory BusinessModuleConfiguration.complete() =>
      BusinessModuleConfiguration(Set.unmodifiable(BusinessModule.values));

  factory BusinessModuleConfiguration.defaultsFor(
    TipoEstabelecimento segment, {
    bool somenteLoja = false,
  }) {
    if (somenteLoja) {
      return const BusinessModuleConfiguration({
        BusinessModule.loja,
        BusinessModule.produtos,
        BusinessModule.estoque,
        BusinessModule.clientes,
        BusinessModule.caixa,
        BusinessModule.financeiro,
        BusinessModule.fornecedores,
        BusinessModule.relatorios,
      });
    }
    const baseServico = {
      BusinessModule.agenda,
      BusinessModule.servicos,
      BusinessModule.clientes,
      BusinessModule.caixa,
      BusinessModule.financeiro,
      BusinessModule.estoque,
      BusinessModule.relatorios,
    };
    return BusinessModuleConfiguration(
      Set.unmodifiable(switch (segment) {
        TipoEstabelecimento.salao => {...BusinessModule.values},
        TipoEstabelecimento.barbearia => {
          ...baseServico,
          BusinessModule.equipe,
          BusinessModule.produtos,
        },
        TipoEstabelecimento.nailDesigner => {
          ...baseServico,
          BusinessModule.produtos,
        },
        TipoEstabelecimento.lashDesigner ||
        TipoEstabelecimento.micropigmentacao ||
        TipoEstabelecimento.bronzeamento => baseServico,
        TipoEstabelecimento.estetica ||
        TipoEstabelecimento.podologia ||
        TipoEstabelecimento.spa ||
        TipoEstabelecimento.massagem => baseServico,
        TipoEstabelecimento.outro => BusinessModule.values.toSet(),
      }),
    );
  }
}

class BusinessProfile {
  final TipoEstabelecimento segment;
  final BusinessModuleConfiguration modules;
  final bool explicitConfiguration;

  const BusinessProfile({
    required this.segment,
    required this.modules,
    required this.explicitConfiguration,
  });

  factory BusinessProfile.legacy(TipoEstabelecimento segment) =>
      BusinessProfile(
        segment: segment,
        modules: BusinessModuleConfiguration.complete(),
        explicitConfiguration: false,
      );
}
