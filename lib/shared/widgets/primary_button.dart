import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';

enum PrimaryButtonSize { sm, md, lg }
enum PrimaryButtonShape { rounded, pill }

/// Single source of truth for accent-filled primary CTAs across the app.
/// Implements the gradient depth treatment from the Claude Design handoff:
///   • top-edge highlight via vertical gradient (accentHighlight → accent)
///   • darker accentDeep border
///   • subtle outer drop shadow
///   • press = solid accentDeep + scale 0.97
class PrimaryButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expanded;
  final PrimaryButtonSize size;
  final PrimaryButtonShape shape;

  /// Optional extra outer shadows (e.g. floating-CTA glow). Stacked under the
  /// default depth shadow.
  final List<BoxShadow>? extraShadow;

  /// Override the size preset's padding (rare — for one-off CTAs).
  final EdgeInsetsGeometry? padding;

  /// Override the size preset's min-height.
  final double? minHeight;

  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.loading = false,
    this.expanded = false,
    this.size = PrimaryButtonSize.md,
    this.shape = PrimaryButtonShape.rounded,
    this.extraShadow,
    this.padding,
    this.minHeight,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  bool get _disabled => widget.onPressed == null || widget.loading;

  void _onTapDown(TapDownDetails _) {
    if (!_disabled) setState(() => _pressed = true);
  }

  void _onTapUp(TapUpDetails _) {
    if (_pressed) {
      setState(() => _pressed = false);
      widget.onPressed?.call();
    }
  }

  void _onTapCancel() => setState(() => _pressed = false);

  EdgeInsets get _padding => switch (widget.size) {
        PrimaryButtonSize.sm =>
          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        PrimaryButtonSize.md =>
          const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        PrimaryButtonSize.lg =>
          const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      };

  double get _minHeight => switch (widget.size) {
        PrimaryButtonSize.sm => 32,
        PrimaryButtonSize.md => 40,
        PrimaryButtonSize.lg => 52,
      };

  double get _iconSize => switch (widget.size) {
        PrimaryButtonSize.sm => 13,
        PrimaryButtonSize.md => 16,
        PrimaryButtonSize.lg => 18,
      };

  TextStyle get _textStyle {
    final base = switch (widget.size) {
      PrimaryButtonSize.sm => AppTypography.labelMd,
      PrimaryButtonSize.md => AppTypography.labelLg,
      PrimaryButtonSize.lg =>
        AppTypography.labelLg.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
    };
    return base.copyWith(
      color: _disabled ? AppColors.textDisabled : AppColors.textPrimary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.shape == PrimaryButtonShape.pill ? 999.0 : 8.0;

    final shadows = <BoxShadow>[
      if (widget.extraShadow != null && !_disabled) ...widget.extraShadow!,
      if (!_disabled && !_pressed)
        const BoxShadow(
          color: AppColors.shadowDefault,
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
    ];

    final decoration = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: _disabled
            ? [AppColors.accentMuted, AppColors.accentMuted]
            : _pressed
                ? [AppColors.accentDeep, AppColors.accentDeep]
                : [AppColors.accentHighlight, AppColors.accent],
        stops: const [0.0, 0.35],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: _disabled ? AppColors.accentMuted : AppColors.accentDeep,
        width: 1,
      ),
      boxShadow: shadows,
    );

    final textColor = _disabled ? AppColors.textDisabled : AppColors.textPrimary;

    Widget child;
    if (widget.loading) {
      child = SizedBox(
        width: _iconSize,
        height: _iconSize,
        child: CircularProgressIndicator(
          strokeWidth: 1.7,
          valueColor: AlwaysStoppedAnimation(textColor),
        ),
      );
    } else if (widget.icon != null) {
      child = Row(
        mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.icon, size: _iconSize, color: textColor),
          const SizedBox(width: 6),
          Text(widget.label, style: _textStyle),
        ],
      );
    } else {
      child = Text(widget.label, style: _textStyle, textAlign: TextAlign.center);
    }

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
        child: Container(
          width: widget.expanded ? double.infinity : null,
          constraints:
              BoxConstraints(minHeight: widget.minHeight ?? _minHeight),
          padding: widget.padding ?? _padding,
          decoration: decoration,
          // alignment.center makes Container expand to its parent — only set
          // it when we actually want full width.
          alignment: widget.expanded ? Alignment.center : null,
          child: child,
        ),
      ),
    );
  }
}
