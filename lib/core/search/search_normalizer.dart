class SearchNormalizer {
  /// Remove acentos, caracteres especiais, múltiplos espaços e converte para minúsculo
  static String normalize(String text) {
    if (text.isEmpty) return text;

    var normalized = text.toLowerCase();

    // Remover acentos básicos
    normalized = normalized.replaceAll(RegExp(r'[áàâãä]'), 'a');
    normalized = normalized.replaceAll(RegExp(r'[éèêë]'), 'e');
    normalized = normalized.replaceAll(RegExp(r'[íìîï]'), 'i');
    normalized = normalized.replaceAll(RegExp(r'[óòôõö]'), 'o');
    normalized = normalized.replaceAll(RegExp(r'[úùûü]'), 'u');
    normalized = normalized.replaceAll(RegExp(r'[ç]'), 'c');
    normalized = normalized.replaceAll(RegExp(r'[ñ]'), 'n');

    // Remover caracteres não alfanuméricos exceto espaços
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9\s]'), '');

    // Remover espaços múltiplos e nas extremidades
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

    return normalized;
  }
}
