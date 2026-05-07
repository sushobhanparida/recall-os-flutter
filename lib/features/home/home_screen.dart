import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/auth_state.dart';
import '../../core/models/screenshot_model.dart';
import '../../core/services/smart_actions_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets/app_fab.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/typewriter_text.dart';
import 'home_provider.dart';
import 'widgets/events_ticket_view.dart';
import 'widgets/links_list_view.dart';
import 'widgets/notes_view.dart';
import 'widgets/screenshot_card.dart';
import 'widgets/smart_actions_banner.dart';
import 'widgets/tag_filter_bar.dart';
import '../task/task_provider.dart';
import '../task/widgets/add_to_tasks_sheet.dart';
import '../stacks/widgets/stack_chooser_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _scrolled = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeProvider);
    final notifier = ref.read(homeProvider.notifier);
    final actions = ref.watch(smartActionsProvider);
    final smartActionsService = ref.read(smartActionsServiceProvider);

    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Fixed header — shadow appears on scroll ───────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: AppColors.bgBase,
                    boxShadow: _scrolled
                        ? [
                            BoxShadow(
                              color: AppColors.shadowDefault,
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : const [],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(backfillRemaining: state.backfillRemaining),
                      const SizedBox(height: 14),
                      TagFilterBar(
                        selected: state.tagFilter,
                        onSelected: notifier.setFilter,
                      ),
                      if (state.isImporting) ...[
                        const SizedBox(height: 4),
                        const LinearProgressIndicator(
                          minHeight: 1,
                          backgroundColor: AppColors.borderSubtle,
                          color: AppColors.accent,
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),

                // ── Scrollable: actions banner + screenshot grid ───────────
                Expanded(
                  child: NotificationListener<ScrollUpdateNotification>(
                    onNotification: (n) {
                      final scrolled = n.metrics.pixels > 2;
                      if (scrolled != _scrolled) {
                        setState(() => _scrolled = scrolled);
                      }
                      return false;
                    },
                    child: _ScrollableBody(
                      tagFilter: state.tagFilter,
                      screenshots: state.screenshots,
                      searchQuery: state.searchQuery,
                      actions: actions,
                      onOpen: (s) => context.push('/screenshot/${s.id}'),
                      onDelete: (id) => notifier.deleteScreenshot(id),
                      onAddToTasks: (s) {
                        final taskNotifier = ref.read(taskProvider.notifier);
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: AppColors.bgElevated,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(12)),
                            side: BorderSide(
                                color: AppColors.borderDefault, width: 1),
                          ),
                          builder: (_) => AddToTasksSheet(
                            screenshot: s,
                            onCreate: taskNotifier.addTask,
                          ),
                        );
                      },
                      onAddToStack: (s) {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: AppColors.bgElevated,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(16)),
                          ),
                          builder: (_) => StackChooserSheet(screenshot: s),
                        );
                      },
                      onExecuteAction: (a) =>
                          smartActionsService.execute(a, context),
                      onOpenAction: (a) {
                        final id = a.screenshot.id;
                        if (id != null) context.push('/screenshot/$id');
                      },
                      onRemoveAction: (a) {
                        final id = a.screenshot.id;
                        if (id != null) {
                          ref
                              .read(dismissedActionsProvider.notifier)
                              .update((s) => {...s, id});
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom bar — search expands left→right, FAB slides out right ──
          Positioned(
            left: 16,
            right: 16,
            bottom: keyboardBottom + 16,
            child: _BottomBar(
              query: state.searchQuery,
              onSearchChanged: notifier.setSearch,
              onFabPressed: notifier.importFromGallery,
              tagFilter: state.tagFilter,
            ),
          ),
        ],
      ),
    );
  }

}

// ── Bottom bar — search pill (left) + FAB (right) ──────────────────────────────

class _BottomBar extends StatefulWidget {
  final String query;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onFabPressed;
  final String tagFilter;

  const _BottomBar({
    required this.query,
    required this.onSearchChanged,
    required this.onFabPressed,
    required this.tagFilter,
  });

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
  bool _expanded = false;
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();

  static const _dur = Duration(milliseconds: 220);
  static const _curve = Curves.easeInOut;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.query);
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _BottomBar old) {
    super.didUpdateWidget(old);
    if (widget.query != _ctrl.text) {
      _ctrl.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
    if (widget.tagFilter != old.tagFilter && _expanded) {
      _collapse();
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus && _ctrl.text.isEmpty) {
      setState(() => _expanded = false);
    }
  }

  void _expand() {
    setState(() => _expanded = true);
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _focus.requestFocus();
    });
  }

  void _collapse() {
    _ctrl.clear();
    widget.onSearchChanged('');
    _focus.unfocus();
    setState(() => _expanded = false);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onAll = widget.tagFilter == 'All';
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return SizedBox(
          height: 56,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // FAB anchored right — slides off when search expands
              AnimatedPositioned(
                duration: _dur,
                curve: _curve,
                right: _expanded ? -80.0 : 0.0,
                top: 0,
                width: 56,
                height: 56,
                child: AppFab(onPressed: widget.onFabPressed),
              ),
              // Search bar — only on All tab, expands to full width
              if (onAll)
                AnimatedPositioned(
                  duration: _dur,
                  curve: _curve,
                  left: 0,
                  top: 0,
                  height: 56,
                  width: _expanded ? w : 56,
                  child: _buildSearchBar(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return AnimatedContainer(
      duration: _dur,
      curve: _curve,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(_expanded ? 14.0 : 28.0),
        border: Border.all(color: AppColors.borderDefault, width: 1),
      ),
      child: Stack(
        children: [
          // TextField — sits between icon and close button
          if (_expanded)
            Positioned(
              left: 52,
              right: 44,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  onChanged: widget.onSearchChanged,
                  cursorColor: AppColors.accent,
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search…',
                    hintStyle: AppTypography.bodyMd
                        .copyWith(color: AppColors.textMuted),
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          // Close button anchored right
          if (_expanded)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 44,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _collapse,
                child: const Center(
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
          // Search icon anchored left — always visible
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 56,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _expanded ? null : _expand,
              child: const Center(
                child: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scrollable body ────────────────────────────────────────────────────────────

class _ScrollableBody extends StatelessWidget {
  final String tagFilter;
  final List<Screenshot> screenshots;
  final String searchQuery;
  final List<SmartAction> actions;
  final ValueChanged<Screenshot> onOpen;
  final ValueChanged<int> onDelete;
  final ValueChanged<Screenshot> onAddToTasks;
  final ValueChanged<Screenshot> onAddToStack;
  final void Function(SmartAction) onExecuteAction;
  final void Function(SmartAction) onOpenAction;
  final void Function(SmartAction) onRemoveAction;

  const _ScrollableBody({
    required this.tagFilter,
    required this.screenshots,
    required this.searchQuery,
    required this.actions,
    required this.onOpen,
    required this.onDelete,
    required this.onAddToTasks,
    required this.onAddToStack,
    required this.onExecuteAction,
    required this.onOpenAction,
    required this.onRemoveAction,
  });

  Widget _banner() => SmartActionsBanner(
        actions: actions,
        onExecute: onExecuteAction,
        onOpen: onOpenAction,
        onRemove: onRemoveAction,
      );

  @override
  Widget build(BuildContext context) {
    if (screenshots.isEmpty && tagFilter != 'Notes') {
      return CustomScrollView(
        slivers: [
          if (actions.isNotEmpty) SliverToBoxAdapter(child: _banner()),
          SliverFillRemaining(
            child: EmptyState(
              icon: Icons.screenshot_monitor_outlined,
              title: searchQuery.isNotEmpty ? 'No results' : 'No screenshots yet',
              subtitle: searchQuery.isNotEmpty
                  ? 'Try a different search term'
                  : 'Tap + to import screenshots',
            ),
          ),
        ],
      );
    }

    switch (tagFilter) {
      case 'Notes':
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: NotesView(
                noteScreenshots: screenshots,
                onOpenScreenshot: onOpen,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
              ),
            ),
          ],
        );
      case 'Links':
        return CustomScrollView(
          slivers: [
            if (screenshots.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: const EmptyState(
                  icon: Icons.link_rounded,
                  title: 'No links yet',
                  subtitle: 'Screenshots with URLs will show up here',
                ),
              )
            else
              SliverToBoxAdapter(
                child: LinksListView(
                  screenshots: screenshots,
                  onOpen: onOpen,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                ),
              ),
          ],
        );
      case 'Events':
        return CustomScrollView(
          slivers: [
            if (actions.isNotEmpty) SliverToBoxAdapter(child: _banner()),
            if (screenshots.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: const EmptyState(
                  icon: Icons.confirmation_number_outlined,
                  title: 'No tickets yet',
                  subtitle: 'Boarding passes, movie tickets, and event invites land here',
                ),
              )
            else
              SliverToBoxAdapter(
                child: EventsTicketView(
                  screenshots: screenshots,
                  onOpen: onOpen,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                ),
              ),
          ],
        );
      default:
        return CustomScrollView(
          slivers: [
            if (actions.isNotEmpty) SliverToBoxAdapter(child: _banner()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 10),
                child: Text(
                  'Screenshots',
                  style: AppTypography.labelLg
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                // bottom: 100 clears both FABs
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 100),
                child: _MasonryGrid(
                  screenshots: screenshots,
                  onOpen: onOpen,
                  onDelete: onDelete,
                  onAddToTasks: onAddToTasks,
                  onAddToStack: onAddToStack,
                ),
              ),
            ),
          ],
        );
    }
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  final int backfillRemaining;
  const _Header({required this.backfillRemaining});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => showModalBottomSheet<void>(
              context: context,
              useRootNavigator: true,
              backgroundColor: AppColors.bgElevated,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              isScrollControlled: true,
              builder: (_) => const _SettingsSheet(),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _LogoMark(),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('RecallOS', style: AppTypography.displayMd),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 18,
                      child: TypewriterText(
                        lines: ref.watch(homeInsightsProvider),
                        style: AppTypography.monoMd.copyWith(
                          color: AppColors.textMuted,
                        ),
                        cursorColor: AppColors.accentText,
                        textAlign: TextAlign.left,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          if (backfillRemaining > 0)
            _BackfillChip(remaining: backfillRemaining),
        ],
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.gradientStart, AppColors.gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      padding: const EdgeInsets.all(6),
      child: SvgPicture.asset(
        'assets/images/RecallOS-appicon.svg',
        colorFilter: const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn),
      ),
    );
  }
}

class _BackfillChip extends StatelessWidget {
  final int remaining;
  const _BackfillChip({required this.remaining});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderDefault, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.2,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 6),
          Text('Indexing $remaining',
              style: AppTypography.labelSm
                  .copyWith(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

// ── Settings sheet ─────────────────────────────────────────────────────────────

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final user = auth is AuthAuthenticated ? auth.user : null;

    final email = user?.email ?? '';
    final name = (user?.userMetadata?['full_name'] as String? ??
                  user?.userMetadata?['name'] as String? ?? '').trim();
    final avatarUrl = user?.userMetadata?['avatar_url'] as String?;
    final initials = _initials(name.isNotEmpty ? name : email);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderEmphasis,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // ── User info ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _UserAvatar(avatarUrl: avatarUrl, initials: initials),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (name.isNotEmpty) ...[
                        Text(name,
                            style: AppTypography.labelLg
                                .copyWith(color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                      ],
                      Text(email,
                          style: AppTypography.bodySm
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const Divider(color: AppColors.borderDefault, height: 1),

          // ── Settings tiles ─────────────────────────────────────────────────
          _SettingsTile(
            icon: Icons.notifications_outlined,
            label: 'Notifications',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.palette_outlined,
            label: 'Appearance',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.cloud_outlined,
            label: 'Backup & sync',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.info_outlined,
            label: 'About',
            onTap: () {},
          ),

          const Divider(color: AppColors.borderDefault, height: 1),

          // ── Sign out ───────────────────────────────────────────────────────
          _SettingsTile(
            icon: Icons.logout_rounded,
            label: 'Sign out',
            color: AppColors.error,
            onTap: () async {
              Navigator.of(context).pop();
              await AuthService.signOut();
            },
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _initials(String text) {
    final parts = text.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (text.isNotEmpty) return text[0].toUpperCase();
    return '?';
  }
}

class _UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  const _UserAvatar({required this.avatarUrl, required this.initials});

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: avatarUrl!,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          placeholder: (_, __) => _InitialsCircle(initials: initials),
          errorWidget: (_, __, ___) => _InitialsCircle(initials: initials),
        ),
      );
    }
    return _InitialsCircle(initials: initials);
  }
}

class _InitialsCircle extends StatelessWidget {
  final String initials;
  const _InitialsCircle({required this.initials});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppColors.gradientStart, AppColors.gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: AppTypography.labelMd.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(label,
                style: AppTypography.bodyMd.copyWith(color: color)),
            const Spacer(),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ── Masonry grid (3 columns, each card sizes to its natural aspect ratio) ──────

class _MasonryGrid extends StatelessWidget {
  final List<Screenshot> screenshots;
  final ValueChanged<Screenshot> onOpen;
  final ValueChanged<int> onDelete;
  final ValueChanged<Screenshot> onAddToTasks;
  final ValueChanged<Screenshot> onAddToStack;

  const _MasonryGrid({
    required this.screenshots,
    required this.onOpen,
    required this.onDelete,
    required this.onAddToTasks,
    required this.onAddToStack,
  });

  @override
  Widget build(BuildContext context) {
    // Distribute round-robin into 3 columns
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
                  ScreenshotCard(
                    screenshot: cols[c][i],
                    onTap: () => onOpen(cols[c][i]),
                    onDelete: () => onDelete(cols[c][i].id!),
                    onAddToTasks: () => onAddToTasks(cols[c][i]),
                    onAddToStack: () => onAddToStack(cols[c][i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
