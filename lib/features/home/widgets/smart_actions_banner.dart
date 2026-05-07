import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/services/smart_actions_service.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../shared/widgets/primary_button.dart';

class SmartActionsBanner extends StatelessWidget {
  final List<SmartAction> actions;
  final void Function(SmartAction) onExecute;
  final void Function(SmartAction) onOpen;
  final void Function(SmartAction) onRemove;

  const SmartActionsBanner({
    super.key,
    required this.actions,
    required this.onExecute,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
            child: Text('Actions',
                style: AppTypography.labelLg
                    .copyWith(color: AppColors.textSecondary)),
          ),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              itemCount: actions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final a = actions[i];
                return _ActionCard(
                  action: a,
                  onExecute: () => onExecute(a),
                  onOpen: () => onOpen(a),
                  onRemove: () => _confirmRemove(context, a),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context, SmartAction action) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: AppColors.borderDefault, width: 1),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 32,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.borderEmphasis,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Remove action?',
                  style: AppTypography.headingSm
                      .copyWith(color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(
                'This will hide "${action.title}" from your actions.',
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    onRemove(action);
                  },
                  child: Text('Remove',
                      style: AppTypography.bodyLg.copyWith(
                          color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel',
                      style: AppTypography.bodyLg
                          .copyWith(color: AppColors.textMuted)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final SmartAction action;
  final VoidCallback onExecute;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _ActionCard({
    required this.action,
    required this.onExecute,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Stack(
        children: [
          Container(
            width: 290,
            padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderDefault, width: 1),
            ),
            child: Row(
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 56,
                    height: 76,
                    child: _Thumb(uri: action.screenshot.uri),
                  ),
                ),
                const SizedBox(width: 12),
                // Title + subtitle + CTA
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        action.title,
                        style: AppTypography.labelLg
                            .copyWith(color: AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        action.subtitle,
                        style: AppTypography.labelSm
                            .copyWith(color: AppColors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      PrimaryButton(
                        label: action.label,
                        icon: action.icon,
                        onPressed: onExecute,
                        size: PrimaryButtonSize.sm,
                  
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Remove button — top-right corner (inside card)
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.bgOverlay,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: AppColors.borderEmphasis, width: 1),
                ),
                child: const Icon(Icons.close_rounded,
                    size: 12, color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String uri;
  const _Thumb({required this.uri});

  @override
  Widget build(BuildContext context) {
    if (uri.startsWith('http')) {
      return Image.network(uri,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Container(color: AppColors.bgElevated));
    }
    return Image.file(File(uri),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: AppColors.bgElevated));
  }
}
