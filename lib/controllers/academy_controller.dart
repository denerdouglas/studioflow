import 'package:flutter/foundation.dart';
import '../models/domain/academy.dart';
import '../repositories/academy_repository.dart';

enum AcademyState { initial, loading, empty, found, offline, error }

class AcademyController extends ChangeNotifier {
  final AcademyRepository academyRepository;

  AcademyState state = AcademyState.initial;
  AcademySearchResult? currentResult;
  List<AcademyCategory>? categories;

  String currentQuery = '';
  String? currentCategoryId;
  String? errorMessage;
  bool isOffline = false;

  AcademyController({required this.academyRepository});

  Future<void> init() async {
    await fetchCategories();
    if (categories != null && categories!.isNotEmpty) {
      await search(categoryId: categories!.first.id);
    } else {
      await search();
    }
  }

  Future<void> fetchCategories() async {
    try {
      categories = await academyRepository.getCategories();
      notifyListeners();
    } catch (e) {
      // It's okay if categories fail to load, we can still show search
      categories = [];
    }
  }

  Future<void> search({String query = '', String? categoryId}) async {
    currentQuery = query;
    currentCategoryId = categoryId;

    state = AcademyState.loading;
    errorMessage = null;
    isOffline = false;
    notifyListeners();

    try {
      final result = await academyRepository.search(
        query: query.isEmpty ? null : query,
        categoryId: categoryId,
      );

      currentResult = result;

      if (result.courses.isEmpty) {
        state = AcademyState.empty;
      } else {
        state = AcademyState.found;
      }
    } catch (e) {
      state = AcademyState.error;
      errorMessage =
          'Falha ao buscar cursos. Verifique sua conexão e tente novamente.';
    }

    notifyListeners();
  }
}
