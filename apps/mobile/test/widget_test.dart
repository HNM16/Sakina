// Widget tests: the cheapest way to actually *run* this code.
//
// These need no device, no emulator and no platform SDK — `flutter test` builds
// the widgets, lays them out and dispatches gestures in a headless harness. For
// a project whose client had never been executed at all, that is most of the
// distance between "the types agree" and "it works".
//
// The first test here is a regression for a bug that shipped and survived every
// other check: `flutter analyze` was clean, `test:dart` was clean, and the
// unread badge still rendered as a firuza bar straight across the chat name.
// Only running it showed that.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sakina/src/l10n.dart';
import 'package:sakina/src/motion.dart';
import 'package:sakina/src/theme.dart';
import 'package:sakina/src/ui/indicators.dart';

/// The app's own chrome, so tests exercise the real theme rather than Material
/// defaults. `home` is supplied per test.
Widget host(Widget home, {Locale locale = const Locale('ru')}) {
  return MaterialApp(
    theme: SakinaTheme.night(),
    locale: locale,
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: localizationDelegates,
    home: home,
  );
}

/// A screen that pushes another one, for the navigation tests.
Widget pusher() => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              SakinaPageRoute<void>(
                builder: (_) => Scaffold(
                  // Keyed so the tests can measure the *page*. Measuring a
                  // centred Text instead reports the text's own offset, which
                  // is a constant and makes any assertion about travel pass
                  // whether the page moved or not.
                  key: const ValueKey('second'),
                  appBar: AppBar(title: const Text('second')),
                  body: const Center(child: Text('body')),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

void main() {
  group('UnreadBadge', () {
    testWidgets('sizes to its own digits inside a ListTile trailing slot',
        (tester) async {
      // The slot offers the full width of the row. A badge that accepts it
      // covers the chat name — which is exactly what happened.
      await tester.pumpWidget(host(
        const Scaffold(
          body: ListTile(title: Text('Нозанин'), trailing: UnreadBadge(count: 4)),
        ),
      ));
      await tester.pumpAndSettle();

      final badge = tester.getSize(find.byType(UnreadBadge));
      expect(badge.width, lessThan(48),
          reason: 'a badge wider than this is the full-row bar bug returning');
      expect(badge.width, greaterThanOrEqualTo(20), reason: 'minWidth: 20');
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('a zero count occupies nothing', (tester) async {
      await tester.pumpWidget(host(
        const Scaffold(body: Center(child: UnreadBadge(count: 0))),
      ));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(UnreadBadge)), Size.zero);
    });
  });

  group('L10n', () {
    testWidgets('resolves each language in its own script', (tester) async {
      for (final (code, expected) in [
        ('ru', 'Чаты'),
        ('tg', 'Сӯҳбатҳо'),
        ('en', 'Chats'),
      ]) {
        await tester.pumpWidget(host(
          Builder(builder: (c) => Scaffold(body: Text(L10n.of(c).t('chats')))),
          locale: Locale(code),
        ));
        await tester.pumpAndSettle();
        expect(find.text(expected), findsOneWidget, reason: 'chats in $code');
      }
    });

    testWidgets('an unknown key returns itself rather than crashing',
        (tester) async {
      // The documented failure mode: a button labelled `chanel_name`. Worth
      // pinning, because it is what makes a typo survive to a screenshot.
      await tester.pumpWidget(host(
        Builder(builder: (c) => Scaffold(body: Text(L10n.of(c).t('no_such_key')))),
      ));
      expect(find.text('no_such_key'), findsOneWidget);
    });
  });

  group('Navigation', () {
    final page = find.byKey(const ValueKey('second'));

    testWidgets('a pushed route slides the full width in from the trailing edge',
        (tester) async {
      await tester.pumpWidget(host(pusher()));
      final width = tester.getSize(find.byType(Navigator)).width;

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final early = tester.getTopLeft(page).dx;
      expect(early, greaterThan(width * 0.5),
          reason: 'a frame in it should still be mostly off-screen — a full '
              'width slide, not the 18% nudge this replaced');

      await tester.pump(const Duration(milliseconds: 160));
      expect(tester.getTopLeft(page).dx, lessThan(early),
          reason: 'and travelling toward the leading edge');

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(page).dx, 0, reason: 'arriving flush');

      // And back out again, via the button in the corner.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(page, findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('under reduce-motion the route swaps with nothing moving',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      await tester.pumpWidget(host(pusher()));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // Flush on the very first frame: no travel at all, which is the whole
      // point of G2 — shortening an animation is not disabling it.
      expect(tester.getTopLeft(page).dx, 0);
      await tester.pump(const Duration(milliseconds: 160));
      expect(tester.getTopLeft(page).dx, 0);
    });
  });
}
