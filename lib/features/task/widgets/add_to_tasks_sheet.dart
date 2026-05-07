import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/screenshot_model.dart';
import '../../../core/models/task_model.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../shared/widgets/primary_button.dart';
import '../task_prefill.dart';

enum _FormVariant { generic, event, simple }

class AddToTasksSheet extends StatefulWidget {
  final Screenshot? screenshot;
  final Task? existingTask;
  /// When adding from a screenshot, overrides prefilled due date (e.g. tapped date pill).
  final DateTime? initialDueDate;
  final void Function(Task) onCreate;
  final void Function(Task)? onUpdate;

  const AddToTasksSheet({
    super.key,
    this.screenshot,
    this.existingTask,
    this.initialDueDate,
    required this.onCreate,
    this.onUpdate,
  });

  bool get isEditing => existingTask != null;

  @override
  State<AddToTasksSheet> createState() => _AddToTasksSheetState();
}

class _AddToTasksSheetState extends State<AddToTasksSheet> {
  late final TextEditingController _titleCtrl;
  late final _FormVariant _variant;
  late final TaskIntent _intent;
  late final String? _contextLabel;

  DateTime? _dueDate;
  NotifyOption _notifyOption = NotifyOption.none;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    if (widget.isEditing) {
      final t = widget.existingTask!;
      _intent = t.intent;
      _dueDate = t.dueDate;
      _notifyOption = t.notifyOption;
      _titleCtrl = TextEditingController(text: t.title);
      _contextLabel = null;
      _variant =
          t.intent == TaskIntent.event ? _FormVariant.event : _FormVariant.generic;
    } else if (widget.screenshot == null) {
      _variant = _FormVariant.generic;
      _intent = TaskIntent.task;
      _contextLabel = null;
      _titleCtrl = TextEditingController();
    } else {
      final prefill = TaskPrefill.fromScreenshot(widget.screenshot!);
      _intent = prefill.intent;
      _dueDate = widget.initialDueDate ?? prefill.dueDate;

      if (widget.screenshot!.tag == ScreenshotTag.event) {
        _variant = _FormVariant.event;
        _contextLabel = null;
      } else {
        _variant = _FormVariant.simple;
        _contextLabel = prefill.url ?? prefill.amount;
      }

      _titleCtrl = TextEditingController(text: prefill.title);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_isSaving) return;
    
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    
    setState(() => _isSaving = true);

    if (widget.isEditing) {
      final updated = widget.existingTask!.copyWith(
        title: title,
        dueDate: _dueDate,
        notifyOption: _notifyOption,
      );
      widget.onUpdate?.call(updated);
    } else {
      widget.onCreate(Task(
        screenshotId: widget.screenshot?.id ?? 0,
        screenshotUri: widget.screenshot?.uri ?? '',
        title: title,
        intent: _intent,
        dueDate: _dueDate,
        notifyOption: _notifyOption,
        createdAt: DateTime.now(),
      ));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 32,
              height: 3,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.borderEmphasis,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Text(
            widget.isEditing
                ? 'Edit Task'
                : (_variant == _FormVariant.generic ? 'New Task' : 'Add to Tasks'),
            style:
                AppTypography.headingSm.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),

          // Title field — Todoist-style: no label, borderless, large hint
          TextField(
            controller: _titleCtrl,
            autofocus: _titleCtrl.text.isEmpty,
            style: AppTypography.bodyLg.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: _variant == _FormVariant.event
                  ? 'Event name'
                  : 'What needs to be done?',
              hintStyle:
                  AppTypography.bodyLg.copyWith(color: AppColors.textMuted),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),

          // Context label for screenshot-sourced tasks
          if (_variant == _FormVariant.simple &&
              _contextLabel != null &&
              _contextLabel.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.borderDefault, width: 1),
              ),
              child: Text(
                _contextLabel,
                style: AppTypography.monoMd
                    .copyWith(color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Quick-action chip row
          _ChipRow(
            dueDate: _dueDate,
            notifyOption: _notifyOption,
            onPickDate: _pickDateTime,
            onPickNotify: _pickNotify,
          ),
          const SizedBox(height: 20),

          // Submit button
          PrimaryButton(
            label: widget.isEditing ? 'Save Changes' : 'Create Task',
            onPressed: _isSaving ? null : _submit,
            loading: _isSaving,
            expanded: true,
            size: PrimaryButtonSize.lg,
          ),
        ],
      ),
    );
  }

  Future<void> _pickNotify() async {
    final result = await showDialog<NotifyOption>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Remind me',
            style: AppTypography.headingSm
                .copyWith(color: AppColors.textPrimary)),
        children: NotifyOption.values
            .map((o) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, o),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      o.label,
                      style: AppTypography.bodyMd.copyWith(
                        color: o == _notifyOption
                            ? AppColors.accent
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
    if (result != null && mounted) {
      setState(() => _notifyOption = result);
    }
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 5)),
      builder: (ctx, child) => _darkPickerTheme(ctx, child),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _dueDate != null
          ? TimeOfDay(hour: _dueDate!.hour, minute: _dueDate!.minute)
          : TimeOfDay.now(),
      builder: (ctx, child) => _darkPickerTheme(ctx, child),
    );
    if (!mounted) return;

    setState(() {
      _dueDate = time != null
          ? DateTime(date.year, date.month, date.day, time.hour, time.minute)
          : DateTime(date.year, date.month, date.day);
    });
  }

  Widget _darkPickerTheme(BuildContext context, Widget? child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          onPrimary: Colors.white,
          surface: AppColors.bgElevated,
          onSurface: AppColors.textPrimary,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: AppColors.bgElevated,
        ),
      ),
      child: child!,
    );
  }

}

class _ChipRow extends StatelessWidget {
  final DateTime? dueDate;
  final NotifyOption notifyOption;
  final VoidCallback onPickDate;
  final VoidCallback onPickNotify;

  const _ChipRow({
    required this.dueDate,
    required this.notifyOption,
    required this.onPickDate,
    required this.onPickNotify,
  });

  @override
  Widget build(BuildContext context) {
    final dateLabel = dueDate != null
        ? DateFormat('MMM d, h:mm a').format(dueDate!)
        : 'No date';
    final notifyLabel = notifyOption.label.isEmpty ? 'None' : notifyOption.label;
    final hasDate = dueDate != null;
    final hasNotify = notifyOption != NotifyOption.none;

    return Row(
      children: [
        _Chip(
          icon: Icons.calendar_today_outlined,
          label: dateLabel,
          isActive: hasDate,
          onTap: onPickDate,
        ),
        const SizedBox(width: 8),
        _Chip(
          icon: Icons.notifications_none_rounded,
          label: notifyLabel,
          isActive: hasNotify,
          onTap: onPickNotify,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _Chip({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.accent.withValues(alpha: 0.12)
              : AppColors.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.accent.withValues(alpha: 0.4) : AppColors.borderDefault,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: isActive ? AppColors.accent : AppColors.textMuted),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTypography.labelMd.copyWith(
                color: isActive ? AppColors.accent : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
