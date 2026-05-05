import 'package:flutter/material.dart';
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
  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _fetchStack();
    _pageController.addListener(() {
      final page = _pageController.page?.round() ?? 0;
      if (page != _currentPage) setState(() => _currentPage = page);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetchStack() async {
    try {
      final data = await Supabase.instance.client
          .from('shared_stacks')
          .select('id, stack_name, image_urls')
          .eq('id', widget.stackId)
          .maybeSingle();
      setState(() {
        if (data != null) {
          _stack = SharedStack.fromMap(data);
        } else {
          _error = true; // row not found (deleted or never created)
        }
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('[StackViewer] fetch failed: $e\n$st');
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  void _goToPrev() {
    if (_currentPage > 0) {
      _pageController.animateToPage(
        _currentPage - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToNext() {
    final count = _stack?.imageUrls.length ?? 0;
    if (_currentPage < count - 1) {
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
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
                '$count screenshot${count == 1 ? '' : 's'}',
                style: const TextStyle(color: Color(0xFF6B6B6B), fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;
          final viewerWidth = isWide ? 600.0 : constraints.maxWidth;

          return Center(
            child: SizedBox(
              width: viewerWidth,
              child: Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      // Tap left third → prev, right third → next (for desktop)
                      onTapUp: (details) {
                        final x = details.localPosition.dx;
                        if (x < viewerWidth / 3) {
                          _goToPrev();
                        } else if (x > viewerWidth * 2 / 3) {
                          _goToNext();
                        }
                      },
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: count,
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
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.broken_image_outlined,
                                      color: Color(0xFF444444), size: 48),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  // Page indicator
                  if (count > 1)
                    _PageDots(
                        count: count, currentIndex: _currentPage),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int currentIndex;

  const _PageDots({required this.count, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    // Clamp to at most 9 dots; show ellipsis behaviour via opacity instead
    final show = count <= 9 ? count : 9;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(show, (i) {
          final isActive = i == currentIndex.clamp(0, show - 1);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: isActive ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF7C3AED)
                  : const Color(0xFF383838),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }
}
