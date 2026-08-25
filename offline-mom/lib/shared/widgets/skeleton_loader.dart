import 'package:flutter/material.dart';

/// A gentle, looping opacity pulse - the base building block for skeleton
/// loading placeholders (V2.3, Premium Product Experience). Built from
/// [AnimationController] alone (no shimmer package) since a slow opacity
/// breathe reads as "content is on its way" just as clearly as a moving
/// gradient, without pulling in a new dependency for it.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  late final Animation<double> _opacity =
      Tween<double>(begin: 0.55, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}

/// One placeholder bar, sized and rounded to match this app's body-text
/// rhythm - used to stand in for a title or subtitle line while real
/// content loads.
class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, this.height = 14});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// A placeholder shaped exactly like [KnowledgeSourceCard]
/// (lib/shared/widgets/knowledge_source_card.dart) - same icon-box size,
/// same corner radius, same two-line layout - so a loading list doesn't
/// visibly "jump" in shape once real cards replace it. Shown in place of a
/// bare spinner wherever a list is the very first thing on a screen
/// (Home's Recent Meetings, History, Documents) - per V2.3's brief,
/// skeletons over spinners wherever practical.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Pulse(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBar(width: 160),
                    SizedBox(height: 8),
                    _SkeletonBar(width: 100, height: 11),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 56,
                height: 22,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A short column of [SkeletonCard]s, each one lightly staggered so the
/// whole list breathes together instead of pulsing in perfect lockstep -
/// used wherever a list-style screen's loading state previously showed
/// just a spinner.
class SkeletonCardList extends StatelessWidget {
  const SkeletonCardList({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          const SkeletonCard(),
        ],
      ],
    );
  }
}
