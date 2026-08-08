import 'package:flutter/material.dart';

import 'app.dart';
import 'database/database_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await DatabaseService.instance.database;
  } catch (e) {
    debugPrint('Erro não fatal no pré-carregamento do SQLite: $e');
  }

  runApp(const StudioFlowApp());
}
