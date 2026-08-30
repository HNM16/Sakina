import 'section.dart';
import 'calls/calls_section.dart';
import 'chats/chats_section.dart';
import 'explore/explore_section.dart';
import 'profile/profile_section.dart';

/// The tabs, in the order they appear.
///
/// This list is the only place the app knows how many sections there are.
/// Adding one is a file under `ui/sections/` and a line here; reordering is
/// reordering this list. Nothing else — not the shell, not the bar, not the
/// navigators — counts or names them.
///
/// Chats is first because it is what the app is for, and because the hardware
/// back button falls back to it (see `shell.dart`).
const sakinaSections = <SakinaSection>[
  ChatsSection(),
  CallsSection(),
  ExploreSection(),
  ProfileSection(),
];
