import 'package:flutter/foundation.dart';
import '../models/domain/marketplace.dart';
import '../repositories/marketplace_repository.dart';
import '../repositories/recommendation_engine.dart';

enum MarketplaceState { initial, loading, empty, found, offline, error }

class MarketplaceController extends ChangeNotifier {
  final MarketplaceRepository marketplaceRepository;
  final RecommendationEngine recommendationEngine;

  MarketplaceState state = MarketplaceState.initial;
  MarketplaceSearchResult? currentResult;
  String currentQuery = '';
  String? errorMessage;
  bool isOffline = false;

  RecommendationMessage? recommendation;

  MarketplaceController({
    required this.marketplaceRepository,
    required this.recommendationEngine,
  });

  Future<void> init() async {
    await fetchRecommendation();
  }

  Future<void> fetchRecommendation() async {
    recommendation = await recommendationEngine.generateRecommendation();
    notifyListeners();
  }

  Future<void> search(String query) async {
    if (query.trim().isEmpty) return;

    currentQuery = query;
    state = MarketplaceState.loading;
    errorMessage = null;
    isOffline = false;
    notifyListeners();

    try {
      final result = await marketplaceRepository.search(query);
      currentResult = result;
      
      // Checar se pegamos do cache
      // No repository, se pegou do cache o fetchedAt será no passado, e não atualizado agora.
      // O repositório levanta exceção se o servidor cair e não houver cache.
      // Mas o repositório retorna o cache se o servidor cair.
      final age = DateTime.now().difference(result.fetchedAt);
      if (age.inSeconds > 10) {
        // Provavelmente cache
        isOffline = true;
      }

      if (result.results.isEmpty) {
        state = MarketplaceState.empty;
      } else {
        state = MarketplaceState.found;
      }
    } catch (e) {
      state = MarketplaceState.error;
      errorMessage = 'Falha ao buscar ofertas. Tente novamente.';
    }

    notifyListeners();
  }
}
