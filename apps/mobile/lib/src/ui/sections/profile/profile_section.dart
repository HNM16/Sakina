import 'package:flutter/material.dart';

import '../section.dart';
import 'profile_screen.dart';

/// The user, and the settings that belong to them.
class ProfileSection extends SakinaSection {
  const ProfileSection();

  @override
  String get id => 'profile';

  @override
  String get labelKey => 'profile';

  @override
  IconData get icon => Icons.person_outline;

  @override
  IconData get selectedIcon => Icons.person;

  @override
  Widget build(BuildContext context, SectionScope scope) => ProfileScreen(
        selfId: scope.repository.selfId,
        selfName: scope.selfName,
        language: scope.language,
        onLanguageChanged: scope.onLanguageChanged,
        themeId: scope.themeId,
        onThemeChanged: scope.onThemeChanged,
        onSignOut: scope.onSignOut,
      );
}
