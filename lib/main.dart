import 'package:flutter/material.dart';

import 'app.dart';
import 'database/database_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DatabaseService.instance.database;

  runApp(const StudioFlowApp());
}
