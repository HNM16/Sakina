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
import 'package:sakina/src/ui/sections/sections.dart';
import 'package:sakina/src/ui/themes/themes.dart';

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

  group('Sections', () {
    test('every section declares a distinct id and a label key', () {
      final ids = sakinaSections.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length,
          reason: 'ids key the navigators and the page storage; a collision '
              'would hand one section another\'s stack');
      for (final section in sakinaSections) {
        expect(section.id, isNotEmpty);
        expect(section.labelKey, isNotEmpty);
        expect(section.icon, isNot(section.selectedIcon),
            reason: 'selection has to read without relying on the accent colour');
      }
    });

    test('chats is first, because back falls through to it', () {
      expect(sakinaSections.first.id, 'chats');
    });

    testWidgets('every section label is translated in all three languages',
        (tester) async {
      for (final code in ['ru', 'tg', 'en']) {
        await tester.pumpWidget(host(
          Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  for (final section in sakinaSections)
                    Text(L10n.of(context).t(section.labelKey)),
                ],
              ),
            ),
          ),
          locale: Locale(code),
        ));
        await tester.pumpAndSettle();
        for (final section in sakinaSections) {
          // t() returns the key itself on a miss, so a missing translation
          // shows up as a tab labelled `explore`.
          expect(find.text(section.labelKey), findsNothing,
              reason: '${section.id} is untranslated in $code');
        }
      }
    });
  });

  group('Themes', () {
    test('ids are distinct and stable-looking', () {
      final ids = sakinaThemes.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length,
          reason: 'the id is what gets written to disk; a collision would hand '
              'a user a different theme than the one they chose');
      expect(ids, everyElement(isNotEmpty));
    });

    test('there is at least one light and one dark, so "match the phone" works',
        () {
      // SakinaThemes.systemLight/systemDark use firstWhere, which throws when
      // a brightness is unrepresented — that would be a crash on launch for
      // everyone following the phone.
      expect(() => SakinaThemes.systemLight, returnsNormally);
      expect(() => SakinaThemes.systemDark, returnsNormally);
    });

    test('an unknown id falls back to following the phone', () {
      // A theme withdrawn in an update must not crash the app on launch for
      // everyone who had chosen it.
      expect(SakinaThemes.byId('a-theme-we-removed'), isNull);
      expect(SakinaThemes.byId(null), isNull);
      expect(SakinaThemes.byId(sakinaThemes.first.id), isNotNull);
    });

    test('every theme builds, and carries the palette every widget reads', () {
      for (final theme in sakinaThemes) {
        final data = theme.build();
        expect(data.brightness, theme.brightness, reason: theme.id);
        expect(data.extension<SakinaPalette>(), isNotNull,
            reason: '${theme.id} must carry SakinaPalette — every widget in '
                'the app reads colour through it, so a theme without one '
                'renders in the fallback and looks like a different app');
      }
    });

    testWidgets('every theme label is translated in all three languages',
        (tester) async {
      for (final code in ['ru', 'tg', 'en']) {
        await tester.pumpWidget(host(
          Builder(
            builder: (context) => Scaffold(
              body: Column(children: [
                for (final theme in sakinaThemes)
                  Text(L10n.of(context).t(theme.labelKey)),
              ]),
            ),
          ),
          locale: Locale(code),
        ));
        await tester.pumpAndSettle();
        for (final theme in sakinaThemes) {
          expect(find.text(theme.labelKey), findsNothing,
              reason: '${theme.id} is untranslated in $code');
        }
      }
    });
  });
}
