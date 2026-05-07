import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/screenshot_model.dart';
import '../../../core/models/stack_model.dart' as sm;
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../stacks_provider.dart';

/// Bottom sheet that lets the user pick an existing stack or create a new one,
/// then adds [screenshot] to the chosen stack.
class StackChooserSheet extends ConsumerStatefulWidget {
  final Screenshot screenshot;

  const StackChooserSheet({super.key, required this.screenshot});

  @override
  ConsumerState<StackChooserSheet> createState() => _StackChooserSheetState();
}

class _StackChooserSheetState extends ConsumerState<StackChooserSheet> {
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final stacks = ref.watch(stacksProvider).stacks;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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

            Text('Add to Stack',
                style: AppTypography.headingSm
                    .copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('Choose a stack or create a new one',
                style:
                    AppTypography.bodySm.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 16),

            // New Stack option
            _StackTile(
              icon: Icons.add_rounded,
              name: 'New Stack',
              isCreate: true,
              onTap: _adding ? null : () => _createAndAdd(context, stacks),
            ),

            if (stacks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Divider(color: AppColors.borderDefault, height: 1),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: stacks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, i) {
                    final s = stacks[i];
                    return _StackTile(
                      icon: Icons.layers_rounded,
                      name: s.name,
                      subtitle: '${s.screenshots.length} screenshots',
                      onTap: _adding ? null : () => _addToStack(s),
                    );
                  },
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'No stacks yet — create your first one above',
                  style:
                      AppTypography.bodySm.copyWith(color: AppColors.textMuted),
                ),
              ),
            ],

            if (_adding) ...[
              const SizedBox(height: 16),
              const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppColors.accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addToStack(sm.Stack stack) async {
    setState(() => _adding = true);
    await ref
        .read(stacksProvider.notifier)
        .addScreenshot(stack.id!, widget.screenshot.id!);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added to "${stack.name}"'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _createAndAdd(BuildContext context, List<sm.Stack> existing) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.borderDefault, width: 1),
        ),
        title: Text('New Stack', style: AppTypography.headingMd),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: AppTypography.bodyMd.copyWith(color: AppColors.textPrimary),
          cursorColor: AppColors.accent,
          decoration: InputDecoration(
            hintText: 'Stack name',
            hintStyle:
                AppTypography.bodyMd.copyWith(color: AppColors.textMuted),
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style:
                    AppTypography.labelLg.copyWith(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: Text('Create',
                style: AppTypography.labelLg
                    .copyWith(color: AppColors.accentText)),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);

    if (name == null || name.isEmpty || !mounted) return;

    setState(() => _adding = true);
    await ref.read(stacksProvider.notifier).createStack(name);

    // Find the newly created stack by name (last one with this name)
    await ref.read(stacksProvider.notifier).load();
    final updated = ref.read(stacksProvider).stacks;
    final newStack =
        updated.where((s) => s.name == name).lastOrNull;

    if (newStack != null) {
      await ref
          .read(stacksProvider.notifier)
          .addScreenshot(newStack.id!, widget.screenshot.id!);
    }

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added to "$name"'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _StackTile extends StatelessWidget {
  final IconData icon;
  final String name;
  final String? subtitle;
  final bool isCreate;
  final VoidCallback? onTap;

  const _StackTile({
    required this.icon,
    required this.name,
    this.subtitle,
    this.isCreate = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isCreate
              ? AppColors.accent.withValues(alpha: 0.08)
              : AppColors.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCreate ? AppColors.accent.withValues(alpha: 0.3) : AppColors.borderDefault,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isCreate ? AppColors.accent : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppTypography.bodyMd.copyWith(
                      color: isCreate
                          ? AppColors.accentText
                          : AppColors.textPrimary,
                      fontWeight:
                          isCreate ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
