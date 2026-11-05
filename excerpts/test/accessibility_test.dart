import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lari/l10n/app_localizations.dart';
import 'package:lari/screens/home_screen.dart';
import 'package:lari/services/database_service.dart';
import 'package:lari/services/locale_provider.dart';
import 'package:lari/services/theme_provider.dart';
import 'package:lari/theme/app_theme.dart';
import 'package:lari/theme/neo_colors.dart';
import 'package:lari/widgets/photo_viewer.dart';

/// Akadálymentesítési ellenőrzések a Flutter beépített irányelveivel.
/// Ezek objektívek: a widget-fából számolnak, nem a véleményemből.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetForTests();
    AppLocalizations.setLocale('hu');
    await initializeDateFormatting();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ],
        child: MaterialApp(theme: AppTheme.lightTheme, home: const HomeScreen()),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// A néző gombsora MINDKÉT témában. A sötét téma külön kell: a hiba is
  /// ott volt, és a főképernyőt csak világosban pumpáljuk.
  ///
  /// A gombok sötét alapon ülnek (a teljes képernyős néző háttere mindkét
  /// témában sötét), ezért a mögöttes felületet is sötétre állítjuk —
  /// különben a kontraszt-ellenőrzés nem azt mérné, amit a felhasználó lát.
  Future<void> pumpPhotoButtons(WidgetTester tester, ThemeData theme) async {
    final c = theme.extension<NeoColors>()!;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          backgroundColor: const Color(0xFF111114),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MediaViewerStage.action(
                icon: Icons.camera_alt_rounded,
                label: AppLocalizations.get('newPhoto'),
                fill: c.cyan,
                ink: c.onLight,
                onTap: () {},
              ),
              MediaViewerStage.action(
                icon: Icons.delete_outline_rounded,
                label: AppLocalizations.get('delete'),
                fill: const Color(0x66000000),
                ink: const Color(0xFFFBFAF6),
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  // A fotónéző gombjain sötét témában majdnem FEHÉR felirat ült a cián és a
  // rózsaszín felületen, mert a kód a `c.black` getterre épült — az pedig az
  // `ink`-et adja vissza, ami sötét témában világos. Ez a teszt a hibás
  // változaton elbukik.
  testWidgets('a néző gombjainak kontrasztja megfelel — világos', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpPhotoButtons(tester, AppTheme.lightTheme);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('a néző gombjainak kontrasztja megfelel — sötét', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpPhotoButtons(tester, AppTheme.darkTheme);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('a koppintási célpontok elérik az Android minimumot', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpHome(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('minden koppintható elemnek van felolvasható címkéje', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpHome(tester);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('a szövegek kontrasztja megfelel', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpHome(tester);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('a tétel kapcsolóként, állapottal jelenik meg', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpHome(tester);
    // A címkéhez több csomópont is tartozhat (a húzásindító és a kártya is),
    // ezért azt nézzük, hogy legalább az egyik KAPCSOLÓ-ként viselkedik.
    final finder = find.bySemanticsLabel(
      RegExp(AppLocalizations.get('seed_oven_off')),
    );
    expect(finder, findsWidgets);
    final nodes = [
      for (final e in finder.evaluate()) tester.getSemantics(find.byWidget(e.widget)),
    ];
    // Tristate: none = nincs kapcsoló-állapot, false_/true_ = van, és mi.
    expect(
      nodes.any((n) => n.flagsCollection.isToggled != Tristate.none),
      isTrue,
      reason: 'egyik csomópontnak sincs kapcsoló-állapota',
    );
    expect(
      nodes.every((n) => n.flagsCollection.isToggled != Tristate.isTrue),
      isTrue,
      reason: 'induláskor egyik tétel sem lehet bepipálva',
    );
    handle.dispose();
  });
}
