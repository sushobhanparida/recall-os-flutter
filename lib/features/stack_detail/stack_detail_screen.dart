import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/models/screenshot_model.dart';
import '../../core/models/stack_model.dart' as stack_model;
import '../../core/services/sharing_service.dart';
import '../../shared/widgets/app_fab.dart';
import '../../shared/widgets/empty_state.dart';
import '../home/widgets/screenshot_card.dart';
import '../stacks/stacks_provider.dart';

class StackDetailScreen extends ConsumerWidget {
  final int stackId;

  const StackDetailScreen({super.key, required this.stackId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stackAsync = ref.watch(stackDetailProvider(stackId));
    final allAsync = ref.watch(allScreenshotsProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: stackAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: AppColors.accent,
          ),
        ),
        error: (e, _) => Center(
            child: Text('Error',
                style: AppTypography.bodyMd.copyWith(color: AppColors.error))),
        data: (stack) {
          if (stack == null) {
            return const EmptyState(
                icon: Icons.layers_outlined, title: 'Stack not found');
          }
          return _StackDetailView(
            stack: stack,
            allScreenshots: allAsync.value ?? [],
            onOpenPicker: () => ref.invalidate(allScreenshotsProvider),
            onAddScreenshot: (sId) =>
                ref.read(stacksProvider.notifier).addScreenshot(stackId, sId),
            onRemoveScreenshot: (sId) =>
                ref.read(stacksProvider.notifier).removeScreenshot(stackId, sId),
          );
        },
      ),
    );
  }
}

class _StackDetailView extends ConsumerStatefulWidget {
  final stack_model.Stack stack;
  final List<Screenshot> allScreenshots;
  final VoidCallback onOpenPicker;
  final void Function(int) onAddScreenshot;
  final void Function(int) onRemoveScreenshot;

  const _StackDetailView({
    required this.stack,
    required this.allScreenshots,
    required this.onOpenPicker,
    required this.onAddScreenshot,
    required this.onRemoveScreenshot,
  });

  @override
  ConsumerState<_StackDetailView> createState() => _StackDetailViewState();
}

class _StackDetailViewState extends ConsumerState<_StackDetailView> {
  bool _sharing = false;
  StackAvatarInfo _avatarInfo = const StackAvatarInfo();

  stack_model.Stack get stack => widget.stack;

  @override
  void initState() {
    super.initState();
    if (stack.isShared) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAvatars());
    }
  }

  Future<void> _fetchAvatars() async {
    try {
      final info = await SharingService.instance.fetchAndCacheAvatars(stack);
      if (mounted) setState(() => _avatarInfo = info);
    } catch (_) {}
  }

  Future<void> _onShareTap() async {
    // Already shared: URL is known — open the sheet immediately.
    // Background sync (triggered on add/remove) keeps Supabase up to date.
    if (stack.isShared) {
      _showShareSheet(SharingService.instance.buildShareUrl(stack.sharedId!));
      return;
    }

    // First share: upload images and create the Supabase record.
    setState(() => _sharing = true);
    try {
      final url = await SharingService.instance.shareStack(stack);
      ref.invalidate(stackDetailProvider(stack.id!));
      if (!mounted) return;
      _showShareSheet(url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Share failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _showShareSheet(String url) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: AppColors.borderDefault),
      ),
      builder: (_) => _ShareSheet(
        url: url,
        stack: stack,
        onUnshare: () async {
          Navigator.pop(context);
          await _onUnshareTap();
        },
        onTogglePublic: (isPublic) async {
          await SharingService.instance.togglePublic(stack, isPublic: isPublic);
          ref.invalidate(stackDetailProvider(stack.id!));
        },
      ),
    );
  }

  Future<void> _onUnshareTap() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Unshare stack?', style: AppTypography.headingMd),
        content: Text(
          'The link will stop working immediately.',
          style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: AppTypography.labelMd
                    .copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Unshare',
                style: AppTypography.labelMd.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _sharing = true);
    try {
      await SharingService.instance.unshareStack(stack);
      ref.invalidate(stackDetailProvider(stack.id!));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unshare failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _onMoreTap() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: AppColors.borderDefault, width: 1),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 32,
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.borderEmphasis,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 4),
            if (stack.isReadOnly) ...[
              ListTile(
                leading: const Icon(Icons.remove_circle_outline_rounded,
                    color: AppColors.error, size: 18),
                title: Text('Remove from my stacks',
                    style: AppTypography.bodyMd.copyWith(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _onRemoveTap();
                },
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined,
                    color: AppColors.textSecondary, size: 18),
                title: Text('Rename',
                    style: AppTypography.bodyMd
                        .copyWith(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _onRenameTap();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.error, size: 18),
                title: Text('Delete stack',
                    style:
                        AppTypography.bodyMd.copyWith(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _onDeleteTap();
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _onRemoveTap() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.borderDefault, width: 1),
        ),
        title: Text('Remove stack?', style: AppTypography.headingMd),
        content: Text(
          'This removes the stack from your account. The owner\'s copy is not affected.',
          style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: AppTypography.labelLg.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Remove',
                style: AppTypography.labelLg.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await SharingService.instance.removeSharedStack(stack);
    if (mounted) context.pop();
  }

  void _onRenameTap() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.borderDefault, width: 1),
        ),
        title: Text('Rename Stack', style: AppTypography.headingMd),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: AppTypography.bodyMd.copyWith(color: AppColors.textPrimary),
          cursorColor: AppColors.accent,
          decoration: InputDecoration(
            hintText: stack.name,
            hintStyle:
                AppTypography.bodyMd.copyWith(color: AppColors.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style:
                    AppTypography.labelLg.copyWith(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                ref.read(stacksProvider.notifier).renameStack(stack.id!, name);
                Navigator.pop(context);
              }
            },
            child: Text('Save',
                style: AppTypography.labelLg
                    .copyWith(color: AppColors.accentText)),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  Future<void> _onDeleteTap() async {
    final isShared = stack.isShared;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.borderDefault, width: 1),
        ),
        title: Text('Delete stack?', style: AppTypography.headingMd),
        content: Text(
          isShared
              ? 'This will also remove the shared link immediately. This cannot be undone.'
              : 'This stack and all its contents will be removed. This cannot be undone.',
          style: AppTypography.bodyMd
              .copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: AppTypography.labelLg
                    .copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete',
                style:
                    AppTypography.labelLg.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await ref.read(stacksProvider.notifier).deleteStack(stack.id!);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final allAvatarUrls = [
      if (_avatarInfo.ownerAvatarUrl != null) _avatarInfo.ownerAvatarUrl!,
      ..._avatarInfo.memberAvatarUrls,
    ];

    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 6, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: AppColors.textSecondary, size: 20),
                    ),
                    Expanded(
                      child: Text(
                        stack.name,
                        style: AppTypography.headingMd,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Screenshot count pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.borderDefault),
                      ),
                      child: Text(
                        '${stack.screenshots.length}',
                        style: AppTypography.labelSm
                            .copyWith(color: AppColors.textMuted),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Share button — hidden for read-only stacks
                    if (!stack.isReadOnly)
                      if (_sharing)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: AppColors.accent),
                          ),
                        )
                      else
                        IconButton(
                          onPressed: _onShareTap,
                          icon: Icon(
                            stack.isShared
                                ? Icons.link_rounded
                                : Icons.ios_share_rounded,
                            color: stack.isShared
                                ? AppColors.accent
                                : AppColors.textSecondary,
                            size: 20,
                          ),
                        ),
                    IconButton(
                      onPressed: _onMoreTap,
                      icon: const Icon(Icons.more_vert_rounded,
                          color: AppColors.textSecondary, size: 20),
                    ),
                  ],
                ),
              ),
              // Avatar row + read-only chip
              if (allAvatarUrls.isNotEmpty || stack.isReadOnly)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Row(
                    children: [
                      _AvatarStack(avatarUrls: allAvatarUrls),
                      const SizedBox(width: 8),
                      if (stack.isReadOnly && _avatarInfo.ownerName != null)
                        Text(
                          'by ${_avatarInfo.ownerName}',
                          style: AppTypography.bodySm
                              .copyWith(color: AppColors.textMuted),
                        )
                      else if (!stack.isReadOnly && _avatarInfo.memberAvatarUrls.isNotEmpty)
                        Text(
                          '${_avatarInfo.memberAvatarUrls.length} viewer${_avatarInfo.memberAvatarUrls.length == 1 ? '' : 's'}',
                          style: AppTypography.bodySm
                              .copyWith(color: AppColors.textMuted),
                        ),
                      if (stack.isReadOnly) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.bgSurface,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.borderDefault),
                          ),
                          child: Text(
                            'View only',
                            style: AppTypography.labelSm
                                .copyWith(color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              // Grid area
              Expanded(
                child: stack.screenshots.isEmpty
                    ? const EmptyState(
                        icon: Icons.photo_library_outlined,
                        title: 'This stack is empty',
                        subtitle: 'Tap + to add screenshots',
                      )
                    : Stack(
                        children: [
                          CustomScrollView(
                            slivers: [
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                      18, 4, 18, stack.isReadOnly ? 24 : 100),
                                  child: _StackMasonryGrid(
                                    screenshots: stack.screenshots,
                                    readOnly: stack.isReadOnly,
                                    onTap: (s) {
                                      if (stack.isReadOnly) {
                                        _showFullscreenImage(context, s.uri);
                                      } else {
                                        context.push('/screenshot/${s.id}');
                                      }
                                    },
                                    onRemove: (s) =>
                                        widget.onRemoveScreenshot(s.id!),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // Top gradient fade
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: 16,
                            child: IgnorePointer(
                              child: Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      AppColors.bgBase,
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
          // FAB — hidden for read-only stacks
          if (!stack.isReadOnly)
            Positioned(
              right: 22,
              bottom: 24,
              child: AppFab(onPressed: () => _showAddPicker(context)),
            ),
        ],
      ),
    );
  }

  void _showFullscreenImage(BuildContext context, String uri) {
    showDialog(
      context: context,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          color: Colors.black87,
          child: InteractiveViewer(
            child: Center(
              child: uri.startsWith('http')
                  ? Image.network(uri, fit: BoxFit.contain)
                  : Image.file(File(uri), fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  void _showAddPicker(BuildContext context) {
    widget.onOpenPicker();
    final existing =
        stack.screenshots.map((s) => s.id!).toSet();
    final available =
        widget.allScreenshots.where((s) => !existing.contains(s.id)).toList();
    final hasAnyScreenshots = widget.allScreenshots.isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: AppColors.borderDefault, width: 1),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (ctx, scrollCtrl) => _ScreenshotPicker(
          screenshots: available,
          hasAnyScreenshots: hasAnyScreenshots,
          scrollController: scrollCtrl,
          onSelect: (id) {
            widget.onAddScreenshot(id);
            Navigator.pop(ctx);
          },
        ),
      ),
    );
  }
}

class _ShareSheet extends StatefulWidget {
  final String url;
  final stack_model.Stack stack;
  final VoidCallback onUnshare;
  final Future<void> Function(bool isPublic) onTogglePublic;

  const _ShareSheet({
    required this.url,
    required this.stack,
    required this.onUnshare,
    required this.onTogglePublic,
  });

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late bool _isPublic;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _isPublic = widget.stack.isPublic;
  }

  Future<void> _handleToggle(bool value) async {
    setState(() { _isPublic = value; _toggling = true; });
    try {
      await widget.onTogglePublic(value);
    } catch (_) {
      if (mounted) setState(() => _isPublic = !value);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
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
          Text('Stack shared', style: AppTypography.headingMd),
          const SizedBox(height: 4),
          Text(
            _isPublic
                ? 'Anyone with this link can view'
                : 'Only RecallOS users with this link can view',
            style: AppTypography.bodySm.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          // URL row — tap anywhere to copy
          GestureDetector(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: widget.url));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Link copied'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderDefault),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.url,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textSecondary,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.copy_rounded,
                      size: 16, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Open link button
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () => launchUrl(
                Uri.parse(widget.url),
                mode: LaunchMode.externalApplication,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.open_in_new_rounded,
                        size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Open link',
                      style: AppTypography.labelLg.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Make public toggle
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Make public', style: AppTypography.bodyMd),
                  Text(
                    'Allow non-RecallOS users to view',
                    style: AppTypography.labelSm.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
              const Spacer(),
              if (_toggling)
                const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.accent),
                )
              else
                Switch(
                  value: _isPublic,
                  onChanged: _handleToggle,
                  activeThumbColor: AppColors.accent,
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Stop sharing
          TextButton(
            onPressed: widget.onUnshare,
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: Text(
              'Stop sharing',
              style: AppTypography.labelMd.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _StackMasonryGrid extends StatelessWidget {
  final List<Screenshot> screenshots;
  final ValueChanged<Screenshot> onTap;
  final ValueChanged<Screenshot> onRemove;
  final bool readOnly;

  const _StackMasonryGrid({
    required this.screenshots,
    required this.onTap,
    required this.onRemove,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final cols = List.generate(3, (_) => <Screenshot>[]);
    for (int i = 0; i < screenshots.length; i++) {
      cols[i % 3].add(screenshots[i]);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int c = 0; c < 3; c++) ...[
          if (c > 0) const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                for (int i = 0; i < cols[c].length; i++) ...[
                  if (i > 0) const SizedBox(height: 16),
                  GestureDetector(
                    onLongPress: readOnly
                        ? null
                        : () => _showUnstackSheet(context, cols[c][i]),
                    child: ScreenshotCard(
                      screenshot: cols[c][i],
                      onTap: () => onTap(cols[c][i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _showUnstackSheet(BuildContext context, Screenshot screenshot) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: AppColors.borderDefault, width: 1),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 32,
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.borderEmphasis,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 4),
            _StackAction(
              icon: Icons.open_in_full_rounded,
              label: 'Open',
              onTap: () {
                Navigator.pop(sheetCtx);
                onTap(screenshot);
              },
            ),
            _StackAction(
              icon: Icons.remove_circle_outline_rounded,
              label: 'Remove from Stack',
              color: AppColors.error,
              onTap: () {
                Navigator.pop(sheetCtx);
                onRemove(screenshot);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _StackAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _StackAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        color == AppColors.textSecondary ? AppColors.textPrimary : color;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 14),
            Text(label,
                style: AppTypography.bodyMd.copyWith(color: textColor)),
          ],
        ),
      ),
    );
  }
}

class _Img extends StatelessWidget {
  final String uri;
  const _Img({required this.uri});

  @override
  Widget build(BuildContext context) {
    if (uri.startsWith('http')) {
      return Image.network(uri,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) =>
              Container(color: AppColors.bgElevated));
    }
    return Image.file(File(uri),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) =>
            Container(color: AppColors.bgElevated));
  }
}

class _AvatarStack extends StatelessWidget {
  final List<String> avatarUrls;

  const _AvatarStack({required this.avatarUrls});

  @override
  Widget build(BuildContext context) {
    if (avatarUrls.isEmpty) return const SizedBox.shrink();
    const size = 26.0;
    const maxVisible = 5;
    const overlap = 10.0;
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
              child: _AvatarCircle(url: visible[i], size: size),
            ),
          if (overflow > 0)
            Positioned(
              left: visible.length * (size - overlap),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bgElevated,
                  border: Border.all(color: AppColors.bgBase, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$overflow',
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: size * 0.3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AvatarCircle extends StatelessWidget {
  final String url;
  final double size;

  const _AvatarCircle({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final hue = (url.hashCode.abs() % 360).toDouble();
    final fallbackColor = HSLColor.fromAHSL(1, hue, 0.45, 0.35).toColor();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.bgBase, width: 1.5),
      ),
      child: ClipOval(
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: fallbackColor,
            alignment: Alignment.center,
            child: Text(
              '?',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScreenshotPicker extends StatefulWidget {
  final List<Screenshot> screenshots;
  final bool hasAnyScreenshots;
  final ScrollController scrollController;
  final void Function(int) onSelect;

  const _ScreenshotPicker({
    required this.screenshots,
    required this.hasAnyScreenshots,
    required this.scrollController,
    required this.onSelect,
  });

  @override
  State<_ScreenshotPicker> createState() => _ScreenshotPickerState();
}

class _ScreenshotPickerState extends State<_ScreenshotPicker> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 12),
          width: 32,
          height: 3,
          decoration: BoxDecoration(
            color: AppColors.borderEmphasis,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('Add screenshots', style: AppTypography.headingMd),
              const Spacer(),
              if (_selected != null)
                GestureDetector(
                  onTap: () => widget.onSelect(_selected!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Add',
                        style: AppTypography.labelLg
                            .copyWith(color: Colors.white)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: widget.screenshots.isEmpty
              ? Center(
                  child: Text(
                    widget.hasAnyScreenshots
                        ? 'All screenshots are already in this stack'
                        : 'No screenshots yet — import some on the Home tab',
                    style: const TextStyle(color: AppColors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                )
              : GridView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: widget.screenshots.length,
                  itemBuilder: (context, i) {
                    final s = widget.screenshots[i];
                    final isSelected = _selected == s.id;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selected = s.id),
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.accent
                                    : AppColors.borderSubtle,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _Img(uri: s.uri),
                          ),
                          if (isSelected)
                            Positioned(
                              top: 5,
                              right: 5,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: const BoxDecoration(
                                  color: AppColors.accent,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check_rounded,
                                    size: 11, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
