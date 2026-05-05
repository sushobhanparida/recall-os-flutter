import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';

// Injected at build time via --dart-define
const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'YOUR_SUPABASE_URL',
);
const _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'YOUR_SUPABASE_ANON_KEY',
);

void main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
  runApp(const RecallOSWebApp());
}
