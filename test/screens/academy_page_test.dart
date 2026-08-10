import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/controllers/academy_controller.dart';
import 'package:studioflow/models/domain/academy.dart';
import 'package:studioflow/screens/academy_page.dart';
import 'package:studioflow/repositories/academy_repository.dart';

// Mocks
class MockAcademyRepository extends AcademyRepository {
  AcademySearchResult? mockResult;
  List<AcademyCategory>? mockCategories;
  Exception? mockError;
  int searchCalls = 0;
  int categoriesCalls = 0;

  @override
  Future<AcademySearchResult> search({
    String? query,
    String? categoryId,
  }) async {
    searchCalls++;
    if (mockError != null) throw mockError!;
    return mockResult ?? AcademySearchResult(courses: [], total: 0);
  }

  @override
  Future<List<AcademyCategory>> getCategories() async {
    categoriesCalls++;
    if (mockError != null) throw mockError!;
    return mockCategories ?? [];
  }
}

void main() {
  late MockAcademyRepository mockRepo;
  late AcademyController controller;

  setUp(() {
    mockRepo = MockAcademyRepository();
    controller = AcademyController(academyRepository: mockRepo);
  });

  Widget buildPage() {
    return MaterialApp(home: AcademyPage(controller: controller));
  }

  group('Academy Page Tests', () {
    testWidgets('1. Resposta courses: [] e Empty state', (tester) async {
      mockRepo.mockResult = AcademySearchResult(courses: [], total: 0);
      mockRepo.mockCategories = [];

      await tester.pumpWidget(buildPage());
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'gestão');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Nenhum curso encontrado no momento.'), findsOneWidget);
    });

    testWidgets('2. Estado Inicial (antes do Future completar)', (
      tester,
    ) async {
      await tester.pumpWidget(buildPage());
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('O que você quer aprender? Ex: Gestão'), findsOneWidget);
    });

    testWidgets('3. Loading', (tester) async {
      mockRepo.mockResult = AcademySearchResult(courses: [], total: 0);
      mockRepo.mockCategories = [];

      await tester.pumpWidget(buildPage());

      final emittedStates = <AcademyState>[];
      void listener() {
        emittedStates.add(controller.state);
      }

      controller.addListener(listener);

      final searchFuture = controller.search(query: 'teste');
      await tester.pump();
      await searchFuture;
      await tester.pumpAndSettle();

      controller.removeListener(listener);

      expect(
        emittedStates,
        containsAllInOrder([AcademyState.loading, AcademyState.empty]),
      );
      expect(controller.state, AcademyState.empty);
    });

    testWidgets('5. Found com fixture', (tester) async {
      mockRepo.mockResult = AcademySearchResult(
        courses: [
          AcademyCourse(
            id: 'c1',
            title: 'Curso de Teste',
            description: 'Desc',
            categoryId: 'cat1',
            authorName: 'Autor 1',
            authorAvatarUrl: '',
            durationMinutes: 120,
            difficultyLevel: 'beginner',
            price: 100.0,
            currency: 'BRL',
            totalReviews: 10,
            publicationStatus: 'published',
            publishedAt: DateTime.now(),
            updatedAt: DateTime.now(),
            clickId: 'clk1',
          ),
        ],
        total: 1,
      );
      mockRepo.mockCategories = [
        const AcademyCategory(id: 'cat1', name: 'Categoria 1'),
      ];

      await tester.pumpWidget(buildPage());
      await tester.enterText(find.byType(TextField), 'teste');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Curso de Teste'), findsOneWidget);
      expect(find.text('BRL 100.00'), findsOneWidget);
      expect(find.text('Categoria 1'), findsOneWidget);
    });

    testWidgets('6. Erro de API', (tester) async {
      mockRepo.mockError = Exception('Falha na conexão');

      await tester.pumpWidget(buildPage());
      await tester.enterText(find.byType(TextField), 'teste');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Falha ao buscar cursos'),
        findsOneWidget,
      );
    });

    testWidgets('7. Categorias exibidas e clicáveis', (tester) async {
      mockRepo.mockResult = AcademySearchResult(courses: [], total: 0);
      mockRepo.mockCategories = [
        const AcademyCategory(id: 'cat1', name: 'Marketing'),
        const AcademyCategory(id: 'cat2', name: 'Finanças'),
      ];

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Todos'), findsOneWidget);
      expect(find.text('Marketing'), findsOneWidget);
      expect(find.text('Finanças'), findsOneWidget);

      await tester.tap(find.text('Finanças'));
      await tester.pumpAndSettle();

      expect(controller.currentCategoryId, 'cat2');
    });

    testWidgets('8. Botão Matricular URL restrições', (tester) async {
      mockRepo.mockResult = AcademySearchResult(
        courses: [
          AcademyCourse(
            id: 'c1',
            title: 'Produto',
            description: '',
            categoryId: '',
            authorName: '',
            authorAvatarUrl: '',
            durationMinutes: 0,
            difficultyLevel: '',
            currency: '',
            totalReviews: 0,
            publicationStatus: 'published',
            publishedAt: DateTime.now(),
            updatedAt: DateTime.now(),
            clickId: '',
          ),
        ],
        total: 1,
      );
      mockRepo.mockCategories = [];

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle(); // trigger init

      expect(find.text('Matricular'), findsOneWidget);

      await tester.tap(find.text('Matricular'));
      await tester
          .pump(); // Não usar pumpAndSettle porque o SnackBar desaparece

      expect(find.text('Matrícula indisponível no momento.'), findsOneWidget);
    });

    testWidgets('9. Curso Coming Soon não tem botão Matricular', (
      tester,
    ) async {
      mockRepo.mockResult = AcademySearchResult(
        courses: [
          AcademyCourse(
            id: 'c1',
            title: 'Produto',
            description: '',
            categoryId: '',
            authorName: '',
            authorAvatarUrl: '',
            durationMinutes: 0,
            difficultyLevel: '',
            currency: '',
            totalReviews: 0,
            publicationStatus: 'coming_soon',
            publishedAt: DateTime.now(),
            updatedAt: DateTime.now(),
            clickId: null,
          ),
        ],
        total: 1,
      );
      mockRepo.mockCategories = [];

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle(); // trigger init

      expect(find.text('Matricular'), findsNothing);
      expect(find.text('Em breve'), findsOneWidget);
    });
  });
}
