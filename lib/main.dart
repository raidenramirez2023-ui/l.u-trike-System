import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'data/auth_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Env.isConfigured) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      // ignore: deprecated_member_use
      anonKey: Env.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    await AuthController.instance.init();
  }

  runApp(const LuTrikeApp());
}

class LuTrikeApp extends StatefulWidget {
  const LuTrikeApp({super.key});

  @override
  State<LuTrikeApp> createState() => _LuTrikeAppState();
}

class _LuTrikeAppState extends State<LuTrikeApp> {
  late final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'LuTrike · LU Tricycle Queue Management',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: _router,
    );
  }
}
