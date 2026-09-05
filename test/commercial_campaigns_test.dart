import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/models/domain/commercial_campaign.dart';
import 'package:studioflow/repositories/commercial_campaign_repository.dart';
import 'package:studioflow/screens/commercial_campaigns_page.dart';

class _FakeRepository extends CommercialCampaignRepository {
  _FakeRepository(this.items);
  final List<CommercialCampaign> items;
  final List<String> impressions = [];
  final List<String> clicks = [];

  @override
  Future<List<CommercialCampaign>> list() async => items;

  @override
  Future<void> impression(String id) async => impressions.add(id);

  @override
  Future<void> click(String id) async => clicks.add(id);
}

CommercialCampaign _item({
  String source = 'rolg_academy',
  String url = 'https://rolg.com/curso',
  DateTime? endsAt,
}) => CommercialCampaign(
  id: 'campaign-1',
  title: 'Gestão para salões',
  subtitle: 'Curso completo',
  description: 'Aprenda gestão.',
  destinationUrl: url,
  category: 'curso',
  sourceType: source,
  priceCents: 9900,
  originalPriceCents: 14900,
  ctaText: 'Conhecer curso',
  priority: 10,
  endsAt: endsAt,
);

void main() {
  test('Academy e afiliado recebem identificação explícita', () {
    expect(_item().disclosure, 'ROLG Academy');
    expect(_item(source: 'affiliate').disclosure, 'Publicidade');
    expect(_item(source: 'partner').disclosure, 'Oferta de parceiro');
  });

  test('destino aceita HTTPS e rejeita HTTP, esquema malicioso e inválido', () {
    expect(CommercialCampaign.safeDestination('https://rolg.com/x'), isNotNull);
    expect(CommercialCampaign.safeDestination('http://rolg.com/x'), isNull);
    expect(CommercialCampaign.safeDestination('javascript:alert(1)'), isNull);
    expect(CommercialCampaign.safeDestination('inválida'), isNull);
    expect(
      CommercialCampaign.safeDestination('https://user:pass@rolg.com'),
      isNull,
    );
  });

  test('validade local elimina campanha expirada', () {
    final now = DateTime(2026, 9, 5);
    expect(_item(endsAt: now).isValidAt(now), isFalse);
    expect(
      _item(endsAt: now.add(const Duration(seconds: 1))).isValidAt(now),
      isTrue,
    );
  });

  test('cache tem TTL finito e não devolve conteúdo expirado', () {
    expect(CommercialCampaignRepository.cacheTtl, const Duration(hours: 24));
    final now = DateTime(2026, 9, 5);
    final json = {
      'campaigns': [
        {
          'id': 'expired',
          'title': 'Expirada',
          'description': '',
          'destinationUrl': 'https://rolg.com/x',
          'category': 'curso',
          'sourceType': 'rolg_academy',
          'ctaText': 'Abrir',
          'priority': 1,
          'endsAt': now.toIso8601String(),
        },
      ],
    };
    expect(CommercialCampaignRepository.decodeValid(json, now), isEmpty);
  });

  testWidgets('lista renderiza oferta e rebuild não duplica impressão', (
    tester,
  ) async {
    final repository = _FakeRepository([_item()]);
    await tester.pumpWidget(
      MaterialApp(home: CommercialCampaignsPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gestão para salões'), findsOneWidget);
    expect(find.text('ROLG Academy • Curso completo'), findsOneWidget);
    expect(repository.impressions, ['campaign-1']);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.purple),
        home: CommercialCampaignsPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.impressions, ['campaign-1']);
  });

  testWidgets('falha/resultado vazio não quebra a página', (tester) async {
    final repository = _FakeRepository(const []);
    await tester.pumpWidget(
      MaterialApp(home: CommercialCampaignsPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma oferta disponível agora.'), findsOneWidget);
  });
}
