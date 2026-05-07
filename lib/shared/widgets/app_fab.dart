import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

class AppFab extends StatefulWidget {
  final VoidCallback onPressed;

  const AppFab({super.key, required this.onPressed});

  @override
  State<AppFab> createState() => _AppFabState();
}

class _AppFabState extends State<AppFab> {
  bool _pressed = false;

  static const _squircle = ContinuousRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(24)),
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.88 : 1.0,
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOutCubic,
      child: Material(
        color: AppColors.accent,
        shape: _squircle,
        elevation: _pressed ? 2 : 12,
        shadowColor: AppColors.accent.withValues(alpha: 0.55),
        animationDuration: const Duration(milliseconds: 180),
        child: InkWell(
          onTap: widget.onPressed,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          customBorder: _squircle,
          splashColor: Colors.white.withValues(alpha: 0.18),
          highlightColor: Colors.white.withValues(alpha: 0.08),
          child: const SizedBox(
            width: 56,
            height: 56,
            child: Icon(
              Icons.add_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}
