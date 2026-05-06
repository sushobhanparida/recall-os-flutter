import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/models/stack_model.dart';
import '../../core/models/screenshot_model.dart';
import '../../core/services/sharing_service.dart';
import '../../core/services/suggestion_service.dart';

class StacksState {
  final List<Stack> stacks;
  final bool isLoading;
  final String? error;

  const StacksState({
    this.stacks = const [],
    this.isLoading = false,
    this.error,
  });

  StacksState copyWith({
    List<Stack>? stacks,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      StacksState(
        stacks: stacks ?? this.stacks,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

class StacksNotifier extends StateNotifier<StacksState> {
  final AppDatabase _db;
  final Ref _ref;

  StacksNotifier(this._db, this._ref) : super(const StacksState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final stacks = await _db.getStacks();
      state = StacksState(stacks: stacks);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> createStack(String name) async {
    try {
      await _db.insertStack(Stack(name: name, createdAt: DateTime.now()));
      await load();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteStack(int id) async {
    try {
      final stack = await _db.getStackById(id);
      if (stack != null && stack.isShared) {
        try {
          await SharingService.instance.unshareStack(stack);
        } catch (e) {
          debugPrint('[SharingService] unshare on delete failed: $e');
        }
      }
      await _db.deleteStack(id);
      _ref.invalidate(stackDetailProvider);
      await load();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> renameStack(int id, String name) async {
    try {
      await _db.renameStack(id, name);
      _ref.invalidate(stackDetailProvider);
      await load();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> addScreenshot(int stackId, int screenshotId) async {
    try {
      await _db.addScreenshotToStack(stackId, screenshotId);
      _ref.invalidate(stackDetailProvider);
      await load();
      await _syncShareIfNeeded(stackId);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> removeScreenshot(int stackId, int screenshotId) async {
    try {
      await _db.removeScreenshotFromStack(stackId, screenshotId);
      _ref.invalidate(stackDetailProvider);
      await load();
      await _syncShareIfNeeded(stackId);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Silently syncs a shared stack's image list to Supabase.
  /// Non-fatal — local operations are never blocked by sync failures.
  Future<void> _syncShareIfNeeded(int stackId) async {
    try {
      final stack = await _db.getStackById(stackId);
      if (stack == null || !stack.isShared) return;
      await SharingService.instance.syncSharedStack(stack);
    } catch (e) {
      debugPrint('[SharingService] background sync failed for stack $stackId: $e');
    }
  }

  Future<int?> acceptSuggestion(StackSuggestion s) async {
    try {
      final id = await _db.createStackWithScreenshots(
        s.name,
        s.screenshots.map((sc) => sc.id!).toList(),
      );
      await _db.dismissSuggestion(s.dismissKey);
      _ref.invalidate(suggestionsProvider);
      await load();
      return id;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<void> dismissSuggestion(StackSuggestion s) async {
    try {
      await _db.dismissSuggestion(s.dismissKey);
      _ref.invalidate(suggestionsProvider);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

// Provider for a single stack by ID (for stack detail screen)
final stackDetailProvider =
    FutureProvider.family<Stack?, int>((ref, stackId) async {
  return AppDatabase.instance.getStackById(stackId);
});

// Provider for all screenshots (used in stack picker)
final allScreenshotsProvider = FutureProvider<List<Screenshot>>((ref) async {
  return AppDatabase.instance.getScreenshots();
});

// Suggested stacks computed from clustering OCR text across screenshots.
final suggestionsProvider =
    FutureProvider<List<StackSuggestion>>((ref) async {
  final db = AppDatabase.instance;
  final screenshots = await db.getScreenshots();
  final dismissed = await db.getDismissedSuggestionKeys();
  return SuggestionService().suggest(screenshots, dismissed);
});

final stacksProvider = StateNotifierProvider<StacksNotifier, StacksState>(
  (ref) => StacksNotifier(AppDatabase.instance, ref),
);
