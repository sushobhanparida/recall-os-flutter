import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/auth/auth_provider.dart';
import 'core/auth/auth_state.dart';
import 'core/services/screenshot_watcher_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/colors.dart';
import 'core/theme/typography.dart';
import 'core/models/task_model.dart';
import 'features/auth/auth_landing_screen.dart';
import 'features/auth/verify_email_screen.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/auth/reset_password_screen.dart';
import 'features/home/home_provider.dart';
import 'features/home/home_screen.dart';
import 'features/task/task_provider.dart';
import 'features/task/task_screen.dart';
import 'features/task/widgets/add_to_tasks_sheet.dart';
import 'features/stacks/stacks_screen.dart';
import 'features/stacks/widgets/stack_chooser_sheet.dart';
import 'features/screenshot_detail/screenshot_detail_screen.dart';
import 'features/stack_detail/stack_detail_screen.dart';
import 'features/stack_detail/shared_stack_landing_screen.dart';
import 'features/notes/note_picker_screen.dart';
import 'features/notes/note_editor_screen.dart';
import 'features/task/task_detail_screen.dart';

// ── Router provider ────────────────────────────────────────────────────────────

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      // ── Auth routes ──────────────────────────────────────────────────────
      GoRoute(path: '/auth/login', builder: (_, __) => const AuthLandingScreen()),
      GoRoute(path: '/auth/verify-email', builder: (_, __) => const VerifyEmailScreen()),
      GoRoute(path: '/auth/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/auth/reset-password', builder: (_, __) => const ResetPasswordScreen()),

      // ── App routes ───────────────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/tasks', builder: (_, __) => const TaskScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/stacks', builder: (_, __) => const StacksScreen()),
          ]),
        ],
      ),
      GoRoute(
        path: '/tasks/:id',
        builder: (_, state) => TaskDetailScreen(
          taskId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/screenshot/:id',
        builder: (_, state) => ScreenshotDetailScreen(
          screenshotId: int.parse(state.pathParameters['id']!),
          task: state.extra is Task ? state.extra as Task : null,
        ),
      ),
      GoRoute(
        path: '/stack/:id',
        builder: (_, state) {
          final id = state.pathParameters['id']!;
          final localId = int.tryParse(id);
          if (localId != null) {
            return StackDetailScreen(stackId: localId);
          }
          // UUID-format id → incoming shared-stack deep link
          return SharedStackLandingScreen(sharedId: id);
        },
      ),
      GoRoute(path: '/notes/picker', builder: (_, __) => const NotePickerScreen()),
      GoRoute(
        path: '/notes/edit/:id',
        builder: (_, state) => NoteEditorScreen(
          screenshotId: int.parse(state.pathParameters['id']!),
        ),
      ),
    ],
  );
});

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final auth = _ref.read(authProvider);
    final loc = state.matchedLocation;
    final onAuth = loc.startsWith('/auth');

    if (auth is AuthInitial) return null;
    if (auth is AuthUnauthenticated && !onAuth) return '/auth/login';
    if (auth is AuthUnverified && loc != '/auth/verify-email') return '/auth/verify-email';
    if (auth is AuthAuthenticated && onAuth) return '/home';
    if (loc == '/todo') return '/tasks';
    return null;
  }
}

// ── App entry ─────────────────────────────────────────────────────────────────

class RecallOSApp extends ConsumerWidget {
  const RecallOSApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch auth so the widget rebuilds when auth changes, which triggers
    // the router's refreshListenable via _RouterNotifier.
    ref.watch(authProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'RecallOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}

// ── App Shell ──────────────────────────────────────────────────────────────────

class _AppShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell shell;

  const _AppShell({required this.shell});

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell> {
  StreamSubscription<ScreenshotAction>? _actionSub;

  @override
  void initState() {
    super.initState();
    _actionSub = ScreenshotWatcherService.events.listen(_handleAction);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Request storage permission before starting the service.
      // On Android 13+ this shows a system dialog if not yet granted.
      await ScreenshotWatcherService.requestMediaPermission();
      await ScreenshotWatcherService.start();
      await ScreenshotWatcherService.checkPending();
    });
  }

  @override
  void dispose() {
    _actionSub?.cancel();
    super.dispose();
  }

  Future<void> _handleAction(ScreenshotAction event) async {
    if (!mounted) return;

    // Show a brief "processing" indicator while we run OCR + entity extraction
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Processing screenshot…'),
        duration: Duration(seconds: 30),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final resolvedPath = await ScreenshotWatcherService.resolveUri(event.uri);
    if (resolvedPath == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not read screenshot'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final screenshot =
        await ref.read(homeProvider.notifier).importFromPath(resolvedPath);

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (screenshot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not process screenshot'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    switch (event.action) {
      case 'save':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved to RecallOS'),
            behavior: SnackBarBehavior.floating,
          ),
        );

      case 'stack':
        await showModalBottomSheet<void>(
          context: context,
          backgroundColor: AppColors.bgElevated,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          isScrollControlled: true,
          builder: (_) => StackChooserSheet(screenshot: screenshot),
        );

      case 'addtask':
        await showModalBottomSheet<void>(
          context: context,
          backgroundColor: AppColors.bgElevated,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          isScrollControlled: true,
          builder: (_) => AddToTasksSheet(
            screenshot: screenshot,
            onCreate: (task) =>
                ref.read(taskProvider.notifier).addTask(task),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: _LinearNavBar(
        currentIndex: widget.shell.currentIndex,
        onTap: (i) => widget.shell.goBranch(
          i,
          initialLocation: i == widget.shell.currentIndex,
        ),
      ),
    );
  }
}

// ── Bottom Nav ─────────────────────────────────────────────────────────────────

class _LinearNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = [
    (Icons.grid_view_rounded, Icons.grid_view_rounded, 'Home'),
    (Icons.check_circle_outline_rounded, Icons.check_circle_rounded, 'Tasks'),
    (Icons.layers_outlined, Icons.layers_rounded, 'Stacks'),
  ];

  const _LinearNavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(
          top: BorderSide(color: AppColors.borderDefault, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: List.generate(_items.length, (i) {
              final (outlinedIcon, filledIcon, label) = _items[i];
              final isSelected = i == currentIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          isSelected ? filledIcon : outlinedIcon,
                          key: ValueKey(isSelected),
                          color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        style: AppTypography.labelSm.copyWith(
                          color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
