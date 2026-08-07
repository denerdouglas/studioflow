enum TipoProduto {
  venda,
  usoInterno,
  ambos,
  ativoImobilizado;

  /// Retorna o valor exato a ser persistido no banco de dados, imune a refatorações de código.
  String toStorage() {
    switch (this) {
      case TipoProduto.venda:
        return 'venda';
      case TipoProduto.usoInterno:
        return 'uso_interno';
      case TipoProduto.ambos:
        return 'ambos';
      case TipoProduto.ativoImobilizado:
        return 'ativo_imobilizado';
    }
  }

  /// Converte a string persistida de volta para a tipagem forte do Enum.
  static TipoProduto fromStorage(String? value) {
    switch (value) {
      case 'venda':
        return TipoProduto.venda;
      case 'uso_interno':
        return TipoProduto.usoInterno;
      case 'ambos':
        return TipoProduto.ambos;
      case 'ativo_imobilizado':
        return TipoProduto.ativoImobilizado;
      default:
        // Mantém 'venda' como default fallback para integridade de legados
        return TipoProduto.venda;
    }
  }
}
