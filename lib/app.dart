import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'screens/app_bootstrap_page.dart';
import 'services/session_controller.dart';

class StudioFlowApp extends StatelessWidget {
  const StudioFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SessionController.instance,
      builder: (context, _) {
        final usuario = SessionController.instance.usuario;
        final principal = _cor(usuario?.corPrincipal, const Color(0xFF70569A));
        final claro = ColorScheme.fromSeed(
          seedColor: principal,
          brightness: Brightness.light,
        );
        final escuro = ColorScheme.fromSeed(
          seedColor: principal,
          brightness: Brightness.dark,
        );
        final modo = switch (usuario?.temaModo) {
          'escuro' => ThemeMode.dark,
          'sistema' => ThemeMode.system,
          _ => ThemeMode.light,
        };
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: AppConstants.nome,
          locale: const Locale(
            AppConstants.localeIdioma,
            AppConstants.localePais,
          ),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('pt', 'BR')],
          theme: AppTheme.buildTheme(claro),
          darkTheme: AppTheme.buildTheme(escuro),
          themeMode: modo,
          home: const AppBootstrapPage(),
        );
      },
    );
  }

  static Color _cor(String? valor, Color padrao) {
    final texto = (valor ?? '').replaceFirst('#', '');
    final numero = int.tryParse(texto, radix: 16);
    return numero == null ? padrao : Color(0xFF000000 | numero);
  }
}
