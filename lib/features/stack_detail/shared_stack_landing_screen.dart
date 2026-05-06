import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/sharing_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';

/// Handles incoming shared-stack deep links (UUID-based).
/// Saves the stack locally then navigates to the local StackDetailScreen.
class SharedStackLandingScreen extends StatefulWidget {
  final String sharedId;
  const SharedStackLandingScreen({super.key, required this.sharedId});

  @override
  State<SharedStackLandingScreen> createState() =>
      _SharedStackLandingScreenState();
}

class _SharedStackLandingScreenState extends State<SharedStackLandingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _saveAndNavigate());
  }

  Future<void> _saveAndNavigate() async {
    try {
      final localId =
          await SharingService.instance.saveSharedStack(widget.sharedId);
      if (mounted) context.go('/stack/$localId');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open shared stack: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go('/stacks');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
                strokeWidth: 1.5, color: AppColors.accent),
            const SizedBox(height: 16),
            Text('Opening stack…',
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
