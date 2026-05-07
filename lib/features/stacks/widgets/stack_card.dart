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
            // Fan collage cover
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _FanCollage(uris: stack.screenshots.map((s) => s.uri).toList()),
                  // Avatar group
                  if (_cardAvatars(stack).isNotEmpty)
                    Positioned(
                      bottom: 6,
                      left: 8,
                      child: _CardAvatarStack(avatarUrls: _cardAvatars(stack)),
                    ),
                ],
              ),
            ),
            // Name + count footer
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      stack.name,
                      style: AppTypography.labelLg,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.bgElevated,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.borderDefault),
                    ),
                    child: Text(
                      '${stack.screenshots.length}',
                      style: AppTypography.monoSm
                          .copyWith(color: AppColors.textMuted),
                    ),
                  ),
                ],
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
                  color: AppColors.shadowStrong,
                  border: Border.all(
                      color: AppColors.borderEmphasis, width: 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$overflow',
                  style: TextStyle(
                      color: AppColors.textPrimary,
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
            color: AppColors.shadowStrong, width: 1),
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
                    color: AppColors.textPrimary,
                    fontSize: size * 0.4,
                    fontWeight: FontWeight.w600)),
          ),
        ),
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
              color: AppColors.textMuted, size: 28),
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
                        color: AppColors.shadowDefault,
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
      return Image.network(uri,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Container(color: AppColors.bgElevated));
    }
    return Image.file(File(uri),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Container(color: AppColors.bgElevated));
  }
}
