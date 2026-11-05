import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Helyi hibanapló.
///
/// SZÁNDÉKOSAN nem küld semmit sehova. Az app adatvédelmi nyilatkozata azt
/// állítja, hogy nincs analitika, és semmilyen adat nem megy szerverre —
/// egy Crashlytics/Sentry ezt valótlanná tenné, és a Play adatbiztonsági
/// nyilatkozatot is módosítani kellene miatta.
///
/// Helyette: a kezeletlen hibákat a készüléken, az app privát mappájában
/// gyűjtjük. A felhasználó a menüből megnézheti, megoszthatja (ha segíteni
/// akar egy hiba felderítésében) vagy törölheti. Semmi nem hagyja el a
/// telefont, amíg ő maga el nem küldi.
class ErrorLog {
  ErrorLog._();

  static const _fileName = 'lari-errors.log';

  /// A napló felső mérete. Fölötte a régi bejegyzéseket eldobjuk, hogy egy
  /// ismétlődő hiba ne tudja tele írni a tárhelyet.
  static const _maxBytes = 64 * 1024;

  static File? _file;
  static bool _installed = false;

  /// Bekötése a Flutter hibakezelésébe. A `main()` hívja, a `runApp` előtt.
  static Future<void> install() async {
    if (_installed || kIsWeb) return;
    _installed = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/$_fileName');
    } catch (e) {
      debugPrint('error log init failed: $e');
      return;
    }

    // A widget-fában keletkező hibák.
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      unawaited(record(details.exceptionAsString(), details.stack));
    };

    // A widget-fán kívüli, elkapatlan aszinkron hibák.
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(record(error.toString(), stack));
      return true;
    };
  }

  /// Egy bejegyzés hozzáfűzése. Hiba esetén csendben elhallgat — a naplózás
  /// sosem okozhat újabb hibát.
  static Future<void> record(String message, [StackTrace? stack]) async {
    final file = _file;
    if (file == null) return;
    try {
      final entry = StringBuffer()
        ..writeln('--- ${DateTime.now().toIso8601String()} ---')
        ..writeln(message);
      if (stack != null) {
        // Csak az első néhány keret, hogy a napló olvasható maradjon.
        final frames = stack.toString().split('\n').take(12);
        entry.writeAll(frames, '\n');
        entry.writeln();
      }
      await file.writeAsString(entry.toString(), mode: FileMode.append);
      await _trim(file);
    } catch (e) {
      debugPrint('error log write failed: $e');
    }
  }

  /// A napló tartalma, vagy null, ha üres/nem elérhető.
  static Future<String?> read() async {
    final file = _file;
    if (file == null) return null;
    try {
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      return text.trim().isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final file = _file;
      if (file != null && await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('error log clear failed: $e');
    }
  }

  /// A megosztáshoz használható fájl (ha van mit megosztani).
  static Future<File?> fileIfNotEmpty() async {
    final file = _file;
    if (file == null) return null;
    try {
      if (!await file.exists()) return null;
      if (await file.length() == 0) return null;
      return file;
    } catch (_) {
      return null;
    }
  }

  /// A napló elejét dobjuk el, ha túl nagyra nőtt.
  ///
  /// BÁJTOKBAN vágunk, nem karakterekben. A `length()` bájtot ad vissza, a
  /// `String.length` viszont UTF-16 kódegységet — nem-ASCII naplónál (ékezetes
  /// magyar vagy kínai szöveg) a kettő eltér, és a karakter-alapú vágás
  /// negatív indexre futott. A RangeError-t a catch elnyelte, így a nyírás
  /// CSENDBEN sosem történt meg, a napló pedig korlátlanul nőtt.
  static Future<void> _trim(File file) async {
    try {
      if (await file.length() <= _maxBytes) return;
      final bytes = await file.readAsBytes();
      final keep = bytes.sublist(bytes.length - _maxBytes ~/ 2);
      // A vágás egy többbájtos UTF-8 karakter közepére eshet: a folytató
      // bájtokat (10xxxxxx) eldobjuk, hogy a fájl érvényes UTF-8 maradjon.
      var start = 0;
      while (start < keep.length && (keep[start] & 0xC0) == 0x80) {
        start++;
      }
      // Ha van még sortörés, onnan kezdjük — ne fél bejegyzéssel induljon.
      final newline = keep.indexOf(0x0A, start);
      if (newline != -1) start = newline + 1;
      await file.writeAsBytes(keep.sublist(start));
    } catch (e) {
      debugPrint('error log trim failed: $e');
    }
  }

  @visibleForTesting
  static void setFileForTests(File? file) {
    _file = file;
    _installed = true;
  }
}
