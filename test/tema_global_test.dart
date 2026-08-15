import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studioflow/app.dart';
import 'package:studioflow/core/constants/app_colors.dart';
import 'package:studioflow/services/session_controller.dart';
import 'package:studioflow/models/domain/acesso.dart';

void main() {
  testWidgets('Validação do Tema Global - Cores e Semântica', (tester) async {
    // 1. Injetar um usuário com cor preferida Verde Escuro e no modo Claro
    final user = UsuarioAcesso(
      id: '1',
      comercioId: 'c1',
      codigoComercio: 'code',
      nomeComercio: 'Teste',
      nomeExibicao: 'Teste',
      nome: 'Teste',
      telefone: '11',
      emailLogin: 't@t.com',
      funcao: FuncaoUsuario.dono,
      ativo: true,
      permissoes: {},
      acoes: {},
      corPrincipal: '#006400', // Verde Escuro
      temaModo: 'claro',
    );

    SessionController.instance.entrar(user);

    await tester.pumpWidget(const StudioFlowApp());
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.byType(Scaffold).first);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 2. Verificar cor primary
    // ColorScheme fromSeed de '#006400' gera uma paleta tonal.
    // O primary NÃO será exatamente #006400 devido ao Tonal Palette do Material 3, mas será derivado dele.
    expect(colorScheme.primary.toARGB32(), isNot(AppColors.principal.toARGB32()));

    // 4. InputDecoration focado usa primary
    final focusedBorder =
        theme.inputDecorationTheme.focusedBorder as OutlineInputBorder;
    expect(focusedBorder.borderSide.color, colorScheme.primary);

    // 6. Verificar que cores semânticas não mudam de valor globalmente
    // Se fossem substituídas na UI, nós validamos que os AppColors continuam puros
    expect(AppColors.sucesso.toARGB32(), 0xFF15996B);
    expect(AppColors.erro.toARGB32(), 0xFFD64D64);

    // 7. Troca de paleta em runtime atualiza UI
    final userDarkPink = UsuarioAcesso(
      id: '1',
      comercioId: 'c1',
      codigoComercio: 'code',
      nomeComercio: 'Teste',
      nomeExibicao: 'Teste',
      nome: 'Teste',
      telefone: '11',
      emailLogin: 't@t.com',
      funcao: FuncaoUsuario.dono,
      ativo: true,
      permissoes: {},
      acoes: {},
      corPrincipal: '#FF1493', // Deep Pink
      temaModo: 'escuro', // Teste Dark Mode
    );

    // Atualiza usuário real-time sem recriar o app
    SessionController.instance.entrar(userDarkPink);
    await tester.pumpAndSettle();

    final BuildContext contextDark = tester.element(find.byType(Scaffold).first);
    final themeDark = Theme.of(contextDark);
    final colorSchemeDark = themeDark.colorScheme;

    // A cor mudou
    expect(colorSchemeDark.primary.toARGB32(), isNot(colorScheme.primary.toARGB32()));

    // O modo de brilho agora é escuro, garantindo contraste reverso
    expect(colorSchemeDark.brightness, Brightness.dark);

    // As superfícies são escuras
    expect(themeDark.scaffoldBackgroundColor, colorSchemeDark.surface);

    // Cleanup timer
    SessionController.instance.cancelarSincronizacaoEmTeste();
  });
}
