import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/core/theme/studioflow_theme.dart';
import 'package:studioflow/models/domain/acesso.dart';
import 'package:studioflow/screens/mais_premium_page.dart';
import 'package:studioflow/services/session_controller.dart';

void main() {
  testWidgets('menu Mais expõe equipe e serviços e pacotes após clientes', (
    tester,
  ) async {
    SessionController.instance.entrar(
      UsuarioAcesso(
        id: 'owner',
        comercioId: 'commerce',
        codigoComercio: 'MENU1',
        nomeComercio: 'Studio',
        nomeExibicao: 'Studio',
        nome: 'Dona',
        telefone: '1199',
        emailLogin: 'dona@studio.test',
        funcao: FuncaoUsuario.dono,
        ativo: true,
        permissoes: ModuloPermissao.values.toSet(),
        acoes: AcaoPermissao.values.toSet(),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: MaisPremiumPage(tema: StudioFlowTheme.elegante)),
    );

    expect(find.text('Clientes'), findsOneWidget);
    expect(find.text('Equipe e Comissões'), findsOneWidget);
    expect(find.text('Serviços e Pacotes'), findsOneWidget);

    final clientes = tester.getTopLeft(find.text('Clientes')).dy;
    final equipe = tester.getTopLeft(find.text('Equipe e Comissões')).dy;
    final servicos = tester.getTopLeft(find.text('Serviços e Pacotes')).dy;
    expect(clientes, lessThan(equipe));
    expect(equipe, lessThan(servicos));
    SessionController.instance.cancelarSincronizacaoEmTeste();
  });
}
