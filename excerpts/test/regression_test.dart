import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lari/l10n/app_localizations.dart';
import 'package:lari/models/location.dart';
import 'package:lari/screens/home_screen.dart';
import 'package:lari/services/backup_service.dart';
import 'package:lari/services/database_service.dart';
import 'package:lari/services/date_display.dart';
import 'package:lari/services/error_log.dart';
import 'package:lari/services/locale_provider.dart';
import 'package:lari/services/media_store.dart';
import 'package:lari/services/text_scale_provider.dart';
import 'package:lari/services/theme_provider.dart';
import 'package:lari/theme/app_theme.dart';
import 'package:lari/widgets/app_menu_button.dart';
import 'package:lari/widgets/display_name.dart';

/// Olyan hibák, amelyeket a `flutter analyze` és a korábbi tesztek EGYIKE SEM
/// fogott meg — mind a négy csendben rossz viselkedés volt, nem összeomlás.
/// Ezért kaptak külön tesztet: a csendes hiba az, ami visszacsúszik.

Widget _wrap(Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
    ChangeNotifierProvider(create: (_) => LocaleProvider()),
  ],
  child: MaterialApp(theme: AppTheme.lightTheme, home: child),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetForTests();
    MediaStore.setDirectoryForTests(null);
    AppLocalizations.setLocale('hu');
    await initializeDateFormatting();
  });

  group('Helyszín átnevezése', () {
    test('a copyWith TÖRLI a fordítási kulcsot, ha null-t kap', () {
      final home = Location(id: 'h', name: 'Home', translationKey: 'loc_home');
      final renamed = home.copyWith(name: 'Nyaraló', translationKey: null);
      expect(renamed.translationKey, isNull);
      expect(renamed.name, 'Nyaraló');
    });

    test('a meg nem adott kulcs viszont megmarad', () {
      final home = Location(id: 'h', name: 'Home', translationKey: 'loc_home');
      expect(home.copyWith(sortOrder: 3).translationKey, 'loc_home');
    });

    test('átnevezés után a saját név látszik, nem a fordítás', () {
      final home = Location(id: 'h', name: 'Home', translationKey: 'loc_home');
      expect(locDisplayName(home), 'Otthon');
      final renamed = home.copyWith(name: 'Nyaraló', translationKey: null);
      expect(locDisplayName(renamed), 'Nyaraló');
    });
  });

  group('Törlés-tipp az első indításnál', () {
    // A törlés csak balra húzással megy, és a felületen semmi nem utalt rá.
    // Egyszer megmutatjuk — de tényleg csak egyszer.
    testWidgets('először megjelenik, másodszor már nem', (tester) async {
      await tester.pumpWidget(_wrap(const HomeScreen()));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(AppLocalizations.get('deleteHint')), findsOneWidget);

      // A képernyő eldobása után újra felépítjük, UGYANAZZAL a tárolóval.
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await tester.pumpWidget(_wrap(const HomeScreen()));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(AppLocalizations.get('deleteHint')), findsNothing);
    });
  });

  group('Helyszín videója', () {
    // A videó életciklusa a FOTÓKÉ: az adott induláshoz tartozik, az „Új nap"
    // törli, és a mentésfájl nem viszi. Ezek a tesztek a tárolási réteget
    // őrzik — a felvevő felület még nincs kész.
    Location home() => Location(
      id: 'h',
      name: 'Otthon',
      videoPath: 'video_1.mp4',
    );

    test('a copyWith TÖRLI a hivatkozást, ha null-t kap', () {
      expect(home().copyWith(videoPath: null).videoPath, isNull);
    });

    test('a meg nem adott hivatkozás megmarad', () {
      expect(home().copyWith(sortOrder: 3).videoPath, 'video_1.mp4');
    });

    test('a régi mentésben nincs video_path — ez nem hiba', () {
      final old = Location.fromMap({
        'id': 'h',
        'name': 'Otthon',
        'sort_order': 0,
      });
      expect(old.videoPath, isNull);
    });

    test('oda-vissza alakítás megőrzi a hivatkozást', () {
      expect(Location.fromMap(home().toMap()).videoPath, 'video_1.mp4');
    });

    test('a mentésfájl NEM viszi a videót', () async {
      DatabaseService.resetForTests();
      SharedPreferences.setMockInitialValues({});
      await DatabaseService.getLocations(); // lusta init + alapértelmezések
      final locations = await DatabaseService.getLocations();
      await DatabaseService.updateLocation(
        locations.first.copyWith(videoPath: 'video_1.mp4'),
      );

      final json = await DatabaseService.exportData();
      expect(json.contains('video_1.mp4'), isFalse);
      expect(json.contains('video_path'), isFalse);

      // A hivatkozás viszont a KÉSZÜLÉKEN megmarad — csak az exportból
      // marad ki, nem az adatbázisból.
      final after = await DatabaseService.getLocations();
      expect(after.first.videoPath, 'video_1.mp4');
    });
  });

  group('Betűméret', () {
    // A menüből választott méret SZORZÓ: a rendszer beállítását szorozza,
    // nem írja felül. Aki a telefonján már nagyra állította, nem veszíthet.
    test('a rendszer méretét megszorozza, nem lecseréli', () {
      final x = TextScaleProvider.effectiveScale(
        const TextScaler.linear(1.3),
        TextScaleOption.normal.factor,
      );
      expect(x, closeTo(1.3, 0.001));

      final y = TextScaleProvider.effectiveScale(
        const TextScaler.linear(1.3),
        TextScaleOption.large.factor,
      );
      expect(y, greaterThan(1.3));
    });

    test('a szorzat 2.0-nál megáll', () {
      final x = TextScaleProvider.effectiveScale(
        const TextScaler.linear(2.0),
        TextScaleOption.huge.factor,
      );
      expect(x, 2.0);
    });

    // A korlát a SZORZATRA vonatkozik: a rendszer saját beállítását soha
    // nem csökkentheti, amíg az maga belefér.
    test('a rendszer saját beállítását nem csökkenti', () {
      final x = TextScaleProvider.effectiveScale(
        const TextScaler.linear(2.0),
        TextScaleOption.normal.factor,
      );
      expect(x, 2.0);
    });
  });

  group('Mentés fájlneve', () {
    // Korábban MINDEN mentés „lari-backup.json" volt, ezért a Letöltések
    // mappában felülírta egymást vagy „(1)", „(2)" néven gyűlt — ezt is a
    // tesztelők jelezték.
    test('a név tartalmazza a dátumot és az időt', () {
      expect(
        BackupService.backupFileName(DateTime(2026, 3, 7, 9, 5)),
        'lari-backup-2026-03-07-0905.json',
      );
    });

    test('két különböző perc két különböző nevet ad', () {
      expect(
        BackupService.backupFileName(DateTime(2026, 3, 7, 9, 5)),
        isNot(BackupService.backupFileName(DateTime(2026, 3, 7, 9, 6))),
      );
    });
  });

  group('Hibanapló nyírása', () {
    late Directory tmp;
    late File logFile;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lari_trim_test');
      logFile = File('${tmp.path}/lari-errors.log');
      ErrorLog.setFileForTests(logFile);
    });

    tearDown(() {
      ErrorLog.setFileForTests(null);
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('nem-ASCII naplónál is nyír', () async {
      // Kínai szöveg: 3 bájt / karakter, viszont 1 UTF-16 kódegység. A vágás
      // bájtban mért küszöbhöz karakter-indexet használt, ezért negatív
      // indexre futott; a RangeError-t a catch elnyelte, és a napló
      // korlátlanul nőtt tovább.
      //
      // A veremkivonat SZÁNDÉKOSAN marad el: az csupa ASCII, és felhígítaná a
      // naplót annyira, hogy a régi számítás véletlenül pozitív maradjon —
      // vagyis a teszt akkor is zöld lenne, ha a hiba benne van.
      const message =
          '出错了錯誤測試記錄出错了錯誤測試記錄出错了錯誤測試記錄出错了錯誤測試記錄'
          '出错了錯誤測試記錄出错了錯誤測試記錄出错了錯誤測試記錄出错了錯誤測試記錄'
          '出错了錯誤測試記錄出错了錯誤測試記錄';
      for (var i = 0; i < 250; i++) {
        await ErrorLog.record('$message $i');
      }
      expect(await logFile.length(), lessThanOrEqualTo(64 * 1024));
      // A megmaradt tartalom érvényes UTF-8 (a readAsString nem dob).
      expect(await ErrorLog.read(), isNotNull);
    });
  });

  group('Időbélyeg kiírása', () {
    final when = DateTime(2026, 9, 19, 8, 30);

    test('magyarul nincs szóköz a dátumban', () {
      AppLocalizations.setLocale('hu');
      // Az ICU magyar mintája `y. MM. dd.` — pont UTÁN szóközzel. Az app
      // fix szélességű betűt használ, ezért ezek a szóközök ugyanolyan
      // szélesek, mint egy számjegy, és az időbélyeg hézagosnak látszott.
      expect(formatDate(when), '2026.09.19.');
      expect(formatDateTime(when), '2026.09.19. 08:30');
      // A dátumrészben nincs szóköz (a dátum és az idő közti szóköz jogos).
      expect(formatDate(when).contains(' '), isFalse);
    });

    test('a többi nyelv az ICU alapértelmezését kapja', () {
      AppLocalizations.setLocale('en');
      expect(formatDate(when), '9/19/2026');
      AppLocalizations.setLocale('es');
      expect(formatDate(when), '19/9/2026');
      AppLocalizations.setLocale('zh');
      expect(formatDate(when), '2026/9/19');
    });

    test('az óra minden nyelven kétjegyű', () {
      // Fix szélességű betűnél a `8:30` egy karakterrel rövidebb, mint a
      // `12:30` — az időbélyegek emiatt nem állnának egy vonalban.
      for (final lang in ['hu', 'en', 'es', 'zh']) {
        AppLocalizations.setLocale(lang);
        expect(formatTime(when), '08:30', reason: lang);
        expect(formatTime(DateTime(2026, 9, 19, 12, 5)), '12:05', reason: lang);
      }
      AppLocalizations.setLocale('hu');
    });
  });

  group('Fotó-hivatkozás feloldása', () {
    test('a régi, teljes útból is az aktuális mappa lesz', () {
      MediaStore.setDirectoryForTests('/data/uj-konteiner/docs');
      // Így néz ki egy korábbi verzió által elmentett érték.
      expect(
        MediaStore.resolve('/data/regi-konteiner/docs/photo_1.jpg'),
        '/data/uj-konteiner/docs/photo_1.jpg',
      );
      // És így az új, fájlnév-alapú.
      expect(
        MediaStore.resolve('photo_1.jpg'),
        '/data/uj-konteiner/docs/photo_1.jpg',
      );
    });

    test('mappa nélkül (teszt, web) változatlanul hagyja', () {
      MediaStore.setDirectoryForTests(null);
      expect(MediaStore.resolve('blob:valami'), 'blob:valami');
      expect(MediaStore.resolve(null), isNull);
    });
  });

  group('Főképernyő import után', () {
    testWidgets('nem ragad rá a már nem létező helyszínre', (tester) async {
      await tester.pumpWidget(_wrap(const HomeScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      // A kezdeti (beépített) helyszínek egyike ki van jelölve.
      expect(find.text('Otthon'), findsWidgets);

      // Import: mindent lecserélünk, csupa ÚJ azonosítóra — pont ez történik
      // egy másik telefonról hozott mentésnél.
      await DatabaseService.importData(
        '{"format":"lari_backup","version":1,'
        '"locations":[{"id":"uj-1","name":"Hajó","sort_order":0}],'
        '"items":[{"id":"i1","location_id":"uj-1","name":"Kikötőkötél",'
        '"is_checked":0,"sort_order":0,"is_default":0}]}',
      );

      // Pontosan ezt hívja a menü a sikeres import után (onDataChanged) —
      // UGYANAZON a State-példányon, ezért marad meg a régi kijelölés.
      final menu = tester.widget<AppMenuButton>(find.byType(AppMenuButton));
      menu.onDataChanged!();
      await tester.pump(const Duration(milliseconds: 100));

      // A kijelölés az új helyszínre került, és a tételei LÁTSZANAK.
      // A hibás verzióban a régi azonosító maradt: üres lista, aktív fül nélkül.
      expect(find.text('Hajó'), findsWidgets);
      // findsWidgets, nem findsOneWidget: a képernyőn kívüli megosztás-kártya
      // ugyanezt a listát még egyszer kirajzolja.
      expect(find.text('Kikötőkötél'), findsWidgets);
    });
  });
}
