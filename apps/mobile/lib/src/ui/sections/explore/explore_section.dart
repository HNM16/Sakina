import 'package:flutter/material.dart';

import '../section.dart';
import 'explore_screen.dart';

/// Everything that is not a conversation: channels, posts, video, and in time
/// the mini-apps that make this a super-app.
class ExploreSection extends SakinaSection {
  const ExploreSection();

  @override
  String get id => 'explore';

  @override
  String get labelKey => 'explore';

  @override
  IconData get icon => Icons.explore_outlined;

  @override
  IconData get selectedIcon => Icons.explore;

  @override
  Widget build(BuildContext context, SectionScope scope) => const ExploreScreen();
}
