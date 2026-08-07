abstract class SearchEngine<T> {
  /// Indexa uma nova entidade ou atualiza uma existente no motor de busca
  Future<void> index(T entity);

  /// Remove uma entidade do índice
  Future<void> remove(String id);

  /// Realiza uma busca textual e retorna as entidades correspondentes
  Future<List<T>> search(String query);

  /// Limpa todo o índice
  Future<void> clear();
}
