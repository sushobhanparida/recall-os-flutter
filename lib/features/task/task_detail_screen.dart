import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/models/task_model.dart';
import 'task_provider.dart';
import 'widgets/add_to_tasks_sheet.dart';

class TaskDetailScreen extends ConsumerWidget {
  final int taskId;

  const TaskDetailScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(taskProvider);
    final notifier = ref.read(taskProvider.notifier);

    final task = state.tasks.where((t) => t.id == taskId).firstOrNull;

    if (task == null) {
      return Scaffold(
        backgroundColor: AppColors.bgBase,
        appBar: AppBar(backgroundColor: AppColors.bgBase),
        body: const Center(
          child: Text('Task not found'),
        ),
      );
    }

    void showEditSheet() {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.bgElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          side: BorderSide(color: AppColors.borderDefault, width: 1),
        ),
        builder: (_) => AddToTasksSheet(
          existingTask: task,
          onCreate: (_) {},
          onUpdate: notifier.updateTask,
        ),
      );
    }

    void confirmDelete() {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.bgElevated,
          title: Text('Delete task?',
              style: AppTypography.headingSm
                  .copyWith(color: AppColors.textPrimary)),
          content: Text('This cannot be undone.',
              style: AppTypography.bodyMd
                  .copyWith(color: AppColors.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: AppTypography.labelLg
                      .copyWith(color: AppColors.textMuted)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                notifier.deleteTask(task.id!);
                context.pop();
              },
              child: Text('Delete',
                  style:
                      AppTypography.labelLg.copyWith(color: AppColors.error)),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        actions: [
          PopupMenuButton<String>(
            color: AppColors.bgElevated,
            icon: const Icon(Icons.more_vert_rounded,
                color: AppColors.textPrimary),
            onSelected: (v) {
              if (v == 'edit') showEditSheet();
              if (v == 'delete') confirmDelete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Text('Edit',
                    style: AppTypography.bodyMd
                        .copyWith(color: AppColors.textPrimary)),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete',
                    style: AppTypography.bodyMd
                        .copyWith(color: AppColors.error)),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                children: [
                  // Intent pill (hidden for plain tasks)
                  if (task.intent != TaskIntent.task) ...[
                    _IntentPill(intent: task.intent),
                    const SizedBox(height: 12),
                  ],

                  // Title
                  Text(
                    task.title,
                    style: AppTypography.headingMd
                        .copyWith(color: AppColors.textPrimary),
                  ),

                  const SizedBox(height: 24),

                  // Screenshot thumbnail
                  if (task.screenshotUri.isNotEmpty) ...[
                    _SectionLabel('Source screenshot'),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: task.screenshotId != 0
                          ? () => context.push(
                              '/screenshot/${task.screenshotId}',
                              extra: task)
                          : null,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _ScreenshotThumb(uri: task.screenshotUri),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Date / time
                  if (task.dueDate != null) ...[
                    _DetailRow(
                      icon: Icons.calendar_today_outlined,
                      label: DateFormat('MMM d, yyyy · h:mm a')
                          .format(task.dueDate!),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Notify
                  if (task.notifyOption != NotifyOption.none) ...[
                    _DetailRow(
                      icon: Icons.notifications_none_rounded,
                      label: task.notifyOption.label,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),

            // Mark completed button
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () {
                    notifier.toggleComplete(task);
                    if (!task.isCompleted) context.pop();
                  },
                  icon: Icon(
                    task.isCompleted
                        ? Icons.undo_rounded
                        : Icons.check_rounded,
                    size: 16,
                  ),
                  label: Text(
                    task.isCompleted ? 'Mark incomplete' : 'Mark completed',
                    style: AppTypography.labelLg,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: task.isCompleted
                        ? AppColors.bgSurface
                        : AppColors.accent,
                    foregroundColor: task.isCompleted
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTypography.labelMd.copyWith(color: AppColors.textMuted),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 12),
        Text(
          label,
          style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _IntentPill extends StatelessWidget {
  final TaskIntent intent;
  const _IntentPill({required this.intent});

  @override
  Widget build(BuildContext context) {
    final color = _color(intent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        intent.label,
        style: AppTypography.labelSm.copyWith(color: color),
      ),
    );
  }

  static Color _color(TaskIntent intent) {
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
        return AppColors.textMuted;
    }
  }
}

class _ScreenshotThumb extends StatelessWidget {
  final String uri;
  const _ScreenshotThumb({required this.uri});

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (uri.startsWith('http')) {
      image = Image.network(uri,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 160,
          errorBuilder: (_, __, ___) => _placeholder());
    } else {
      image = Image.file(File(uri),
          fit: BoxFit.cover,
          width: double.infinity,
          height: 160,
          errorBuilder: (_, __, ___) => _placeholder());
    }
    return image;
  }

  Widget _placeholder() {
    return Container(
      width: double.infinity,
      height: 160,
      color: AppColors.bgSurface,
      child: const Icon(Icons.image_outlined,
          color: AppColors.textMuted, size: 32),
    );
  }
}
