import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/services/suggestion_service.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../shared/widgets/primary_button.dart';

class SuggestionCard extends StatelessWidget {
  final StackSuggestion suggestion;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const SuggestionCard({
    super.key,
    required this.suggestion,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final previews = suggestion.screenshots.map((s) => s.uri).toList();

    return Container(
      width: 155,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderDefault, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Fan collage + dismiss + count
          Stack(
            children: [
              SizedBox(
                height: 86,
                child: _FanCollage(uris: previews),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: onDismiss,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 12, color: Colors.white),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${suggestion.screenshots.length}',
                    style: AppTypography.monoSm
                        .copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.name,
                  style: AppTypography.labelLg
                      .copyWith(color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                PrimaryButton(
                  label: 'Create stack',
                  onPressed: onAccept,
                  expanded: true,
                  size: PrimaryButtonSize.sm,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FanCollage extends StatelessWidget {
  final List<String> uris;
  const _FanCollage({required this.uris});

  static const _angles = [0.0, 0.12, 0.22];

  @override
  Widget build(BuildContext context) {
    final previews = uris.take(3).toList();
    if (previews.isEmpty) {
      return Container(
        color: AppColors.bgElevated,
        child: const Center(
          child: Icon(Icons.photo_library_outlined,
              color: AppColors.textMuted, size: 20),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final cardW = w * 0.72;
        final cardH = h * 0.86;

        return Stack(
          alignment: Alignment.center,
          children: [
            Container(color: AppColors.bgElevated),
            for (int i = previews.length - 1; i >= 0; i--)
              Transform.rotate(
                angle: _angles[i],
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: cardW,
                  height: cardH,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _Thumb(uri: previews[i]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  final String uri;
  const _Thumb({required this.uri});

  @override
  Widget build(BuildContext context) {
    if (uri.startsWith('http')) {
      return Image.network(
        uri,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: AppColors.bgElevated),
      );
    }
    return Image.file(
      File(uri),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: AppColors.bgElevated),
    );
  }
}
