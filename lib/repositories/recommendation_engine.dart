import 'estoque_repository.dart';

class RecommendationMessage {
  final String text;
  final String actionLabel;
  final String suggestedQuery;

  RecommendationMessage({
    required this.text,
    required this.actionLabel,
    required this.suggestedQuery,
  });
}

class RecommendationEngine {
  final EstoqueRepository estoqueRepository;

  RecommendationEngine({required this.estoqueRepository});

  Future<RecommendationMessage?> generateRecommendation() async {
    try {
      final estoqueBaixo = await estoqueRepository.listarEstoqueBaixo();
      if (estoqueBaixo.isNotEmpty) {
        // Find one that makes sense
        for (final item in estoqueBaixo) {
          if (item.estoqueMinimo > 0 &&
              item.quantidadeAtual <= item.estoqueMinimo) {
            return RecommendationMessage(
              text:
                  'Só restam ${item.quantidadeAtual.toInt()} unidades de ${item.nome}.',
              actionLabel: 'Ver ofertas',
              suggestedQuery: item.nome,
            );
          }
        }
      }

      // Future: add Equipment check (requires real dates as per user requirement)
      // Future: add Reposição recorrente (requires purchase history)
    } catch (e) {
      // Ignora erro no motor de recomendação
    }
    return null;
  }
}
