// Runs the real app on a Linux/macOS/Windows desktop, for looking at.
//
// Deliberately outside `lib/`, and its one dependency is a dev dependency, so
// none of this can reach a phone. `flutter build linux -t tool/desktop_harness.dart`.
//
// Why it needs to exist: sqflite is an Android/iOS plugin. On a desktop there
// is no platform channel behind it, so `LocalStore.open()` throws
// "databaseFactory not initialized" and startup dies before the first frame.
// `sqflite_common_ffi` supplies the same API backed by the sqlite3 C library
// that is already on the machine, which is the documented way to run a mobile
// app on a desktop.
//
// Everything else is the real thing: the real main(), the real theme, the real
// widgets. Firebase is the only other plugin missing here and main() already
// treats push as optional, so it degrades to "no notifications" on its own.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sakina/main.dart' as app;

Future<void> main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  await app.main();
}
