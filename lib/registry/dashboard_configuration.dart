class DashboardConfiguration {
  final List<String> layout;

  const DashboardConfiguration({required this.layout});

  factory DashboardConfiguration.lojaLayout() {
    return const DashboardConfiguration(
      layout: [
        'caixa',
        'estoque_alerts',
        'indicadores',
        'ia_panel',
      ],
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
}
