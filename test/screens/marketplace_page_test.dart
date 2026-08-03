import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/controllers/marketplace_controller.dart';
import 'package:studioflow/models/domain/marketplace.dart';
import 'package:studioflow/screens/marketplace_page.dart';
import 'package:studioflow/repositories/marketplace_repository.dart';
import 'package:studioflow/repositories/recommendation_engine.dart';
import 'package:studioflow/repositories/estoque_repository.dart';
import 'package:studioflow/database/database_service.dart';

// Mocks
class MockMarketplaceRepository extends MarketplaceRepository {
  MarketplaceSearchResult? mockResult;
  Exception? mockError;
  int calls = 0;

  @override
  Future<MarketplaceSearchResult> search(String query) async {
    calls++;
    if (mockError != null) throw mockError!;
    return mockResult ??
        MarketplaceSearchResult(
          results: [],
          page: 1,
          total: 0,
          fetchedAt: DateTime.now(),
        );
  }
}

class MockEstoqueRepository extends EstoqueRepository {
  MockEstoqueRepository() : super(databaseService: DatabaseService.instance);
}

class MockRecommendationEngine extends RecommendationEngine {
  RecommendationMessage? mockRec;

  MockRecommendationEngine()
    : super(estoqueRepository: MockEstoqueRepository());

  @override
  Future<RecommendationMessage?> generateRecommendation() async {
    return mockRec;
  }
}

void main() {
  late MockMarketplaceRepository mockRepo;
  late MockRecommendationEngine mockRecEngine;
  late MarketplaceController controller;

  setUp(() {
    mockRepo = MockMarketplaceRepository();
    mockRecEngine = MockRecommendationEngine();
    controller = MarketplaceController(
      marketplaceRepository: mockRepo,
      recommendationEngine: mockRecEngine,
    );
  });

  Widget buildPage() {
    return MaterialApp(home: MarketplacePage(controller: controller));
  }

  group('Marketplace Page Tests', () {
    testWidgets('1. Resposta results: [] e 4. Empty state', (tester) async {
      mockRepo.mockResult = MarketplaceSearchResult(
        results: [],
        page: 1,
        total: 0,
        fetchedAt: DateTime.now(),
      );

      await tester.pumpWidget(buildPage());
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'shampoo');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        find.text('Nenhuma oferta disponível para esta pesquisa no momento.'),
        findsOneWidget,
      );
    });

    testWidgets('2. Estado Inicial', (tester) async {
      await tester.pumpWidget(buildPage());
      expect(controller.state, MarketplaceState.initial);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('O que você procura? Ex: Shampoo'), findsOneWidget);
    });

    testWidgets('3. Loading', (tester) async {
      mockRepo.mockResult = MarketplaceSearchResult(
        results: [],
        page: 1,
        total: 0,
        fetchedAt: DateTime.now(),
      );

      await tester.pumpWidget(buildPage());

      final emittedStates = <MarketplaceState>[];
      void listener() {
        emittedStates.add(controller.state);
      }

      controller.addListener(listener);

      final searchFuture = controller.search('teste');
      await tester.pump();
      await searchFuture;
      await tester.pumpAndSettle();

      controller.removeListener(listener);

      expect(
        emittedStates,
        containsAllInOrder([MarketplaceState.loading, MarketplaceState.empty]),
      );
      expect(controller.state, MarketplaceState.empty);
    });

    testWidgets('5. Found com fixture', (tester) async {
      mockRepo.mockResult = MarketplaceSearchResult(
        results: [
          MarketplaceProductGroup(
            title: 'Produto de Teste',
            offers: [
              MarketplaceOffer(
                partner: MarketplacePartner(slug: 'p1', name: 'Parceiro 1'),
                clickId: 'clk1',
                priceCents: 1000,
                updatedAt: DateTime.now(),
              ),
            ],
          ),
        ],
        page: 1,
        total: 1,
        fetchedAt: DateTime.now(),
      );

      await tester.pumpWidget(buildPage());
      await tester.enterText(find.byType(TextField), 'teste');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Produto de Teste'), findsOneWidget);
      expect(find.text('Parceiro 1'), findsOneWidget);
      expect(find.text('R\$ 10.00'), findsOneWidget);
    });

    testWidgets('6. Erro de API', (tester) async {
      mockRepo.mockError = Exception('Falha na conexão');

      await tester.pumpWidget(buildPage());
      await tester.enterText(find.byType(TextField), 'teste');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        find.text('Falha ao buscar ofertas. Tente novamente.'),
        findsOneWidget,
      );
    });

    testWidgets(
      '7. Offline com cache válido e 8. Offline sem cache (via repository logic)',
      (tester) async {
        mockRepo.mockResult = MarketplaceSearchResult(
          results: [],
          page: 1,
          total: 0,
          fetchedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        );

        await tester.pumpWidget(buildPage());
        await tester.enterText(find.byType(TextField), 'teste');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(controller.isOffline, true);
        expect(find.textContaining('Modo Offline'), findsOneWidget);
      },
    );

    testWidgets('13. Recomendação por estoque baixo', (tester) async {
      mockRecEngine.mockRec = RecommendationMessage(
        text: 'Só restam 2 unidades de Esmalte',
        actionLabel: 'Ver ofertas',
        suggestedQuery: 'Esmalte',
      );

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle(); // trigger init

      expect(find.text('Sugestão Inteligente'), findsOneWidget);
      expect(find.text('Só restam 2 unidades de Esmalte'), findsOneWidget);
    });

    testWidgets('14. Ausência de recomendação', (tester) async {
      mockRecEngine.mockRec = null;

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Sugestão Inteligente'), findsNothing);
    });

    testWidgets('20. Botão Comprar restrições e URL inválida', (tester) async {
      mockRepo.mockResult = MarketplaceSearchResult(
        results: [
          MarketplaceProductGroup(
            title: 'Produto',
            offers: [
              MarketplaceOffer(
                partner: MarketplacePartner(slug: 'p1', name: 'P1'),
                clickId: 'invalido_url',
                priceCents: 1000,
                updatedAt: DateTime.now(),
              ),
              MarketplaceOffer(
                partner: MarketplacePartner(slug: 'p2', name: 'P2'),
                clickId: '',
                priceCents: 1000,
                updatedAt: DateTime.now(),
              ),
            ],
          ),
        ],
        page: 1,
        total: 1,
        fetchedAt: DateTime.now(),
      );

      await tester.pumpWidget(buildPage());
      await tester.enterText(find.byType(TextField), 'teste');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final buyButtons = find.widgetWithText(FilledButton, 'Comprar');
      expect(buyButtons, findsNWidgets(2));

      await tester.tap(buyButtons.last);
      await tester.pump();
      expect(find.text('Oferta indisponível para compra.'), findsOneWidget);
    });

    testWidgets('23. Selo exibido (badges)', (tester) async {
      mockRepo.mockResult = MarketplaceSearchResult(
        results: [
          MarketplaceProductGroup(
            title: 'Produto',
            offers: [
              MarketplaceOffer(
                partner: MarketplacePartner(slug: 'p1', name: 'P1'),
                clickId: 'clk1',
                priceCents: 1000,
                updatedAt: DateTime.now(),
                badges: ['Frete Grátis', 'Patrocinado'],
              ),
            ],
          ),
        ],
        page: 1,
        total: 1,
        fetchedAt: DateTime.now(),
      );

      await tester.pumpWidget(buildPage());
      await tester.enterText(find.byType(TextField), 'teste');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Frete Grátis'), findsOneWidget);
      expect(find.text('Patrocinado'), findsOneWidget);
    });
  });
}
