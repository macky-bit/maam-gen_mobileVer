import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/supabase_service.dart';
import 'services/tmdb_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var environment = '';
  try {
    environment = await rootBundle.loadString('.env');
    TmdbService.configureFromEnv(environment);
  } on FlutterError {
    // A --dart-define credential can still configure builds without .env.
  }
  final supabase = await SupabaseService.initialize(environment);
  runApp(StreamFlixApp(supabase: supabase));
}
