import '../models/domain/business_profile.dart';

class DashboardConfiguration {
  final List<String> layout;

  const DashboardConfiguration({required this.layout});

  factory DashboardConfiguration.lojaLayout() {
    return const DashboardConfiguration(
      layout: ['caixa', 'estoque_alerts', 'indicadores', 'ia_panel'],
    );
  }

  factory DashboardConfiguration.defaultLayout() {
    return const DashboardConfiguration(
      layout: [
        'modalidades',
        'ia_panel',
        'caixa',
        'agenda',
        'estoque_alerts',
        'indicadores',
      ],
    );
  }

  factory DashboardConfiguration.forModules(
    BusinessModuleConfiguration modules,
  ) {
    if (!modules.possui(BusinessModule.servicos)) {
      return DashboardConfiguration.lojaLayout();
    }
    return DashboardConfiguration(
      layout: [
        if (modules.possui(BusinessModule.servicos)) 'modalidades',
        'ia_panel',
        if (modules.possui(BusinessModule.caixa)) 'caixa',
        if (modules.possui(BusinessModule.agenda)) 'agenda',
        if (modules.possui(BusinessModule.estoque)) 'estoque_alerts',
        if (modules.possui(BusinessModule.relatorios)) 'indicadores',
      ],
    );
  }
}
