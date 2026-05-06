import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/models/stack_model.dart' as stack_model;

class StackCard extends StatelessWidget {
  final stack_model.Stack stack;
  final VoidCallback onTap;

  const StackCard({
    super.key,
    required this.stack,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderDefault, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cover image
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Cover(stack: stack),
                  // Gradient overlay
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.5),
                        ],
                        stops: const [0.5, 1.0],
                      ),
                    ),
                  ),
                  // Count badge
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '${stack.screenshots.length}',
                        style: AppTypography.monoSm
                            .copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                  // Avatar group — shown when stack is shared or read-only
                  if (_cardAvatars(stack).isNotEmpty)
                    Positioned(
                      bottom: 6,
                      left: 8,
                      child: _CardAvatarStack(avatarUrls: _cardAvatars(stack)),
                    ),
                ],
              ),
            ),
            // Name footer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                stack.name,
                style: AppTypography.labelLg,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

}

List<String> _cardAvatars(stack_model.Stack stack) {
  if (stack.isReadOnly && stack.ownerAvatarUrl != null) {
    return [stack.ownerAvatarUrl!];
  }
  return stack.memberAvatars;
}

class _CardAvatarStack extends StatelessWidget {
  final List<String> avatarUrls;
  const _CardAvatarStack({required this.avatarUrls});

  @override
  Widget build(BuildContext context) {
    const size = 20.0;
    const overlap = 8.0;
    const maxVisible = 4;
    final visible = avatarUrls.take(maxVisible).toList();
    final overflow = avatarUrls.length - maxVisible;
    final itemCount = visible.length + (overflow > 0 ? 1 : 0);
    final totalWidth = size + (itemCount - 1) * (size - overlap);

    return SizedBox(
      width: totalWidth,
      height: size,
      child: Stack(
        children: [
          for (int i = 0; i < visible.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: _CardAvatar(url: visible[i], size: size),
            ),
          if (overflow > 0)
            Positioned(
              left: visible.length * (size - overlap),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.55),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2), width: 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$overflow',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.3,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CardAvatar extends StatelessWidget {
  final String url;
  final double size;
  const _CardAvatar({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final hue = (url.hashCode.abs() % 360).toDouble();
    final fallback = HSLColor.fromAHSL(1, hue, 0.45, 0.35).toColor();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
            color: Colors.black.withValues(alpha: 0.6), width: 1),
      ),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Container(
            color: fallback,
            alignment: Alignment.center,
            child: Text('?',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.4,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final stack_model.Stack stack;
  const _Cover({required this.stack});

  @override
  Widget build(BuildContext context) {
    if (stack.coverImage == null) {
      return Container(
        color: AppColors.bgElevated,
        child: const Center(
          child: Icon(Icons.photo_library_outlined,
              color: AppColors.textMuted, size: 28),
        ),
      );
    }
    final uri = stack.coverImage!.uri;
    if (uri.startsWith('http')) {
      return Image.network(uri, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: AppColors.bgElevated));
    }
    return Image.file(File(uri), fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: AppColors.bgElevated));
  }
}
