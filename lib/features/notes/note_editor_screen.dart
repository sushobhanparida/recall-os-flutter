import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/app_database.dart';
import '../../core/models/screenshot_model.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../home/home_provider.dart';
import '../home/widgets/notes_view.dart';

/// Edit and save the OCR text as a user note. The screenshot's `noteText`
/// gets persisted; the original `extractedText` is left untouched.
class NoteEditorScreen extends ConsumerStatefulWidget {
  final int screenshotId;

  const NoteEditorScreen({super.key, required this.screenshotId});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  Screenshot? _screenshot;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _ctrl;
  bool _loading = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _ctrl = TextEditingController();
    void updateDirty() {
      final titleChanged = _titleCtrl.text != (_screenshot?.noteTitle ?? '');
      final textChanged = _ctrl.text != (_screenshot?.noteText ?? _screenshot?.extractedText ?? '');
      final next = titleChanged || textChanged;
      if (next != _dirty) setState(() => _dirty = next);
    }

    _titleCtrl.addListener(updateDirty);
    _ctrl.addListener(updateDirty);
    _load();
  }

  Future<void> _load() async {
    final s = await AppDatabase.instance.getScreenshotById(widget.screenshotId);
    if (!mounted) return;
    if (s == null) {
      context.pop();
      return;
    }
    setState(() {
      _screenshot = s;
      _titleCtrl.text = s.noteTitle ?? '';
      _ctrl.text = s.noteText ?? s.extractedText;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = _screenshot;
    if (s == null) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Note is empty'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    await AppDatabase.instance.updateScreenshot(
      s.copyWith(noteTitle: _titleCtrl.text.trim(), noteText: text),
    );
    if (!mounted) return;
    // Refresh consumers so the new note appears immediately.
    ref.read(homeProvider.notifier).loadScreenshots();
    // ignore: unused_result
    ref.refresh(savedNotesProvider);
    context.go('/home');
  }

  Future<void> _delete() async {
    final s = _screenshot;
    if (s == null || !s.isNote) return;
    await AppDatabase.instance.updateScreenshot(
      s.copyWith(clearNote: true),
    );
    if (!mounted) return;
    ref.read(homeProvider.notifier).loadScreenshots();
    // ignore: unused_result
    ref.refresh(savedNotesProvider);
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppColors.accent,
                ),
              )
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final s = _screenshot!;
    return Column(
      children: [
        // Top bar
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => context.pop(),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.borderDefault, width: 1),
                  ),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: AppColors.textPrimary, size: 18),
                ),
              ),
              const Spacer(),
              if (s.isNote) ...[
                _PillButton(
                  label: 'Delete',
                  icon: Icons.delete_outline_rounded,
                  onTap: _delete,
                  destructive: true,
                ),
                const SizedBox(width: 8),
              ],
              _PillButton(
                label: s.isNote ? 'Save' : 'Save note',
                icon: Icons.check_rounded,
                onTap: _save,
                primary: true,
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Source preview
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.borderDefault, width: 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: s.uri.startsWith('http')
                        ? Image.network(s.uri, fit: BoxFit.contain)
                        : Image.file(File(s.uri), fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Note title',
                    style: AppTypography.labelMd
                        .copyWith(color: AppColors.textMuted)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.borderDefault, width: 1),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _titleCtrl,
                    cursorColor: AppColors.accent,
                    style: AppTypography.bodyMd
                        .copyWith(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Enter a note title',
                      hintStyle: AppTypography.bodyMd
                          .copyWith(color: AppColors.textMuted),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 0),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Note text',
                    style: AppTypography.labelMd
                        .copyWith(color: AppColors.textMuted)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.borderDefault, width: 1),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _ctrl,
                    maxLines: null,
                    minLines: 8,
                    cursorColor: AppColors.accent,
                    style: AppTypography.bodyMd
                        .copyWith(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Write or edit the note…',
                      hintStyle: AppTypography.bodyMd
                          .copyWith(color: AppColors.textMuted),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_dirty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Unsaved changes',
                        style: AppTypography.labelSm
                            .copyWith(color: AppColors.warning)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  final bool destructive;

  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = destructive
        ? AppColors.errorMuted
        : primary
            ? AppColors.accent
            : AppColors.bgSurface;
    final fg = destructive
        ? AppColors.error
        : primary
            ? AppColors.textPrimary
            : AppColors.textPrimary;
    final border = destructive
        ? AppColors.error.withValues(alpha: 0.3)
        : primary
            ? Colors.transparent
            : AppColors.borderDefault;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(label,
                style: AppTypography.labelMd.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}
