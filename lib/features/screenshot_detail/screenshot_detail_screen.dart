import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/database/app_database.dart';
import '../../core/models/extracted_entity.dart';
import '../../core/models/screenshot_model.dart';
import '../../core/models/task_model.dart';
import '../../core/services/crop_service.dart';
import '../../core/services/smart_actions_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/tag_badge.dart';
import '../home/home_provider.dart';
import '../stacks/stacks_provider.dart';
import '../stacks/widgets/stack_chooser_sheet.dart';
import '../task/task_provider.dart';
import '../task/widgets/add_to_tasks_sheet.dart';

/// Hides generic QR raw payloads & addresses; dedupes same-value pills.
List<ExtractedEntity> _filterAndDedupeEntityPills(
    List<ExtractedEntity> entities) {
  final out = <ExtractedEntity>[];
  final seen = <String>{};
  for (final e in entities) {
    if (e.type == 'address' || e.type == 'qr') continue;
    final key = _entityPillDedupeKey(e);
    if (!seen.add(key)) continue;
    out.add(e);
  }
  return out;
}

String _entityPillDedupeKey(ExtractedEntity e) {
  switch (e.type) {
    case 'url':
    case 'qr_url':
      return 'url::${_normalizeUrlForCompare(e.rawText)}';
    case 'phone':
    case 'qr_phone':
      return 'phone::${_sanitizedPhoneDigits(e.rawText)}';
    case 'email':
    case 'qr_email':
      return 'email::${_parseEmailAddress(e.rawText).toLowerCase()}';
    case 'date':
      final ts = e.value?['timestamp'] as int?;
      return 'date::${ts ?? e.rawText.toLowerCase().trim().hashCode}';
    case 'money':
      return 'money::${e.rawText.toLowerCase().trim()}';
    case 'flight':
      final airline = e.value?['airline'] as String?;
      final number = e.value?['number'] as String?;
      if (airline != null && number != null) {
        return 'flight::${airline.toUpperCase()}${number.toUpperCase()}';
      }
      return 'flight::${e.rawText.toLowerCase().trim()}';
    default:
      return '${e.type}::${e.rawText.toLowerCase().trim()}';
  }
}

String _normalizeUrlForCompare(String raw) {
  var u = raw.trim();
  if (!u.startsWith('http://') && !u.startsWith('https://')) {
    u = 'https://$u';
  }
  try {
    final uri = Uri.parse(u);
    final host = uri.host.toLowerCase();
    var path = uri.path;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final q = uri.hasQuery ? '?${uri.query}' : '';
    return '$host$path$q'.toLowerCase();
  } catch (_) {
    return u.toLowerCase();
  }
}

String _sanitizedPhoneDigits(String raw) {
  var s = raw.trim();
  if (s.toLowerCase().startsWith('tel:')) s = s.substring(4);
  return s.replaceAll(RegExp(r'\D'), '');
}

String _parseEmailAddress(String raw) {
  var s = raw.trim();
  if (s.toLowerCase().startsWith('mailto:')) {
    s = s.substring(7);
  }
  return s.split('?').first.trim();
}

bool _entityPillIsInteractive(String type) {
  return type == 'money' ||
      type == 'date' ||
      type == 'url' ||
      type == 'qr_url' ||
      type == 'phone' ||
      type == 'qr_phone' ||
      type == 'email' ||
      type == 'qr_email';
}

String _telUriBody(String raw) {
  var s = raw.trim();
  if (s.toLowerCase().startsWith('tel:')) s = s.substring(4);
  final buf = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (RegExp(r'[0-9+*#;]', caseSensitive: false).hasMatch(c)) {
      buf.write(c);
    }
  }
  return buf.toString();
}

Future<void> _handleEntityPillTap(
  BuildContext context,
  WidgetRef ref,
  Screenshot screenshot,
  ExtractedEntity entity,
) async {
  switch (entity.type) {
    case 'money':
      await Clipboard.setData(ClipboardData(text: entity.rawText.trim()));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Copied',
            style: AppTypography.bodySm.copyWith(color: AppColors.textPrimary),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    case 'date':
      final ts = entity.value?['timestamp'] as int?;
      if (ts == null) return;
      final due = DateTime.fromMillisecondsSinceEpoch(ts);
      final notifier = ref.read(taskProvider.notifier);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.bgElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          side: BorderSide(color: AppColors.borderDefault, width: 1),
        ),
        builder: (_) => AddToTasksSheet(
          screenshot: screenshot,
          initialDueDate: due,
          onCreate: notifier.addTask,
        ),
      );
      return;
    case 'url':
    case 'qr_url':
      await _promptOpenUrl(context, entity.rawText.trim());
      return;
    case 'phone':
    case 'qr_phone':
      await _showPhoneEntityActions(context, entity.rawText.trim());
      return;
    case 'email':
    case 'qr_email':
      await _promptComposeEmail(context, _parseEmailAddress(entity.rawText));
      return;
    default:
      return;
  }
}

Future<void> _promptOpenUrl(BuildContext context, String raw) async {
  var urlString = raw.trim();
  if (!urlString.startsWith('http://') && !urlString.startsWith('https://')) {
    urlString = 'https://$urlString';
  }
  final uri = Uri.tryParse(urlString);
  if (uri == null || uri.host.isEmpty) return;

  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderDefault, width: 1),
      ),
      title: Text('Open link?', style: AppTypography.headingMd),
      content: Text(
        urlString,
        style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            'Cancel',
            style: AppTypography.labelLg.copyWith(color: AppColors.textMuted),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Open',
            style: AppTypography.labelLg.copyWith(color: AppColors.accentText),
          ),
        ),
      ],
    ),
  );
  if (open != true || !context.mounted) return;
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (_) {}
}

Future<void> _promptComposeEmail(BuildContext context, String address) async {
  if (address.isEmpty) return;
  final uri = Uri(scheme: 'mailto', path: address);

  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderDefault, width: 1),
      ),
      title: Text('Open email app?', style: AppTypography.headingMd),
      content: Text(
        address,
        style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            'Cancel',
            style: AppTypography.labelLg.copyWith(color: AppColors.textMuted),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Open',
            style: AppTypography.labelLg.copyWith(color: AppColors.accentText),
          ),
        ),
      ],
    ),
  );
  if (open != true || !context.mounted) return;
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  } catch (_) {}
}

Future<void> _showPhoneEntityActions(BuildContext context, String raw) async {
  final display = raw.trim();
  if (display.isEmpty) return;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      side: BorderSide(color: AppColors.borderDefault, width: 1),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Container(
              width: 32,
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.borderEmphasis,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.phone_outlined,
              color: AppColors.textSecondary,
              size: 20,
            ),
            title: Text(
              'Call',
              style:
                  AppTypography.bodyMd.copyWith(color: AppColors.textPrimary),
            ),
            subtitle: Text(
              display,
              style: AppTypography.bodySm.copyWith(color: AppColors.textMuted),
            ),
            onTap: () {
              Navigator.pop(ctx);
              _promptCallNumber(context, display);
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.person_add_outlined,
              color: AppColors.textSecondary,
              size: 20,
            ),
            title: Text(
              'Add to contact',
              style:
                  AppTypography.bodyMd.copyWith(color: AppColors.textPrimary),
            ),
            onTap: () async {
              Navigator.pop(ctx);
              await _openNewContactWithPhone(context, display);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> _promptCallNumber(BuildContext context, String raw) async {
  final tel = _telUriBody(raw);
  if (tel.isEmpty) return;

  final call = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderDefault, width: 1),
      ),
      title: Text('Call this number?', style: AppTypography.headingMd),
      content: Text(
        raw,
        style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            'Cancel',
            style: AppTypography.labelLg.copyWith(color: AppColors.textMuted),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Call',
            style: AppTypography.labelLg.copyWith(color: AppColors.accentText),
          ),
        ),
      ],
    ),
  );
  if (call != true || !context.mounted) return;
  final uri = Uri.parse('tel:$tel');
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  } catch (_) {}
}

Future<void> _openNewContactWithPhone(BuildContext context, String raw) async {
  final phone = raw.trim();
  if (phone.isEmpty) return;

  try {
    if (Platform.isAndroid) {
      final digits = _sanitizedPhoneDigits(phone);
      final intent = AndroidIntent(
        action: 'android.intent.action.INSERT',
        type: 'vnd.android.cursor.dir/contact',
        arguments: <String, dynamic>{
          'phone': digits.isNotEmpty ? digits : phone,
        },
      );
      await intent.launch();
      return;
    }
  } catch (_) {}

  await Clipboard.setData(ClipboardData(text: phone));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Phone copied — paste when creating a contact',
          style: AppTypography.bodySm.copyWith(color: AppColors.textPrimary),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class ScreenshotDetailScreen extends ConsumerStatefulWidget {
  final int screenshotId;
  final Task? task;

  const ScreenshotDetailScreen({
    super.key,
    required this.screenshotId,
    this.task,
  });

  @override
  ConsumerState<ScreenshotDetailScreen> createState() =>
      _ScreenshotDetailScreenState();
}

class _ScreenshotDetailScreenState
    extends ConsumerState<ScreenshotDetailScreen> {
  final _cropService = CropService();
  bool _isProcessing = false;
  String _processingLabel = '';

  Future<void> _runSmartCrop(Screenshot screenshot) async {
    await _runCrop(
      screenshot,
      label: 'Finding subject…',
      run: () => _cropService.smartCrop(screenshot.uri),
      onNoSubject: () =>
          _showSnack('No subject detected — try manual crop', isError: false),
    );
  }

  Future<void> _runManualCrop(Screenshot screenshot) async {
    await _runCrop(
      screenshot,
      label: 'Saving…',
      run: () => _cropService.manualCrop(screenshot.uri),
    );
  }

  Future<void> _runCrop(
    Screenshot screenshot, {
    required String label,
    required Future<CropResult> Function() run,
    VoidCallback? onNoSubject,
  }) async {
    setState(() {
      _isProcessing = true;
      _processingLabel = label;
    });

    final result = await run();

    if (!mounted) return;

    if (result == CropResult.success) {
      // Re-run OCR + entity extraction on the new image.
      setState(() => _processingLabel = 'Re-reading text…');
      final ocr = ref.read(ocrServiceProvider);
      final entityService = ref.read(entityServiceProvider);
      final newText = await ocr.extractText(screenshot.uri);
      final newEntities = await entityService.extract(newText);
      final newTag = ocr.autoTag(newText, entities: newEntities);

      await AppDatabase.instance.updateScreenshot(
        screenshot.copyWith(
          extractedText: newText,
          tag: newTag,
          entities: newEntities,
        ),
      );

      // Drop cached pixels so the new image renders.
      PaintingBinding.instance.imageCache
          .evict(FileImage(File(screenshot.uri)));
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      if (!mounted) return;

      ref.invalidate(screenshotDetailProvider(widget.screenshotId));
      // Refresh home grid + downstream consumers (picker, suggestions).
      ref.read(homeProvider.notifier).loadScreenshots();
      ref.invalidate(allScreenshotsProvider);
      ref.invalidate(suggestionsProvider);
    } else if (result == CropResult.noSubjectDetected) {
      onNoSubject?.call();
    } else if (result == CropResult.failed) {
      _showSnack('Crop failed', isError: true);
    }

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _processingLabel = '';
      });
    }
  }

  void _showAddToTasks(Screenshot screenshot) {
    final notifier = ref.read(taskProvider.notifier);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: AppColors.borderDefault, width: 1),
      ),
      builder: (_) => AddToTasksSheet(
        screenshot: screenshot,
        onCreate: notifier.addTask,
      ),
    );
  }

  Future<void> _showAddToStack(Screenshot screenshot) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => StackChooserSheet(screenshot: screenshot),
    );
  }

  void _showSnack(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: AppTypography.bodySm.copyWith(color: AppColors.textPrimary)),
        backgroundColor: isError ? AppColors.error : AppColors.bgElevated,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(screenshotDetailProvider(widget.screenshotId));

    return Scaffold(
      backgroundColor: AppColors.bgElevated,
      body: Stack(
        children: [
          async.when(
            loading: () => const Center(
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppColors.accent,
              ),
            ),
            error: (e, _) => Center(
              child: Text('Error: $e',
                  style: AppTypography.bodyMd.copyWith(color: AppColors.error)),
            ),
            data: (screenshot) {
              if (screenshot == null) {
                return Center(
                  child: Text('Not found',
                      style: AppTypography.bodyMd
                          .copyWith(color: AppColors.textMuted)),
                );
              }
              return _DetailView(
                screenshot: screenshot,
                task: widget.task,
                onSmartCrop: () => _runSmartCrop(screenshot),
                onManualCrop: () => _runManualCrop(screenshot),
                onAddToTasks: () => _showAddToTasks(screenshot),
                onAddToStack: () => _showAddToStack(screenshot),
              );
            },
          ),
          if (_isProcessing) _ProcessingOverlay(label: _processingLabel),
        ],
      ),
    );
  }
}

class _DetailView extends StatefulWidget {
  final Screenshot screenshot;
  final Task? task;
  final VoidCallback onSmartCrop;
  final VoidCallback onManualCrop;
  final VoidCallback onAddToTasks;
  final VoidCallback onAddToStack;

  const _DetailView({
    required this.screenshot,
    this.task,
    required this.onSmartCrop,
    required this.onManualCrop,
    required this.onAddToTasks,
    required this.onAddToStack,
  });

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView> {
  final _sheetController = DraggableScrollableController();

  static const _minSize = 0.25;
  static const _midSize = 0.42;
  static const _topBarH = 52.0;
  static const _imageSheetGap = 24.0;

  // Max sheet fraction: sheet top edge sits flush with the bottom of the top bar.
  double _maxSheetSize(double screenH, double topInset) =>
      ((screenH - topInset - _topBarH) / screenH).clamp(0.0, 0.97);

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  void _onImageDragUpdate(DragUpdateDetails details) {
    if (!_sheetController.isAttached) return;
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final maxSize = _maxSheetSize(screenH, mq.padding.top);
    final delta = -details.delta.dy / screenH;
    _sheetController.jumpTo(
      (_sheetController.size + delta).clamp(_minSize, maxSize),
    );
  }

  void _onImageDragEnd(DragEndDetails details) {
    if (!_sheetController.isAttached) return;
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final maxSize = _maxSheetSize(screenH, mq.padding.top);
    final snapList = [_minSize, _midSize, maxSize];

    final velocity = details.primaryVelocity ?? 0;
    final current = _sheetController.size;

    double target;
    if (velocity < -300) {
      target = snapList.firstWhere(
        (s) => s > current + 0.02,
        orElse: () => maxSize,
      );
    } else if (velocity > 300) {
      target = snapList.reversed.firstWhere(
        (s) => s < current - 0.02,
        orElse: () => _minSize,
      );
    } else {
      target = snapList
          .reduce((a, b) => (a - current).abs() < (b - current).abs() ? a : b);
    }

    _sheetController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final topInset = mq.padding.top;
    final bottomInset = mq.padding.bottom;
    final screenH = mq.size.height;

    final topContentH = topInset + _topBarH;
    final maxSize = _maxSheetSize(screenH, topInset);

    // Tallest the image can be: when sheet is at its minimum.
    final maxImageH = screenH * (1 - _minSize) - topContentH;

    final smartActions =
        SmartActionsService().actionsFor([widget.screenshot], limit: 1);
    final SmartAction? smartAction =
        smartActions.isEmpty ? null : smartActions.first;

    return Stack(
      children: [
        // Image — resizes to fill space above sheet, clamped to ≥ 50% of max height.
        ListenableBuilder(
          listenable: _sheetController,
          builder: (context, _) {
            final fraction =
                _sheetController.isAttached ? _sheetController.size : _midSize;
            final rawH =
                screenH * (1 - fraction) - topContentH - _imageSheetGap;
            final imageH = rawH.clamp(maxImageH * 0.5, maxImageH);

            return Positioned(
              top: topContentH,
              left: 16,
              right: 16,
              height: imageH,
              child: GestureDetector(
                onVerticalDragUpdate: _onImageDragUpdate,
                onVerticalDragEnd: _onImageDragEnd,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _DetailImage(uri: widget.screenshot.uri),
                    if (smartAction != null)
                      Positioned(
                        bottom: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _SmartActionCTA(
                            action: smartAction,
                            onTap: () => SmartActionsService()
                                .execute(smartAction, context),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),

        // Bottom sheet — stops at the top bar when fully expanded.
        DraggableScrollableSheet(
          controller: _sheetController,
          initialChildSize: _midSize,
          minChildSize: _minSize,
          maxChildSize: maxSize,
          snap: true,
          snapSizes: const [_midSize],
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.bgBase,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomInset + 24),
                  child: _InfoPanel(
                    screenshot: widget.screenshot,
                    task: widget.task,
                  ),
                ),
              ),
            );
          },
        ),

        // Floating top bar — always above everything.
        Positioned(
          top: topInset,
          left: 18,
          right: 18,
          height: _topBarH,
          child: Row(
            children: [
              _CircleButton(
                icon: Icons.arrow_back_rounded,
                onTap: () => context.pop(),
              ),
              const Spacer(),
              _KebabMenuButton(
                screenshot: widget.screenshot,
                onSmartCrop: widget.onSmartCrop,
                onManualCrop: widget.onManualCrop,
                onAddToTasks: widget.onAddToTasks,
                onAddToStack: widget.onAddToStack,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.borderDefault, width: 1),
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 18),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: button) : button;
  }
}

// ── Kebab menu ────────────────────────────────────────────────────────────────

enum _MenuAction { editNote, addToTasks, addToStack, smartCrop, crop }

class _KebabMenuButton extends StatelessWidget {
  final Screenshot screenshot;
  final VoidCallback onSmartCrop;
  final VoidCallback onManualCrop;
  final VoidCallback onAddToTasks;
  final VoidCallback onAddToStack;

  const _KebabMenuButton({
    required this.screenshot,
    required this.onSmartCrop,
    required this.onManualCrop,
    required this.onAddToTasks,
    required this.onAddToStack,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuAction>(
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.borderDefault, width: 1),
        ),
        child: const Icon(
          Icons.more_vert_rounded,
          color: AppColors.textPrimary,
          size: 18,
        ),
      ),
      color: AppColors.bgElevated,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderDefault, width: 1),
      ),
      onSelected: (action) {
        switch (action) {
          case _MenuAction.editNote:
            context.push('/notes/edit/${screenshot.id}');
          case _MenuAction.addToTasks:
            onAddToTasks();
          case _MenuAction.addToStack:
            onAddToStack();
          case _MenuAction.smartCrop:
            onSmartCrop();
          case _MenuAction.crop:
            onManualCrop();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _MenuAction.editNote,
          child: _MenuRow(
            icon: screenshot.isNote
                ? Icons.edit_note_rounded
                : Icons.notes_rounded,
            label: screenshot.isNote ? 'Edit note' : 'Convert to note',
          ),
        ),
        const PopupMenuItem(
          value: _MenuAction.addToTasks,
          child: _MenuRow(
            icon: Icons.playlist_add_rounded,
            label: 'Add to Tasks',
          ),
        ),
        const PopupMenuItem(
          value: _MenuAction.addToStack,
          child: _MenuRow(
            icon: Icons.layers_rounded,
            label: 'Add to Stack',
          ),
        ),
        const PopupMenuItem(
          value: _MenuAction.smartCrop,
          child: _MenuRow(
            icon: Icons.auto_awesome_outlined,
            label: 'Smart crop',
          ),
        ),
        const PopupMenuItem(
          value: _MenuAction.crop,
          child: _MenuRow(icon: Icons.crop_rounded, label: 'Crop'),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Text(
          label,
          style: AppTypography.bodyMd.copyWith(color: AppColors.textPrimary),
        ),
      ],
    );
  }
}

// ── Smart action CTA ──────────────────────────────────────────────────────────

class _SmartActionCTA extends StatelessWidget {
  final SmartAction action;
  final VoidCallback onTap;

  const _SmartActionCTA({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PrimaryButton(
      label: action.label,
      icon: action.icon,
      onPressed: onTap,
      size: PrimaryButtonSize.md,
      shape: PrimaryButtonShape.pill,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
      extraShadow: [
        BoxShadow(
          color: AppColors.accent.withValues(alpha: 0.42),
          blurRadius: 20,
          spreadRadius: 2,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: AppColors.accent.withValues(alpha: 0.15),
          blurRadius: 12,
          spreadRadius: 0,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}

// ── Processing overlay ────────────────────────────────────────────────────────

class _ProcessingOverlay extends StatelessWidget {
  final String label;
  const _ProcessingOverlay({required this.label});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.shadowStrong,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderDefault, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Text(label,
                    style: AppTypography.bodyMd
                        .copyWith(color: AppColors.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final Screenshot screenshot;
  final Task? task;

  const _InfoPanel({required this.screenshot, this.task});

  @override
  Widget build(BuildContext context) {
    final pillEntities = _filterAndDedupeEntityPills(screenshot.entities);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.bgBase,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(26, 12, 26, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 3,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.borderEmphasis,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header — category + captured time
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              children: [
                TagBadge(tag: screenshot.tag),
                const SizedBox(width: 12),
                Text('·',
                    style: AppTypography.labelMd
                        .copyWith(color: AppColors.textMuted)),
                const SizedBox(width: 12),
                Text(
                  DateFormat('MMM d, yyyy · HH:mm')
                      .format(screenshot.createdAt),
                  style:
                      AppTypography.monoMd.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),

          if (task != null) ...[
            _TaskCard(task: task!),
            _divider(),
          ],

          if (screenshot.aiSummary != null &&
              screenshot.aiSummary!.isNotEmpty) ...[
            _AiSummarySection(text: screenshot.aiSummary!),
            _divider(),
          ],

          if (pillEntities.isNotEmpty) ...[
            _EntitiesSection(
              screenshot: screenshot,
              entities: pillEntities,
            ),
            _divider(),
          ],

          if (screenshot.extractedText.isNotEmpty) ...[
            _ExtractedTextSection(text: screenshot.extractedText),
          ],
        ],
      ),
    );
  }

  Widget _divider() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 2),
        child: Divider(color: AppColors.borderSubtle, height: 1),
      );
}

class _AiSummarySection extends StatelessWidget {
  final String text;
  const _AiSummarySection({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_outlined,
                  color: AppColors.textMuted, size: 16),
              const SizedBox(width: 12),
              Text('AI Summary',
                  style: AppTypography.labelMd
                      .copyWith(color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: AppTypography.bodyMd.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _EntitiesSection extends ConsumerWidget {
  final Screenshot screenshot;
  final List<ExtractedEntity> entities;

  const _EntitiesSection({
    required this.screenshot,
    required this.entities,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_outlined,
                  color: AppColors.textMuted, size: 16),
              const SizedBox(width: 12),
              Text('Detected',
                  style: AppTypography.labelMd
                      .copyWith(color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in entities)
                _EntityChip(
                  entity: e,
                  onTap: _entityPillIsInteractive(e.type)
                      ? () => _handleEntityPillTap(
                            context,
                            ref,
                            screenshot,
                            e,
                          )
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntityChip extends StatelessWidget {
  final ExtractedEntity entity;
  final VoidCallback? onTap;

  const _EntityChip({required this.entity, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgSurface,
      shape: const StadiumBorder(
        side: BorderSide(color: AppColors.borderDefault, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconFor(entity.type),
                  size: 12, color: AppColors.accentText),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  _displayText(entity),
                  style: AppTypography.labelSm
                      .copyWith(color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'money':
        return Icons.payments_outlined;
      case 'date':
        return Icons.calendar_today_outlined;
      case 'url':
      case 'qr_url':
        return Icons.link_rounded;
      case 'phone':
      case 'qr_phone':
        return Icons.phone_outlined;
      case 'flight':
        return Icons.flight_takeoff_outlined;
      case 'email':
      case 'qr_email':
        return Icons.alternate_email_rounded;
      case 'address':
        return Icons.location_on_outlined;
      case 'tracking':
        return Icons.local_shipping_outlined;
      case 'iban':
      case 'payment_card':
        return Icons.credit_card_rounded;
      case 'isbn':
        return Icons.menu_book_outlined;
      case 'portrait':
        return Icons.person_outline_rounded;
      case 'qr_payment':
        return Icons.payments_rounded;
      case 'qr_wifi':
        return Icons.wifi_rounded;
      case 'qr_contact':
        return Icons.person_add_rounded;
      case 'qr':
        return Icons.qr_code_rounded;
    }
    return Icons.label_outline_rounded;
  }

  String _displayText(ExtractedEntity e) {
    switch (e.type) {
      case 'flight':
        final airline = e.value?['airline'] as String?;
        final number = e.value?['number'] as String?;
        if (airline != null && number != null) return '$airline$number';
        return e.rawText;
      case 'date':
        final ts = e.value?['timestamp'] as int?;
        if (ts != null) {
          final dt = DateTime.fromMillisecondsSinceEpoch(ts);
          return DateFormat('MMM d, yyyy').format(dt);
        }
        return e.rawText;
    }
    return e.rawText;
  }
}

class _TaskCard extends StatelessWidget {
  final Task task;
  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final intentColor = _intentColor(task.intent);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_intentIcon(task.intent), color: AppColors.textMuted, size: 16),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text('Task',
                style:
                    AppTypography.labelMd.copyWith(color: AppColors.textMuted)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: AppTypography.labelLg.copyWith(
                    color: task.isCompleted
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                    decoration:
                        task.isCompleted ? TextDecoration.lineThrough : null,
                    decorationColor: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    if (task.intent.label.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: intentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: intentColor.withValues(alpha: 0.3),
                              width: 1),
                        ),
                        child: Text(task.intent.label,
                            style: AppTypography.labelSm
                                .copyWith(color: intentColor)),
                      ),
                      if (task.dueDate != null) const SizedBox(width: 6),
                    ],
                    if (task.dueDate != null)
                      Text(
                        DateFormat('MMM d, yyyy · HH:mm').format(task.dueDate!),
                        style: AppTypography.monoSm,
                      ),
                    if (task.isCompleted) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: AppColors.accent.withValues(alpha: 0.3),
                              width: 1),
                        ),
                        child: Text('Done',
                            style: AppTypography.labelSm
                                .copyWith(color: AppColors.accent)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _intentIcon(TaskIntent intent) {
    switch (intent) {
      case TaskIntent.event:
        return Icons.calendar_today_outlined;
      case TaskIntent.visitLater:
        return Icons.link_rounded;
      case TaskIntent.payLater:
        return Icons.payments_outlined;
      case TaskIntent.readLater:
        return Icons.menu_book_outlined;
      case TaskIntent.buyLater:
        return Icons.shopping_bag_outlined;
      case TaskIntent.task:
        return Icons.task_alt_rounded;
    }
  }

  Color _intentColor(TaskIntent intent) {
    switch (intent) {
      case TaskIntent.event:
        return AppColors.tagEvent;
      case TaskIntent.visitLater:
        return AppColors.tagLink;
      case TaskIntent.payLater:
        return AppColors.tagShopping;
      case TaskIntent.readLater:
        return AppColors.tagNote;
      case TaskIntent.buyLater:
        return AppColors.tagShopping;
      case TaskIntent.task:
        return AppColors.accent;
    }
  }
}

class _ExtractedTextSection extends StatefulWidget {
  final String text;
  const _ExtractedTextSection({required this.text});

  @override
  State<_ExtractedTextSection> createState() => _ExtractedTextSectionState();
}

class _ExtractedTextSectionState extends State<_ExtractedTextSection> {
  bool _expanded = false;
  bool _justCopied = false;

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _justCopied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _justCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.text.length > 200
        ? '${widget.text.substring(0, 200)}…'
        : widget.text;
    final needsExpansion = widget.text.length > 200;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.text_snippet_outlined,
                  color: AppColors.textMuted, size: 16),
              const SizedBox(width: 12),
              Text('Extracted text',
                  style: AppTypography.labelMd
                      .copyWith(color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderDefault, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: _IconAction(
                    icon:
                        _justCopied ? Icons.check_rounded : Icons.copy_rounded,
                    label: _justCopied ? 'Copied' : 'Copy',
                    onTap: _copyAll,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _expanded ? widget.text : preview,
                  style: AppTypography.monoMd,
                  cursorColor: AppColors.accent,
                  selectionControls: MaterialTextSelectionControls(),
                ),
                if (needsExpansion) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Text(
                        _expanded ? 'Show less' : 'Show more',
                        style: AppTypography.labelSm
                            .copyWith(color: AppColors.accentText),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _IconAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.accentText),
          const SizedBox(width: 4),
          Text(label,
              style:
                  AppTypography.labelSm.copyWith(color: AppColors.accentText)),
        ],
      ),
    );
  }
}

class _DetailImage extends StatelessWidget {
  final String uri;
  const _DetailImage({required this.uri});

  @override
  Widget build(BuildContext context) {
    final isLocal = !uri.startsWith('http');
    final image = isLocal
        ? Image.file(
            File(uri),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox(
              width: 260,
              height: 180,
              child: ColoredBox(color: AppColors.bgSurface),
            ),
          )
        : Image.network(
            uri,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox(
              width: 260,
              height: 180,
              child: ColoredBox(color: AppColors.bgSurface),
            ),
          );

    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(80),
            border: Border.all(color: AppColors.borderDefault, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: image,
        ),
      ),
    );
  }
}
