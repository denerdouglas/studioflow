import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/core/theme/studioflow_theme.dart';
import 'package:studioflow/core/utils/instagram_url.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/screens/dashboard_premium_page.dart';
import 'package:studioflow/screens/loja_salao_page.dart';
import 'package:studioflow/services/session_controller.dart';
import 'package:studioflow/services/vision_ocr_service.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Instagram', () {
    test('normaliza arroba e URLs aceitas para o perfil exato', () {
      expect(
        InstagramUrl.normalizar('@usuario'),
        'https://www.instagram.com/usuario/',
      );
      expect(
        InstagramUrl.normalizar('instagram.com/usuario'),
        'https://www.instagram.com/usuario/',
      );
      expect(
        InstagramUrl.normalizar('https://instagram.com/usuario/'),
        'https://www.instagram.com/usuario/',
      );
      expect(InstagramUrl.normalizar('https://instagram.com/'), isNull);
    });
  });

  group('OCR inteligente', () {
    test('separa código, preço, produto, material e fornecedor', () {
      final data = VisionOcrService.parseText(
        '526876\nR\$ 20,00\nBRINCO F. PRATA\nMiriam Guido',
      );
      expect(data.codigo, '526876');
      expect(data.preco, 20);
      expect(data.nome, 'BRINCO F. PRATA');
      expect(data.material?.toLowerCase(), 'prata');
      expect(data.fornecedor, 'Miriam Guido');
    });

    test('não confunde preço monet?rio com código', () {
      final data = VisionOcrService.parseText('R\$ 5268,76\nREF: 123456');
      expect(data.preco, 5268.76);
      expect(data.codigo, '123456');
    });
  });

  testWidgets('barra premium tem Início, Agenda, Loja e Mais', (tester) async {
    SessionController.instance.entrar(_usuario());
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPremiumPage(
          nomeResponsavel: 'Dener',
          nomeNegocio: 'Studio',
          tipoNegocio: 'Salão',
          tema: StudioFlowThemeData.sugeridoParaCategoria('Salão'),
        ),
      ),
    );
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(
      find.widgetWithText(NavigationDestination, 'Clientes'),
      findsNothing,
    );
    final labels = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((item) => item.label)
        .toList();
    expect(labels, ['Início', 'Agenda', 'Loja', 'Mais']);
    await tester.tap(find.text('Mais'));
    await tester.pump();
    expect(find.text('Clientes'), findsOneWidget);
    await tester.tap(find.text('Loja'));
    await tester.pump();
    expect(find.byType(LojaSalaoPage), findsOneWidget);
    SessionController.instance.cancelarSincronizacaoEmTeste();
  });
}

UsuarioAcesso _usuario() => UsuarioAcesso(
  id: 'u',
  comercioId: 'c',
  codigoComercio: 'SF',
  nomeComercio: 'Studio',
  nomeExibicao: 'Studio',
  nome: 'Dener',
  telefone: '11999999999',
  emailLogin: 'teste@studioflow.test',
  funcao: FuncaoUsuario.dono,
  ativo: true,
  permissoes: ModuloPermissao.values.toSet(),
  acoes: AcaoPermissao.values.toSet(),
);
