class DashboardConfiguration {
  final List<String> layout;

  const DashboardConfiguration({required this.layout});

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
