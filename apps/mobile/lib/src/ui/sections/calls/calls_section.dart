import 'package:flutter/material.dart';

import '../section.dart';
import 'calls_screen.dart';

/// Voice and video. Designed in docs/CALLS.md, not built.
class CallsSection extends SakinaSection {
  const CallsSection();

  @override
  String get id => 'calls';

  @override
  String get labelKey => 'calls';

  @override
  IconData get icon => Icons.call_outlined;

  @override
  IconData get selectedIcon => Icons.call;

  @override
  Widget build(BuildContext context, SectionScope scope) => const CallsScreen();
}
