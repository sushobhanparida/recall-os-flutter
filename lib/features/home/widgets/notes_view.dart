import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/screenshot_model.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../shared/widgets/empty_state.dart';

/// Provider for the user's saved notes (screenshots with non-null noteText).
final savedNotesProvider = FutureProvider<List<Screenshot>>((ref) async {
  return AppDatabase.instance.getSavedNotes();
});

/// The Notes tab body. Top: fanned/album hero card → opens note-picker.
/// Below: Pinterest-style grid of saved notes.
class NotesView extends ConsumerWidget {
  /// All screenshots tagged Notes — used to build the fan preview at top.
  final List<Screenshot> noteScreenshots;
  final ValueChanged<Screenshot> onOpenScreenshot;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const NotesView({
    super.key,
    required this.noteScreenshots,
    required this.onOpenScreenshot,
    this.shrinkWrap = false,
    this.physics,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedNotesAsync = ref.watch(savedNotesProvider);

    return CustomScrollView(
      shrinkWrap: shrinkWrap,
      physics: physics,
      slivers: [
        SliverToBoxAdapter(
          child: _FanHero(
            screenshots: noteScreenshots,
            onTap: () async {
              await context.push('/notes/picker');
              // ignore: unused_result
              ref.refresh(savedNotesProvider);
            },
          ),
        ),
        savedNotesAsync.when(
          loading: () => const SliverToBoxAdapter(
              child: SizedBox(
                  height: 80,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppColors.accent,
                    ),
                  ))),
          error: (e, _) => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $e',
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.error)),
            ),
          ),
          data: (notes) => notes.isEmpty
              ? const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.notes_rounded,
                    title: 'No notes saved yet',
                    subtitle: 'Tap the album above to convert a screenshot',
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                  sliver: _PinterestGrid(notes: notes, ref: ref),
                ),
        ),
      ],
    );
  }
}

// ── Fan / album hero ────────────────────────────────────────────────────────

class _FanHero extends StatelessWidget {
  final List<Screenshot> screenshots;
  final VoidCallback onTap;

  const _FanHero({required this.screenshots, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: AppColors.borderDefault, width: 1),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              SizedBox(
                width: 120,
                height: 120,
                child: _Fan(screenshots: screenshots),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Convert to note',
                          style: AppTypography.headingSm
                              .copyWith(color: AppColors.textPrimary)),
                      const SizedBox(height: 6),
                      Text(
                        'Pick a screenshot, edit the\nextracted text, save as a note.',
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome_outlined,
                                size: 12, color: AppColors.textPrimary),
                            const SizedBox(width: 5),
                            Text('Pick screenshot',
                                style: AppTypography.labelSm
                                    .copyWith(color: AppColors.textPrimary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fan extends StatelessWidget {
  final List<Screenshot> screenshots;
  const _Fan({required this.screenshots});

  @override
  Widget build(BuildContext context) {
    final sample = screenshots.take(4).toList();
    if (sample.isEmpty) {
      return Center(
        child: Container(
          width: 70,
          height: 100,
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: AppColors.borderDefault, width: 1),
          ),
          child:
              const Icon(Icons.image_outlined, color: AppColors.textMuted),
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        for (var i = sample.length - 1; i >= 0; i--)
          Transform.translate(
            offset: Offset(_offsetFor(i), 0),
            child: Transform.rotate(
              angle: _angleFor(i),
              child: _FanCard(uri: sample[i].uri),
            ),
          ),
      ],
    );
  }

  // Spread the cards left/right of center, fanning outward.
  double _offsetFor(int i) {
    switch (i) {
      case 0:
        return -18;
      case 1:
        return -6;
      case 2:
        return 8;
      case 3:
        return 22;
    }
    return 0;
  }

  double _angleFor(int i) {
    switch (i) {
      case 0:
        return -0.12;
      case 1:
        return -0.04;
      case 2:
        return 0.04;
      case 3:
        return 0.12;
    }
    return 0;
  }
}

class _FanCard extends StatelessWidget {
  final String uri;
  const _FanCard({required this.uri});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 104,
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderEmphasis, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDefault,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: uri.startsWith('http')
            ? Image.network(uri,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: AppColors.bgElevated))
            : Image.file(File(uri),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: AppColors.bgElevated)),
      ),
    );
  }
}

// ── Pinterest grid ──────────────────────────────────────────────────────────

class _PinterestGrid extends StatelessWidget {
  final List<Screenshot> notes;
  final WidgetRef ref;

  const _PinterestGrid({required this.notes, required this.ref});

  @override
  Widget build(BuildContext context) {
    // Distribute notes across two columns by index parity. Each column is a
    // simple Column — heights vary by note content, which gives the
    // staggered/Pinterest look without an extra dep.
    final left = <Screenshot>[];
    final right = <Screenshot>[];
    for (var i = 0; i < notes.length; i++) {
      (i.isEven ? left : right).add(notes[i]);
    }

    return SliverToBoxAdapter(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _NoteColumn(notes: left, ref: ref)),
          const SizedBox(width: 10),
          Expanded(child: _NoteColumn(notes: right, ref: ref)),
        ],
      ),
    );
  }
}

class _NoteColumn extends StatelessWidget {
  final List<Screenshot> notes;
  final WidgetRef ref;

  const _NoteColumn({required this.notes, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final n in notes) ...[
          _NoteCard(note: n, ref: ref),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _NoteCard extends ConsumerWidget {
  final Screenshot note;
  final WidgetRef ref;

  const _NoteCard({required this.note, required this.ref});

  // Cycle through 4 hand-picked sticky-note-ish backgrounds so the wall
  // isn't a single dull tone — Google Keep style.
  Color _bg() {
    final hash = (note.id ?? 0) % 4;
    switch (hash) {
      case 0:
        return AppColors.noteBgMoss;
      case 1:
        return AppColors.noteBgWine;
      case 2:
        return AppColors.noteBgNavy;
      default:
        return AppColors.tagNoteMuted; // sand
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef _) {
    final text = note.noteText ?? '';
    return GestureDetector(
      onTap: () async {
        await context.push('/notes/edit/${note.id}');
        // ignore: unused_result
        ref.refresh(savedNotesProvider);
      },
      child: Container(
        constraints: const BoxConstraints(maxHeight: 120),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _bg(),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderDefault, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note.noteTitle != null && note.noteTitle!.trim().isNotEmpty) ...[
              Text(
                note.noteTitle!,
                style: AppTypography.headingSm
                    .copyWith(color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
            ],
            Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.textPrimary, height: 1.35),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.image_outlined,
                    size: 11, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    DateFormat('MMM d').format(note.createdAt),
                    style: AppTypography.monoSm
                        .copyWith(color: AppColors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
