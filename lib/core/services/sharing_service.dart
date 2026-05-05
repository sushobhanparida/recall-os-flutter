import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';
import '../models/screenshot_model.dart';
import '../models/stack_model.dart';
import '../supabase/supabase_config.dart';

class SharingService {
  SharingService._();
  static final SharingService instance = SharingService._();

  static const _bucket = 'stack-images';
  static const _webBaseUrl = 'https://recallos-web-viewer.vercel.app/stack';

  static SupabaseClient get _client => SupabaseConfig.client;

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<String> shareStack(Stack stack) async {
    _assertAuthenticated();
    final imageUrls = await _uploadImages(stack.screenshots, stack.id!);
    if (stack.sharedId != null) {
      final found =
          await _updateSharedStack(stack.sharedId!, stack.name, imageUrls);
      if (found) return '$_webBaseUrl/${stack.sharedId}';
      // Local sharedId exists but Supabase record is gone — recreate.
    }
    final sharedId = await _createSharedStack(stack.name, imageUrls);
    await AppDatabase.instance.setStackSharedId(stack.id!, sharedId);
    debugPrint('[SharingService] created shared_stacks row id=$sharedId');
    return '$_webBaseUrl/$sharedId';
  }

  /// Re-syncs image_urls for an already-shared stack after add/remove.
  Future<void> syncSharedStack(Stack stack) async {
    if (stack.sharedId == null) return;
    _assertAuthenticated();
    final imageUrls = await _uploadImages(stack.screenshots, stack.id!);
    await _updateSharedStack(stack.sharedId!, stack.name, imageUrls);
  }

  /// Deletes the Supabase record and clears the local sharedId.
  Future<void> unshareStack(Stack stack) async {
    if (stack.sharedId == null) return;
    await _client.from('shared_stacks').delete().eq('id', stack.sharedId!);
    await AppDatabase.instance.setStackSharedId(stack.id!, null);
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
      String name, List<String> imageUrls) async {
    final userId = _client.auth.currentUser!.id;
    final response = await _client
        .from('shared_stacks')
        .insert({
          'stack_name': name,
          'owner_id': userId,
          'image_urls': imageUrls,
        })
        .select('id')
        .single();
    return response['id'] as String;
  }

  Future<bool> _updateSharedStack(
      String sharedId, String name, List<String> imageUrls) async {
    final rows = await _client
        .from('shared_stacks')
        .update({'stack_name': name, 'image_urls': imageUrls})
        .eq('id', sharedId)
        .select('id');
    return rows.isNotEmpty;
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
