/// Representa a origem de uma modalidade.
enum OrigemModalidade {
  /// Importada automaticamente de um SegmentTemplate padrão do sistema.
  importado,

  /// Criada manualmente pelo usuário na interface.
  manual,
}

extension OrigemModalidadeExtension on OrigemModalidade {
  String get nome {
    switch (this) {
      case OrigemModalidade.importado:
        return 'importado';
      case OrigemModalidade.manual:
        return 'manual';
    }
  }

  static OrigemModalidade fromNome(String nome) {
    return OrigemModalidade.values.firstWhere(
      (e) => e.nome == nome,
      orElse: () => OrigemModalidade.manual,
    );
  }
}
