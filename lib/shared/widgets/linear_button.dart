import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';

enum LinearButtonVariant { primary, secondary, ghost, destructive }

class LinearButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final LinearButtonVariant variant;
  final bool isLoading;
  final bool small;

  const LinearButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = LinearButtonVariant.secondary,
    this.isLoading = false,
    this.small = false,
  });

  @override
  State<LinearButton> createState() => _LinearButtonState();
}

class _LinearButtonState extends State<LinearButton> {
  bool _pressed = false;

  void _onTapDown(TapDownDetails _) {
    if (widget.onPressed != null && !widget.isLoading) {
      setState(() => _pressed = true);
    }
  }

  void _onTapUp(TapUpDetails _) {
    if (_pressed) {
      setState(() => _pressed = false);
      widget.onPressed?.call();
    }
  }

  void _onTapCancel() => setState(() => _pressed = false);

  BoxDecoration _decoration(bool disabled) {
    switch (widget.variant) {
      case LinearButtonVariant.primary:
        // Depth: top-edge highlight gradient + darker border + outer drop shadow.
        // Mirrors CSS: inset 0 1px 0 rgba(255,255,255,0.12) + 0 1px 2px rgba(0,0,0,0.3)
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _pressed
                ? [AppColors.accentDeep, AppColors.accentDeep]
                : [AppColors.accentHighlight, AppColors.accent],
            stops: const [0.0, 0.35],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.accentDeep, width: 1),
          boxShadow: _pressed
              ? const []
              : [
                  BoxShadow(
                    color: AppColors.shadowDefault,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
        );

      case LinearButtonVariant.secondary:
        // White-transparent border reads as a subtle edge highlight on dark bg,
        // unlike opaque borderDefault which can disappear into the surface.
        return BoxDecoration(
          color: _pressed ? AppColors.bgOverlay : AppColors.bgElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderWhiteSubtle, width: 1),
        );

      case LinearButtonVariant.ghost:
        return BoxDecoration(
          color: _pressed
              ? AppColors.bgSurface.withValues(alpha: 0.6)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.transparent, width: 1),
        );

      case LinearButtonVariant.destructive:
        // Neutral dark fill — danger lives in text+border only (same as design spec).
        return BoxDecoration(
          color: _pressed ? AppColors.bgOverlay : AppColors.bgElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.error.withValues(alpha: 0.3),
            width: 1,
          ),
        );
    }
  }

  Color _textColor(bool disabled) => switch (widget.variant) {
        LinearButtonVariant.primary => AppColors.textPrimary,
        LinearButtonVariant.secondary =>
          disabled ? AppColors.textDisabled : AppColors.textPrimary,
        LinearButtonVariant.ghost =>
          disabled ? AppColors.textDisabled : AppColors.textSecondary,
        LinearButtonVariant.destructive => AppColors.error,
      };

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null && !widget.isLoading;
    final textColor = _textColor(disabled);

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
        child: Container(
          constraints: BoxConstraints(minHeight: widget.small ? 30 : 36),
          padding: EdgeInsets.symmetric(
            horizontal: widget.small ? 12 : 16,
            vertical: widget.small ? 7 : 9,
          ),
          decoration: _decoration(disabled),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isLoading)
                SizedBox(
                  width: widget.small ? 11 : 13,
                  height: widget.small ? 11 : 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: textColor,
                  ),
                )
              else if (widget.icon != null)
                Icon(widget.icon, color: textColor, size: widget.small ? 13 : 15),
              if ((widget.icon != null || widget.isLoading) &&
                  widget.label.isNotEmpty)
                SizedBox(width: widget.small ? 5 : 6),
              if (widget.label.isNotEmpty)
                Text(
                  widget.label,
                  style: (widget.small
                          ? AppTypography.labelMd
                          : AppTypography.labelLg)
                      .copyWith(color: textColor),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
