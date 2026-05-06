import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'features/stack_viewer/stack_viewer_screen.dart';
import 'features/stack_viewer/stack_viewer_error.dart';
import 'features/auth/login_screen.dart';

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/stack/:id',
      builder: (context, state) => StackViewerScreen(
        stackId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/auth/login',
      builder: (context, state) => LoginScreen(
        redirect: state.uri.queryParameters['redirect'] ?? '/',
      ),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) =>
          const StackViewerError(stackId: ''),
    ),
  ],
  errorBuilder: (context, state) =>
      const StackViewerError(stackId: ''),
);

class RecallOSWebApp extends StatelessWidget {
  const RecallOSWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'RecallOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C3AED),
          surface: Color(0xFF141414),
        ),
      ),
      routerConfig: _router,
    );
  }
}
