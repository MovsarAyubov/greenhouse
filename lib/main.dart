import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'scada/ui/scada_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const profile = String.fromEnvironment(
    'SCADA_ENV',
    defaultValue: 'physical',
  );
  final envFile = profile == 'emulated' ? '.env.emulated' : '.env.physical';
  await dotenv.load(fileName: envFile);
  runApp(const ScadaApp());
}
