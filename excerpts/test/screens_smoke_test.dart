import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lari/l10n/app_localizations.dart';
import 'package:lari/screens/home_screen.dart';
import 'package:lari/services/locale_provider.dart';
import 'package:lari/services/theme_provider.dart';
import 'package:lari/theme/app_theme.dart';
import 'package:lari/widgets/animated_splash.dart';
import 'package:lari/widgets/language_picker_screen.dart';
import 'package:lari/widgets/onboarding_screen.dart';

/// Füst-tesztek: minden képernyőt felépítünk és végigpörgetünk.
///
/// A widget-teszt automatikusan elbukik, ha közben BÁRMILYEN kivétel vagy
/// layout-assertion keletkezik — így ezek pontosan azokat a hibákat fogják
/// meg, amelyek eddig csak a telefonon derültek ki:
///  * elrendezési hiba (pl. Spacer görgethetőn belül → az egész képernyő
///    használhatatlanná válik),
///  * túlcsordulás kis kijelzőn,
///  * ParentDataWidget hibás beágyazása (Positioned nem Stack alatt).
Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      locale: const Locale('hu'),
      supportedLocales:
          AppLocalizations.supportedLocales.map((c) => Locale(c)).toList(),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    ),
  );
}

/// Ugyanaz, mint a [_wrap], de a RENDSZER betűméretét is felnagyítja.
///
/// A Lari nem írja felül a `textScaler`-t, vagyis tiszteletben tartja az
/// Android „Betűméret” beállítását. Ez szándékos — a célközönség egy része
/// nagyobb betűvel használja a telefonját —, de azt jelenti, hogy nálunk
/// kisebb betűvel tesztelt elrendezés náluk szétcsúszhat.
Widget _wrapScaled(Widget child, double scale) => MediaQuery(
  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
  child: _wrap(child),
);

/// Ideiglenesen kis kijelzőt állít be (a legszűkebb reális Android méret).
void _useSmallScreen(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(320, 480);
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setLocale('hu');
    // Ugyanaz, amit a main() csinál: a dátumformázás nyelvenkénti adatot
    // igényel, enélkül a DateFormat.yMd(locale) kivételt dob.
    await initializeDateFormatting();
  });

  testWidgets('nyelvválasztó felépül normál kijelzőn', (tester) async {
    await tester.pumpWidget(_wrap(LanguagePickerScreen(onDone: () {})));
    await tester.pumpAndSettle();
    expect(find.text('Magyar'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
  });

  testWidgets('nyelvválasztó kis kijelzőn sem csordul túl és görgethető', (
    tester,
  ) async {
    _useSmallScreen(tester);
    await tester.pumpWidget(_wrap(LanguagePickerScreen(onDone: () {})));
    await tester.pumpAndSettle();
    // Görgethetőnek kell lennie, hogy minden nyelv elérhető maradjon.
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Magyar'), findsOneWidget);
  });

  testWidgets('nyelvválasztó gombja hívja az onDone-t', (tester) async {
    var done = false;
    await tester.pumpWidget(_wrap(LanguagePickerScreen(onDone: () => done = true)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
  });

  testWidgets('az útmutató mind a 9 oldala felépül', (tester) async {
    await tester.pumpWidget(_wrap(OnboardingScreen(onDone: () {})));
    // pumpAndSettle NEM használható: a demó-animációk végtelenül ismétlődnek,
    // így a widget-fa sosem „nyugszik meg”.
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.text(AppLocalizations.get('next')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }
    // Az utolsó oldalon a gomb felirata „Kezdés”-re vált.
    expect(find.text(AppLocalizations.get('start')), findsOneWidget);
  });

  testWidgets('az útmutató kis kijelzőn is felépül', (tester) async {
    _useSmallScreen(tester);
    await tester.pumpWidget(_wrap(OnboardingScreen(onDone: () {})));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(AppLocalizations.get('onbTitle1')), findsOneWidget);
  });

  testWidgets('az indítóképernyő teljes animációja hiba nélkül lefut', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(AnimatedSplash(onDone: () {})));
    // Apró lépésekben, hogy a rövid életű fázisok (pl. a csobbanás) is
    // ténylegesen kirajzolódjanak legalább egy képkockán.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  // Elfér-e minden a legkeskenyebb kijelzőn: a tétel-kártya tartalma és
  // odalent a műveletgombok felirata. A Row túlcsordulása a widget-tesztben
  // kivétel, tehát ez a teszt elbukik, ha bármelyik sor nem fér ki.
  testWidgets('a főképernyő a legkeskenyebb kijelzőn sem csordul túl', (
    tester,
  ) async {
    _useSmallScreen(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(
      find.text(AppLocalizations.get('seed_oven_off')),
      findsAtLeastNWidgets(1),
    );
  });

  // 2.0× a TETŐ: a [TextScaleProvider] ennél fogja meg a rendszer méretének
  // és a menüből választott szorzónak a SZORZATÁT. Ha ez kifér, minden kifér.
  // A legrosszabb reális eset egyszerre: legszűkebb kijelző ÉS nagy
  // rendszerbetű. Ez fogja meg azt, amit a fejlesztői gépen sosem látunk.
  testWidgets('a főképernyő keskeny kijelzőn + 2.0× betűvel sem csordul túl', (
    tester,
  ) async {
    _useSmallScreen(tester);
    await tester.pumpWidget(_wrapScaled(const HomeScreen(), 2.0));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(
      find.text(AppLocalizations.get('seed_oven_off')),
      findsAtLeastNWidgets(1),
    );
    // Az állapotsávban HÁROM elem van: a sáv, a megosztás és a videógomb.
    // Ez volt a szűk hely, amit a videó tervénél kockázatként jeleztem —
    // ha egyszer nem fér ki, ez a teszt bukik el, nem a felhasználó telefonja.
    expect(
      find.bySemanticsLabel(AppLocalizations.get('videoRecord')),
      findsOneWidget,
    );
  });

  testWidgets('az útmutató a legnagyobb betűmérettel sem csordul túl', (
    tester,
  ) async {
    await tester.pumpWidget(_wrapScaled(OnboardingScreen(onDone: () {}), 2.0));
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.text(AppLocalizations.get('next')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.text(AppLocalizations.get('start')), findsOneWidget);
  });

  testWidgets('a főképernyő betölti az alapértelmezett helyszíneket', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const HomeScreen()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    // Egyes szövegek többször is szerepelnek a fában (a helyszín neve a fülön
    // és az összecsukott fejlécben is, a tételek pedig a képernyőn kívüli
    // megosztás-kártyán is), ezért „legalább egy” a feltétel.
    expect(
      find.text(AppLocalizations.get('loc_home')),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.text(AppLocalizations.get('loc_work')),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.text(AppLocalizations.get('seed_oven_off')),
      findsAtLeastNWidgets(1),
    );
  });
}
