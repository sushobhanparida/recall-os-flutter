import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';
import '../models/screenshot_model.dart';
import '../models/stack_model.dart';
import '../supabase/supabase_config.dart';

class StackAvatarInfo {
  final String? ownerAvatarUrl;
  final String? ownerName;
  final List<String> memberAvatarUrls;
  const StackAvatarInfo({this.ownerAvatarUrl, this.ownerName, this.memberAvatarUrls = const []});
}

class SharingService {
  SharingService._();
  static final SharingService instance = SharingService._();

  static const _bucket = 'stack-images';
  static const _webBaseUrl = 'https://recallos-web-viewer.vercel.app/stack';

  static SupabaseClient get _client => SupabaseConfig.client;

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<String> shareStack(Stack stack, {bool isPrivate = true}) async {
    _assertAuthenticated();
    await _upsertOwnProfile();
    final imageUrls = await _uploadImages(stack.screenshots, stack.id!);
    if (stack.sharedId != null) {
      // Upsert by known UUID: updates if row exists, re-creates if deleted.
      // Avoids a SELECT-after-UPDATE which could falsely return empty under
      // certain RLS configurations and cause duplicate orphaned rows.
      await _upsertSharedStack(stack.sharedId!, stack.name, imageUrls, isPrivate: isPrivate);
      return '$_webBaseUrl/${stack.sharedId}';
    }
    final sharedId = await _createSharedStack(stack.name, imageUrls, isPrivate: isPrivate);
    await AppDatabase.instance.setStackSharedId(stack.id!, sharedId);
    debugPrint('[SharingService] created shared_stacks row id=$sharedId');
    return '$_webBaseUrl/$sharedId';
  }

  /// Re-syncs image_urls for an already-shared stack after add/remove.
  Future<void> syncSharedStack(Stack stack) async {
    if (stack.sharedId == null) return;
    _assertAuthenticated();
    final imageUrls = await _uploadImages(stack.screenshots, stack.id!);
    await _upsertSharedStack(stack.sharedId!, stack.name, imageUrls, isPrivate: stack.isPrivate);
  }

  /// Toggles the public/private flag without re-uploading images.
  Future<void> togglePublic(Stack stack, {required bool isPublic}) async {
    if (stack.sharedId == null) return;
    _assertAuthenticated();
    await _client.from('shared_stacks')
        .update({'is_private': !isPublic})
        .eq('id', stack.sharedId!);
    await AppDatabase.instance.setStackPrivacy(stack.id!, !isPublic);
  }

  /// Deletes the Supabase record and clears the local sharedId.
  Future<void> unshareStack(Stack stack) async {
    if (stack.sharedId == null) return;
    await _client.from('shared_stacks').delete().eq('id', stack.sharedId!);
    await AppDatabase.instance.setStackSharedId(stack.id!, null);
  }

  /// Called when a recipient opens a shared link. Idempotent — safe to call on re-open.
  Future<int> saveSharedStack(String sharedId) async {
    _assertAuthenticated();
    final data = await _client
        .from('shared_stacks')
        .select('id, stack_name, image_urls, owner_id, is_private')
        .eq('id', sharedId)
        .maybeSingle();
    if (data == null) throw Exception('Shared stack not found: $sharedId');

    final imageUrls = List<String>.from(data['image_urls'] as List? ?? []);
    final ownerId = data['owner_id'] as String?;

    String? ownerAvatarUrl;
    String? ownerName;
    if (ownerId != null) {
      final profile = await _client
          .from('profiles')
          .select('display_name, avatar_url')
          .eq('id', ownerId)
          .maybeSingle();
      ownerAvatarUrl = profile?['avatar_url'] as String?;
      ownerName = profile?['display_name'] as String?;
    }

    final localId = await AppDatabase.instance.saveReadOnlyStack(
      sharedId: sharedId,
      name: data['stack_name'] as String,
      imageUrls: imageUrls,
      ownerName: ownerName,
      ownerAvatarUrl: ownerAvatarUrl,
    );

    // Register as a member (upsert via unique constraint)
    final userId = _client.auth.currentUser!.id;
    await _client.from('shared_stack_members').upsert(
      {'stack_id': sharedId, 'user_id': userId},
      onConflict: 'stack_id,user_id',
    );

    // Upsert own profile so others can see our avatar
    await _upsertOwnProfile();

    return localId;
  }

  /// Removes a recipient's copy of a shared stack locally and from membership.
  Future<void> removeSharedStack(Stack stack) async {
    if (!stack.isReadOnly || stack.id == null) return;
    await AppDatabase.instance.deleteStack(stack.id!);
    if (stack.sharedId != null) {
      final userId = _client.auth.currentUser?.id;
      if (userId != null) {
        await _client.from('shared_stack_members')
            .delete()
            .eq('stack_id', stack.sharedId!)
            .eq('user_id', userId);
      }
    }
  }

  /// Fetches owner + member avatar info for a shared stack and caches locally.
  Future<StackAvatarInfo> fetchAndCacheAvatars(Stack stack) async {
    if (stack.sharedId == null || stack.id == null) {
      return const StackAvatarInfo();
    }
    _assertAuthenticated();

    // Round 1 — owner lookup and member ID list are independent: run in parallel.
    final round1 = await Future.wait<dynamic>([
      _client
          .from('shared_stacks')
          .select('owner_id')
          .eq('id', stack.sharedId!)
          .maybeSingle(),
      _client
          .from('shared_stack_members')
          .select('user_id')
          .eq('stack_id', stack.sharedId!),
    ]);

    final ownerId = (round1[0] as Map<String, dynamic>?)?['owner_id'] as String?;
    final userIds = (round1[1] as List<dynamic>)
        .map((m) => m['user_id'] as String)
        .toList();

    // Round 2 — owner profile and member profiles are independent: run in parallel.
    // Two separate profile queries because shared_stack_members.user_id → auth.users
    // (not profiles), so Supabase can't do the embedded join automatically.
    final round2 = await Future.wait<dynamic>([
      ownerId != null
          ? _client
              .from('profiles')
              .select('display_name, avatar_url')
              .eq('id', ownerId)
              .maybeSingle()
          : Future<dynamic>.value(null),
      userIds.isNotEmpty
          ? _client
              .from('profiles')
              .select('avatar_url')
              .inFilter('id', userIds)
          : Future<dynamic>.value(<dynamic>[]),
    ]);

    final ownerProfile = round2[0] as Map<String, dynamic>?;
    final ownerAvatarUrl = ownerProfile?['avatar_url'] as String?;
    final ownerName = ownerProfile?['display_name'] as String?;

    final memberAvatarUrls = (round2[1] as List<dynamic>)
        .map((p) => p['avatar_url'] as String?)
        .whereType<String>()
        .toList();

    await AppDatabase.instance.updateStackAvatars(
      stack.id!,
      ownerAvatarUrl: ownerAvatarUrl,
      ownerName: ownerName,
      memberAvatars: memberAvatarUrls,
    );

    return StackAvatarInfo(
      ownerAvatarUrl: ownerAvatarUrl,
      ownerName: ownerName,
      memberAvatarUrls: memberAvatarUrls,
    );
  }

  String buildShareUrl(String sharedId) => '$_webBaseUrl/$sharedId';

  // ── Private helpers ────────────────────────────────────────────────────────

  void _assertAuthenticated() {
    if (_client.auth.currentUser == null) {
      throw Exception('User not authenticated — sign in before sharing.');
    }
  }

  Future<List<String>> _uploadImages(
      List<Screenshot> screenshots, int stackId) async {
    final userId = _client.auth.currentUser!.id;
    final results = <String>[];
    final failures = <String>[];

    for (final screenshot in screenshots) {
      try {
        final url = await _uploadOne(screenshot, userId, stackId);
        results.add(url);
      } catch (e) {
        debugPrint('[SharingService] upload failed for ${screenshot.uri}: $e');
        failures.add(screenshot.uri);
      }
    }

    if (failures.isNotEmpty && results.isEmpty) {
      throw Exception(
          'All ${failures.length} image uploads failed. Check connectivity.');
    }
    if (failures.isNotEmpty) {
      throw _PartialUploadException(
        uploaded: results.length,
        total: screenshots.length,
        failed: failures,
      );
    }
    return results;
  }

  Future<String> _uploadOne(
      Screenshot screenshot, String userId, int stackId) async {
    // Already a remote URL — skip re-upload.
    if (screenshot.uri.startsWith('http')) return screenshot.uri;

    final file = File(screenshot.uri);
    if (!file.existsSync()) {
      throw Exception('Local file missing: ${screenshot.uri}');
    }

    // Path: {userId}/{stackId}/{screenshotId}.jpg
    // Each stack gets its own folder; stable key for idempotent upserts.
    final screenshotId = screenshot.id ?? screenshot.uri.hashCode;
    final storagePath = '$userId/$stackId/$screenshotId.jpg';

    final bytes = await file.readAsBytes();
    await _client.storage.from(_bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions:
              const FileOptions(contentType: 'image/jpeg', upsert: true),
        );

    return _client.storage.from(_bucket).getPublicUrl(storagePath);
  }

  Future<String> _createSharedStack(
      String name, List<String> imageUrls, {bool isPrivate = true}) async {
    final userId = _client.auth.currentUser!.id;
    final response = await _client
        .from('shared_stacks')
        .insert({
          'stack_name': name,
          'owner_id': userId,
          'image_urls': imageUrls,
          'is_private': isPrivate,
        })
        .select('id')
        .single();
    return response['id'] as String;
  }

  Future<void> _upsertSharedStack(
      String sharedId, String name, List<String> imageUrls, {bool isPrivate = true}) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('shared_stacks').upsert(
      {
        'id': sharedId,
        'stack_name': name,
        'owner_id': userId,
        'image_urls': imageUrls,
        'is_private': isPrivate,
      },
      onConflict: 'id',
    );
  }

  Future<void> _upsertOwnProfile() async {
    final user = _client.auth.currentUser!;
    final meta = user.userMetadata ?? {};
    final avatarUrl = meta['avatar_url'] as String? ?? meta['picture'] as String?;
    final name = meta['full_name'] as String? ?? meta['name'] as String? ?? user.email;
    await _client.from('profiles').upsert(
      {'id': user.id, 'display_name': name, 'avatar_url': avatarUrl},
      onConflict: 'id',
    );
  }
}

class _PartialUploadException implements Exception {
  final int uploaded;
  final int total;
  final List<String> failed;

  _PartialUploadException({
    required this.uploaded,
    required this.total,
    required this.failed,
  });

  @override
  String toString() =>
      'Partial upload: $uploaded/$total images shared. '
      '${failed.length} failed (files may have been moved or deleted).';
}
