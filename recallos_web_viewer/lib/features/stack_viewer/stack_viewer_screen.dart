import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/shared_stack_model.dart';
import 'stack_viewer_error.dart';

class StackViewerScreen extends StatefulWidget {
  final String stackId;

  const StackViewerScreen({super.key, required this.stackId});

  @override
  State<StackViewerScreen> createState() => _StackViewerScreenState();
}

class _StackViewerScreenState extends State<StackViewerScreen> {
  SharedStack? _stack;
  bool _loading = true;
  bool _error = false;
  bool _showOpenInApp = true;
  final _pageController = PageController();
  final _thumbnailScrollController = ScrollController();
  int _currentPage = 0;

  static const double _thumbnailWidth = 60;
  static const double _thumbnailHeight = 80;
  static const double _thumbnailSpacing = 8;

  @override
  void initState() {
    super.initState();
    _fetchStack();
    _pageController.addListener(() {
      final page = _pageController.page?.round() ?? 0;
      if (page != _currentPage) {
        setState(() => _currentPage = page);
        _scrollThumbnailToVisible(page);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _thumbnailScrollController.dispose();
    super.dispose();
  }

  void _scrollThumbnailToVisible(int index) {
    if (!_thumbnailScrollController.hasClients) return;
    final itemWidth = _thumbnailWidth + _thumbnailSpacing;
    final targetOffset = index * itemWidth;
    final viewportWidth = _thumbnailScrollController.position.viewportDimension;
    final currentOffset = _thumbnailScrollController.offset;
    final maxOffset = _thumbnailScrollController.position.maxScrollExtent;

    final visibleStart = currentOffset;
    final visibleEnd = currentOffset + viewportWidth;
    final itemStart = targetOffset;
    final itemEnd = targetOffset + _thumbnailWidth;

    if (itemStart < visibleStart || itemEnd > visibleEnd) {
      final desired = (targetOffset - viewportWidth / 2 + _thumbnailWidth / 2)
          .clamp(0.0, maxOffset);
      _thumbnailScrollController.animateTo(
        desired,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _fetchStack() async {
    final client = Supabase.instance.client;
    try {
      final data = await client
          .from('shared_stacks')
          .select('id, stack_name, image_urls, is_private')
          .eq('id', widget.stackId)
          .maybeSingle();

      if (data == null) {
        _handleAccessFailure(client);
        return;
      }
      if (mounted) {
        setState(() { _stack = SharedStack.fromMap(data); _loading = false; });
      }
    } catch (e, st) {
      debugPrint('[StackViewer] fetch failed: $e\n$st');
      _handleAccessFailure(client);
    }
  }

  void _handleAccessFailure(SupabaseClient client) {
    if (client.auth.currentUser == null) {
      if (mounted) context.go('/auth/login?redirect=/stack/${widget.stackId}');
    } else {
      _joinAndRefetch(client);
    }
  }

  Future<void> _joinAndRefetch(SupabaseClient client) async {
    try {
      final userId = client.auth.currentUser!.id;
      await client.from('shared_stack_members').upsert(
        {'stack_id': widget.stackId, 'user_id': userId},
        onConflict: 'stack_id,user_id',
      );
      final data = await client
          .from('shared_stacks')
          .select('id, stack_name, image_urls, is_private')
          .eq('id', widget.stackId)
          .maybeSingle();
      if (!mounted) return;
      if (data == null) {
        setState(() { _error = true; _loading = false; });
        return;
      }
      setState(() { _stack = SharedStack.fromMap(data); _loading = false; });
    } catch (e) {
      debugPrint('[StackViewer] join+refetch failed: $e');
      if (mounted) setState(() { _error = true; _loading = false; });
    }
  }

  void _openInApp() {
    html.window.location.href = 'recallos://stack/${widget.stackId}';
  }

  void _goToPrev() {
    if (_currentPage > 0) {
      _pageController.animateToPage(
        _currentPage - 1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _goToNext() {
    final count = _stack?.imageUrls.length ?? 0;
    if (_currentPage < count - 1) {
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _jumpToPage(int index) {
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F0F),
        body: Center(
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: Color(0xFF7C3AED)),
        ),
      );
    }
    if (_error || _stack == null) {
      return StackViewerError(stackId: widget.stackId);
    }

    final stack = _stack!;
    final count = stack.imageUrls.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141414),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          stack.name,
          style: const TextStyle(
            color: Color(0xFFF7F7F7),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_currentPage + 1} / $count',
                style: const TextStyle(color: Color(0xFF6B6B6B), fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showOpenInApp)
            _OpenInAppBanner(
              onOpen: _openInApp,
              onDismiss: () => setState(() => _showOpenInApp = false),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 700;
                final viewerWidth = isWide ? 600.0 : constraints.maxWidth;

                return Center(
                  child: SizedBox(
                    width: viewerWidth,
                    child: Column(
                      children: [
                        Expanded(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              PageView.builder(
                                controller: _pageController,
                                itemCount: count,
                                physics: const PageScrollPhysics(
                                  parent: ClampingScrollPhysics(),
                                ),
                                itemBuilder: (context, i) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        stack.imageUrls[i],
                                        fit: BoxFit.contain,
                                        loadingBuilder: (_, child, progress) {
                                          if (progress == null) return child;
                                          return const Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                              color: Color(0xFF7C3AED),
                                            ),
                                          );
                                        },
                                        errorBuilder: (_, __, ___) =>
                                            const Center(
                                          child: Icon(
                                              Icons.broken_image_outlined,
                                              color: Color(0xFF444444),
                                              size: 48),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              if (count > 1) ...[
                                Positioned(
                                  left: 8,
                                  child: _NavArrowButton(
                                    icon: Icons.chevron_left,
                                    enabled: _currentPage > 0,
                                    onTap: _goToPrev,
                                  ),
                                ),
                                Positioned(
                                  right: 8,
                                  child: _NavArrowButton(
                                    icon: Icons.chevron_right,
                                    enabled: _currentPage < count - 1,
                                    onTap: _goToNext,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (count > 1)
                          _ThumbnailStrip(
                            imageUrls: stack.imageUrls,
                            currentIndex: _currentPage,
                            scrollController: _thumbnailScrollController,
                            onTap: _jumpToPage,
                            thumbnailWidth: _thumbnailWidth,
                            thumbnailHeight: _thumbnailHeight,
                            spacing: _thumbnailSpacing,
                          ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NavArrowButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _NavArrowButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.25,
      duration: const Duration(milliseconds: 150),
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF2E2E2E), width: 1),
          ),
          child: Icon(icon, color: const Color(0xFFF7F7F7), size: 22),
        ),
      ),
    );
  }
}

class _ThumbnailStrip extends StatelessWidget {
  final List<String> imageUrls;
  final int currentIndex;
  final ScrollController scrollController;
  final ValueChanged<int> onTap;
  final double thumbnailWidth;
  final double thumbnailHeight;
  final double spacing;

  const _ThumbnailStrip({
    required this.imageUrls,
    required this.currentIndex,
    required this.scrollController,
    required this.onTap,
    required this.thumbnailWidth,
    required this.thumbnailHeight,
    required this.spacing,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: thumbnailHeight + 16,
      child: ListView.builder(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: spacing, vertical: 8),
        physics: const BouncingScrollPhysics(),
        itemCount: imageUrls.length,
        itemBuilder: (context, i) {
          final isActive = i == currentIndex;
          return GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: thumbnailWidth,
              margin: EdgeInsets.symmetric(horizontal: spacing / 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isActive
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF2E2E2E),
                  width: isActive ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Image.network(
                  imageUrls[i],
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFF1E1E1E),
                    child: const Icon(Icons.broken_image_outlined,
                        color: Color(0xFF444444), size: 20),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OpenInAppBanner extends StatelessWidget {
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  const _OpenInAppBanner({required this.onOpen, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Text(
            'Open in RecallOS app',
            style: TextStyle(color: Color(0xFFF7F7F7), fontSize: 13),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onOpen,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Open',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close, color: Color(0xFF6B6B6B), size: 18),
          ),
        ],
      ),
    );
  }
}
