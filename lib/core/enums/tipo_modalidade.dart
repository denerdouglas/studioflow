/// Define a hierarquia da modalidade instalada em uma empresa.
enum TipoModalidade {
  /// A modalidade principal do negócio (ex: Salão de Beleza). Só pode existir uma ativa.
  principal,

  /// Uma modalidade paralela grande (ex: Barbearia dentro do Salão).
  secundaria,

  /// Especialidades focadas (ex: Manicure, Estética).
  especialidade,

  /// Subdivisões ultra focadas (ex: Cílios, Sobrancelha).
  subespecialidade,
}

extension TipoModalidadeExtension on TipoModalidade {
  String get nome {
    switch (this) {
      case TipoModalidade.principal:
        return 'principal';
      case TipoModalidade.secundaria:
        return 'secundaria';
      case TipoModalidade.especialidade:
        return 'especialidade';
      case TipoModalidade.subespecialidade:
        return 'subespecialidade';
    }
  }

  static TipoModalidade fromNome(String nome) {
    return TipoModalidade.values.firstWhere(
      (e) => e.nome == nome,
      orElse: () => TipoModalidade.especialidade,
    );
  }
}
