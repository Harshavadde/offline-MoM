import 'package:flutter/material.dart';

/// A brief fade+rise entrance, played once as [child] first appears (V2.3,
/// Premium Product Experience) - the same shape Workspace Chat's message
/// bubbles already use (`_EntranceFade` in chat_screen.dart), generalized
/// here for list/grid items elsewhere in the app. [delay] lets a list
/// stagger its items (index * a small step) so content settles in as a
/// wave rather than all at once; deliberately short and linear-feeling so
/// it reads as polish, not a loading delay.
class EntranceFade extends StatefulWidget {
  const EntranceFade({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 220),
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  @override
  State<EntranceFade> createState() => _EntranceFadeState();
}

class _EntranceFadeState extends State<EntranceFade> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
