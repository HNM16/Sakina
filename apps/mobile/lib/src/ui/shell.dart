import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../motion.dart';
import 'sections/section.dart';
import 'sections/sections.dart';

/// The four-section shell: a bar at the bottom, a section above it.
///
/// Three things it is responsible for, and nothing else — every other decision
/// belongs to a section, which is what keeps this file from growing every time
/// the app does.
///
///  1. **A navigator per section.** Each keeps its own stack, so opening a chat,
///     switching to Profile and switching back leaves you in the chat. One
///     shared navigator would make a tab change destroy the stack under it,
///     which is the single most-noticed difference between an app that feels
///     built and one that feels assembled.
///  2. **The fade-through** between sections. See [SakinaMotion.sectionOut].
///  3. **Back**: pop within the section, then fall back to Chats, then leave.
///     Telegram's behaviour, and the one people already have in their thumbs.
class SakinaShell extends StatefulWidget {
  const SakinaShell({super.key, required this.scope});

  final SectionScope scope;

  @override
  State<SakinaShell> createState() => _SakinaShellState();
}

class _SakinaShellState extends State<SakinaShell> {
  /// Keyed by section id rather than index so reordering [sakinaSections]
  /// cannot silently hand one section another's stack.
  late final Map<String, GlobalKey<NavigatorState>> _navigators = {
    for (final section in sakinaSections)
      section.id: GlobalKey<NavigatorState>(debugLabel: section.id),
  };

  int _index = 0;

  void _select(int next) {
    if (next == _index) {
      // A second tap on the section you are already in pops it to its root.
      // Standard on both platforms, and the fastest way out of a deep stack.
      _navigators[sakinaSections[next].id]?.currentState?.popUntil((r) => r.isFirst);
      return;
    }
    SakinaHaptics.threshold(context);
    setState(() => _index = next);
  }

  /// The hardware back button, and the gesture on Android.
  void _onPop(bool didPop, Object? _) {
    if (didPop) return;

    final navigator = _navigators[sakinaSections[_index].id]?.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }
    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return PopScope(
      // Always false: back is decided in [_onPop], because what it means
      // depends on which section is showing and how deep it is.
      canPop: false,
      onPopInvokedWithResult: _onPop,
      child: Scaffold(
        body: _SectionFade(
          index: _index,
          children: [
            for (final section in sakinaSections)
              // Each section's whole subtree keeps its state while the others
              // are off screen — scroll positions, open chats, half-typed
              // messages.
              Navigator(
                key: _navigators[section.id],
                onGenerateRoute: (settings) => MaterialPageRoute<void>(
                  settings: settings,
                  builder: (context) => section.build(context, widget.scope),
                ),
              ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: [
            for (final section in sakinaSections)
              NavigationDestination(
                icon: Icon(section.icon),
                selectedIcon: Icon(section.selectedIcon),
                label: l10n.t(section.labelKey),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fade-through between siblings: out, swap, in.
///
/// Not a cross-fade. The outgoing section is gone before the incoming one
/// starts, so there is never a frame with two screens ghosted over each other —
/// which is what makes a cross-fade read as cheap.
///
/// The swap is an [IndexedStack] underneath, so state survives; only the
/// opacity and scale animate. Doing it the obvious way, with an
/// AnimatedSwitcher over the section widget, would rebuild the subtree and
/// throw away everything the section was holding.
class _SectionFade extends StatefulWidget {
  const _SectionFade({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_SectionFade> createState() => _SectionFadeState();
}

class _SectionFadeState extends State<_SectionFade> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SakinaMotion.sectionIn,
    reverseDuration: SakinaMotion.sectionOut,
    value: 1,
  );

  /// What is actually on screen, which lags [widget.index] by the length of the
  /// outgoing half.
  late int _shown = widget.index;

  @override
  void didUpdateWidget(_SectionFade old) {
    super.didUpdateWidget(old);
    if (widget.index == old.index) return;

    if (SakinaMotion.reduced(context)) {
      // G2: removed, not shortened. The section swaps and nothing moves.
      setState(() => _shown = widget.index);
      _controller.value = 1;
      return;
    }

    _controller.reverse().whenComplete(() {
      if (!mounted) return;
      setState(() => _shown = widget.index);
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: SakinaMotion.settle,
      reverseCurve: SakinaMotion.leave,
    );

    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween(begin: SakinaMotion.sectionScaleFrom, end: 1.0).animate(curved),
        child: IndexedStack(index: _shown, children: widget.children),
      ),
    );
  }
}
