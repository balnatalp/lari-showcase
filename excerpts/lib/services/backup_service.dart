import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_localizations.dart';
import 'database_service.dart';

/// Listák + elemek mentése egy önálló JSON-fájlba és visszatöltése.
///
/// Export: a készüléken ideiglenes `.lari.json`-t írunk, majd a rendszer
/// megosztó ablakával adjuk át (e-mail, Drive, pendrive…). A fájl nem
/// hagyja el a telefont másként, mint ahogy te elküldöd.
/// Import: fájlt választunk, beolvassuk, és felülírjuk az adatokat.
class BackupService {
  static const _filePrefix = 'lari-backup';

  /// A mentés fájlneve a KÉSZÍTÉS IDEJÉT viseli:
  /// `lari-backup-2026-10-31-1408.json`.
  ///
  /// Korábban minden mentés `lari-backup.json` volt, ezért a Letöltések
  /// mappában az újabb felülírta a régebbit, vagy „(1)", „(2)" néven gyűlt —
  /// a tesztelők ezt jelezték. A helyszín nevét szándékosan NEM használjuk:
  /// a mentés MINDEN helyszínt tartalmaz, egyetlen helyszín neve félrevezető
  /// volna.
  static String backupFileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '$_filePrefix-${now.year}-${two(now.month)}-${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}.json';
  }

  /// Létrehozza a mentést és megnyitja a megosztó ablakot.
  static Future<bool> exportToShare() async {
    try {
      final json = await DatabaseService.exportData();
      final dir = await getTemporaryDirectory();
      final filename = backupFileName(DateTime.now());
      final file = File('${dir.path}/$filename');
      // Az ELŐZŐ mentések maradékát töröljük, nem a mostanit a megosztás
      // után: a fogadó alkalmazás (Drive, e-mail) ilyenkor még olvashatja a
      // fájlt. Mióta a név dátumos, ez már nem egyetlen fájl felülírása —
      // végig kell söpörni a korábbiakon, különben a temp mappában gyűlnek.
      try {
        for (final entry in dir.listSync()) {
          final name = entry.path.split(Platform.pathSeparator).last;
          if (entry is File &&
              name.startsWith(_filePrefix) &&
              name.endsWith('.json')) {
            try {
              entry.deleteSync();
            } catch (_) {}
          }
        }
      } catch (_) {}
      await file.writeAsString(json);

      final result = await SharePlus.instance.share(
        ShareParams(
          // A `name`-et EXPLICITEN adjuk meg, hogy a fogadó alkalmazás
          // (pl. Letöltések, Drive) a `.json` kiterjesztéssel mentse a fájlt,
          // ne "ismeretlen típusként".
          files: [
            XFile(file.path, mimeType: 'application/json', name: filename),
          ],
          subject: 'Lari backup',
          text: AppLocalizations.get('exportShareText'),
        ),
      );

      // Csak akkor jelezzük sikernek, ha a felhasználó TÉNYLEGESEN
      // megosztotta (success). Ha bezárta a megosztó ablakot (dismissed)
      // vagy nem érhető el (unavailable), az NEM siker — ne írjuk ki,
      // hogy "mentve".
      return result.status == ShareResultStatus.success;
    } catch (_) {
      return false;
    }
  }

  /// Fájlválasztóval behozza a JSON-t és felülírja az adatokat.
  /// A [onImported] a sikeres betöltés után hívódik (a UI frissítéshez).
  /// Visszaadja: null = nem sikerült, false = rossz formátum, true = kész.
  static Future<bool?> importFromPicker() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (files.isEmpty) return null; // megszakítva a fájlválasztóban
      final path = files.single.path;
      if (path == null) return null;

      final json = await File(path).readAsString();
      return await DatabaseService.importData(json);
    } catch (_) {
      return null;
    }
  }
}
