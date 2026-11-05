import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'
    show kIsWeb, debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/checklist_item.dart';
import '../models/location.dart';
import 'media_store.dart';

class DatabaseService {
  static SharedPreferences? _prefs;
  static const _locationsKey = 'locations';
  static const _itemsKey = 'items';
  static bool _initialized = false;

  /// Az írások sorosítása. Minden művelet „olvasd be az egészet → módosítsd →
  /// írd vissza az egészet" mintát követ; ha kettő egyszerre fut, a második
  /// visszaírása eldobhatja az elsőét (pl. bepipálsz egy tételt, miközben az
  /// átrendezés mentése még tart). Ez a lánc garantálja, hogy egyszerre csak
  /// egy módosítás legyen folyamatban.
  static Future<void> _writeQueue = Future<void>.value();

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Csak tesztekhez: eldobja a bemelegített SharedPreferences-példányt, hogy
  /// a következő teszt friss (mockolt) tárolóval induljon.
  @visibleForTesting
  static void resetForTests() {
    _prefs = null;
    _initialized = false;
    _writeQueue = Future<void>.value();
  }

  static Future<void> _init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();

    // Initialize default data only if the key has never been set.
    // (An empty list is a valid state — the user deleted everything.)
    final locs = _prefs!.getStringList(_locationsKey);
    if (locs == null) {
      await _seedDefaults();
    }
    _initialized = true;
  }

  static Future<void> _seedDefaults() async {
    final homeId = 'default-home';
    final workId = 'default-work';

    final locations = [
      Location(
        id: homeId,
        name: 'Home',
        sortOrder: 0,
        translationKey: 'loc_home',
      ),
      Location(
        id: workId,
        name: 'Work',
        sortOrder: 1,
        translationKey: 'loc_work',
      ),
    ];

    // [name, translationKey] pairs — name is fallback, key is for l10n
    final defaultHomeItems = [
      ('Oven turned off', 'seed_oven_off'),
      ('Lights turned off', 'seed_lights_off'),
      ('Plugs unplugged', 'seed_plugs_out'),
      ('Iron unplugged', 'seed_iron_out'),
      ('Windows closed', 'seed_windows_closed'),
      ('Front door locked', 'seed_door_locked'),
      ('Taps turned off', 'seed_taps_off'),
      // A vitamin/gyógyszer SEM tétel, SEM beépített helyszín.
      //
      // A tesztelő külön helyszínt javasolt rá, én viszont tételként vettem
      // fel az Otthon listájába — így ment ki az 1.0.1-ben. Kivettük.
      // Beépített „Vitaminok" helyszín sem lesz: nem mindenkinek való, és
      // aki akar, két koppintással létrehozza magának.
    ];

    final defaultWorkItems = [
      ('Computer turned off', 'seed_pc_off'),
      ('Monitor turned off', 'seed_monitor_off'),
      ('Lights turned off', 'seed_work_lights_off'),
      ('Documents locked away', 'seed_docs_locked'),
    ];

    final items = <ChecklistItem>[];
    for (var i = 0; i < defaultHomeItems.length; i++) {
      items.add(
        ChecklistItem(
          id: 'home-$i',
          locationId: homeId,
          name: defaultHomeItems[i].$1,
          sortOrder: i,
          isDefault: true,
          translationKey: defaultHomeItems[i].$2,
        ),
      );
    }
    for (var i = 0; i < defaultWorkItems.length; i++) {
      items.add(
        ChecklistItem(
          id: 'work-$i',
          locationId: workId,
          name: defaultWorkItems[i].$1,
          sortOrder: i,
          isDefault: true,
          translationKey: defaultWorkItems[i].$2,
        ),
      );
    }

    await _saveLocations(locations);
    await _saveItems(items);
  }

  static Future<void> _saveLocations(List<Location> locations) async {
    final json = locations.map((l) => jsonEncode(l.toMap())).toList();
    await _prefs!.setStringList(_locationsKey, json);
  }

  static Future<void> _saveItems(List<ChecklistItem> items) async {
    final json = items.map((i) => jsonEncode(i.toMap())).toList();
    await _prefs!.setStringList(_itemsKey, json);
  }

  // --- Locations ---

  static Future<List<Location>> getLocations() async {
    await _init();
    final jsonList = _prefs!.getStringList(_locationsKey) ?? [];
    var locations = jsonList
        .map((j) => Location.fromMap(jsonDecode(j) as Map<String, dynamic>))
        .toList();

    // Migration: attach translationKey to legacy hardcoded location names so
    // the built-in Home/Work locations translate with the app language.
    var changed = false;
    for (var i = 0; i < locations.length; i++) {
      final loc = locations[i];
      if (loc.translationKey == null) {
        if (loc.name == 'Otthon' || loc.name == 'Home') {
          locations[i] = loc.copyWith(translationKey: 'loc_home');
          changed = true;
        } else if (loc.name == 'Munka' || loc.name == 'Work') {
          locations[i] = loc.copyWith(translationKey: 'loc_work');
          changed = true;
        }
      }
    }
    if (changed) await _saveLocations(locations);

    locations.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return locations;
  }

  static Future<void> addLocation(Location location) async {
    return _serialized(() async {
      final locations = await getLocations();
      locations.add(location);
      await _saveLocations(locations);
    });
  }

  static Future<void> updateLocation(Location location) async {
    return _serialized(() async {
      final locations = await getLocations();
      final idx = locations.indexWhere((l) => l.id == location.id);
      if (idx != -1) locations[idx] = location;
      await _saveLocations(locations);
    });
  }

  static Future<void> deleteLocation(String id) async {
    return _serialized(() async {
      var locations = await getLocations();
      locations = locations.where((l) => l.id != id).toList();
      await _saveLocations(locations);

      var items = await _getAllItems();
      items = items.where((i) => i.locationId != id).toList();
      await _saveItems(items);
    });
  }

  // --- Items ---

  static Future<List<ChecklistItem>> _getAllItems() async {
    final jsonList = _prefs!.getStringList(_itemsKey) ?? [];
    return jsonList
        .map(
          (j) => ChecklistItem.fromMap(jsonDecode(j) as Map<String, dynamic>),
        )
        .toList();
  }

  static Future<List<ChecklistItem>> getItems(String locationId) async {
    await _init();
    final all = await _getAllItems();
    final filtered = all.where((i) => i.locationId == locationId).toList();
    filtered.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return filtered;
  }

  static Future<void> addItem(ChecklistItem item) async {
    return _serialized(() async {
      final items = await _getAllItems();
      items.add(item);
      await _saveItems(items);
    });
  }

  static Future<void> updateItem(ChecklistItem item) async {
    return _serialized(() async {
      final items = await _getAllItems();
      final idx = items.indexWhere((i) => i.id == item.id);
      if (idx != -1) items[idx] = item;
      await _saveItems(items);
    });
  }

  /// A helyszínek sorrendjének mentése EGY írással. Az átrendezés korábban
  /// elemenként hívta az updateLocation-t, ami N-szer írta újra a teljes
  /// listát — most egyszer.
  static Future<void> saveLocationOrder(List<Location> ordered) async {
    return _serialized(() async {
      await _init();
      await _saveLocations(ordered);
    });
  }

  /// Egy helyszín tételeinek sorrendje EGY írással. A kapott lista csak az
  /// adott helyszín tételeit tartalmazza, ezért a teljes listába vezetjük át.
  static Future<void> saveItemOrder(List<ChecklistItem> ordered) async {
    return _serialized(() async {
      await _init();
      final all = await _getAllItems();
      final byId = {for (final i in ordered) i.id: i};
      await _saveItems([for (final i in all) byId[i.id] ?? i]);
    });
  }

  /// Helyszín duplikálása a tételeivel együtt, egyetlen írásban.
  ///
  /// A másolat FRISS: a pipák, az időbélyegek és a fotó-hivatkozások nem
  /// jönnek át — azok egy konkrét indulásához tartoznak, nem a listához.
  /// A fotófájlokat sem másoljuk, csak a hivatkozást hagyjuk el.
  static Future<Location> duplicateLocation(
    Location source,
    String newName,
    String Function() newId,
  ) async {
    return _serialized(() async {
      await _init();
      final locations = await getLocations();
      final copy = Location(
        id: newId(),
        name: newName,
        sortOrder: locations.length,
        // A másolat SOSEM örökli a fordítási kulcsot: az a beépített
        // Otthon/Munka helyszíneké, a másolat viszont egyedi nevet kap.
        // A videót sem örökli — a másolat friss lista, ahogy a pipák és a
        // fotók sem jönnek át.
      );
      locations.add(copy);
      await _saveLocations(locations);

      final all = await _getAllItems();
      final sourceItems = all.where((i) => i.locationId == source.id).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      for (var i = 0; i < sourceItems.length; i++) {
        final src = sourceItems[i];
        all.add(
          ChecklistItem(
            id: newId(),
            locationId: copy.id,
            name: src.name,
            sortOrder: i,
            isDefault: false,
            translationKey: src.translationKey,
          ),
        );
      }
      await _saveItems(all);
      return copy;
    });
  }

  static Future<void> deleteItem(String id) async {
    return _serialized(() async {
      var items = await _getAllItems();
      items = items.where((i) => i.id != id).toList();
      await _saveItems(items);
    });
  }

  static Future<void> resetAllItems(String locationId) async {
    return _serialized(() async {
      var items = await _getAllItems();
      for (var i = 0; i < items.length; i++) {
        if (items[i].locationId == locationId) {
          items[i] = items[i].copyWith(
            isChecked: false,
            checkedAt: null,
            photoPath: null,
          );
        }
      }
      await _saveItems(items);
    });
  }

  // --- UI-állapot ---

  static const _addTabIndexKey = 'add_tab_index';
  static const _swipeHintKey = 'swipe_hint_seen';

  /// A "+" fül helye a fülsorban. Ez a felhasználó döntése (hosszú nyomás +
  /// húzás), ezért túl kell élnie az újraindítást — korábban minden
  /// újratöltéskor visszaugrott a sor végére.
  static Future<int?> getAddTabIndex() async {
    await _init();
    return _prefs!.getInt(_addTabIndexKey);
  }

  static Future<void> saveAddTabIndex(int index) async {
    await _init();
    await _prefs!.setInt(_addTabIndexKey, index);
  }

  /// Látta-e már a felhasználó a „balra húzással törölhetsz" mozdulatot.
  /// Egyszer mutatjuk meg, az első indításnál.
  static Future<bool> getSwipeHintSeen() async {
    await _init();
    return _prefs!.getBool(_swipeHintKey) ?? false;
  }

  static Future<void> markSwipeHintSeen() async {
    await _init();
    await _prefs!.setBool(_swipeHintKey, true);
  }

  // --- Export / Import (listák + elemek, fotók nélkül) ---

  static const _exportVersion = 1;

  /// Teljes állapotot visszaadó JSON (listák + elemek). A fotókat nem viszi —
  /// a photoPath kimarad, mert az abszolút elérési út nem érvényes átvitelkor.
  /// Ez a fájl küldhető (e-mail, Drive, pendrive) és másik telefonra
  /// visszatölthető az [importData]-val.
  static Future<String> exportData() async {
    await _init();
    final locations = await getLocations();
    final items = await _getAllItems();
    final payload = {
      'format': 'lari_backup',
      'version': _exportVersion,
      'exported_at': DateTime.now().toIso8601String(),
      // A `video_path` ugyanazért marad ki, amiért a tételek `photo_path`-ja:
      // a felvétel a készüléken van, a mentésfájl pedig csak a listákat viszi.
      'locations': locations
          .map((l) => l.toMap()..remove('video_path'))
          .toList(),
      // A sorrend (sort_order) megőrződik, de a KIPIPÁLT (áthúzott) állapot
      // NEM kerül a mentésbe: az import után minden elem friss, kipipálatlan
      // — a "kipipált" csak az adott napra vonatkozik, abban nincs logika
      // átvinni. A photo_path is kimarad (abszolút út nem érvényes átvitelkor).
      'items': items
          .map(
            (i) => i.toMap()
              ..remove('photo_path')
              ..['is_checked'] = 0
              ..['checked_at'] = null,
          )
          .toList(),
    };
    return jsonEncode(payload);
  }

  /// Betölti a [json] import fájlt és felülírja a jelenlegi adatokat.
  /// A fotók NEM jönnek vissza (photoPath üres marad minden elemen).
  /// Validálja a formátumot, és false értékkel tér vissza, ha nem ismer fel.
  static Future<bool> importData(String json) async {
    await _init();
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      if (decoded['format'] != 'lari_backup') return false;
      // Újabb formátumot nem tudunk értelmezni — jobb nemet mondani, mint
      // félig beolvasni.
      final version = decoded['version'] as int? ?? 1;
      if (version > _exportVersion) return false;

      final locList = decoded['locations'] as List? ?? [];
      final itemList = decoded['items'] as List? ?? [];

      final locations = locList
          .map((e) => Location.fromMap(e as Map<String, dynamic>))
          .toList();
      final locIds = locations.map((l) => l.id).toSet();
      final items = itemList
          .map(
            (e) => (ChecklistItem.fromMap(
              e as Map<String, dynamic>,
            )).copyWith(photoPath: null),
          )
          // Árva elem (nincs hozzá helyszín) sosem jelenne meg, csak foglalná
          // a helyet — ki sem mentjük.
          .where((i) => locIds.contains(i.locationId))
          .toList();

      // A meglévő fotófájlokat el kell takarítani: az import minden elem
      // photoPath-ját nullázza, így a fájlokra semmi nem hivatkozna többé.
      await _deleteAllPhotoFiles();

      await _saveLocations(locations);
      await _saveItems(items);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Törli a jelenlegi elemekhez tartozó fotófájlokat a készülékről.
  static Future<void> _deleteAllPhotoFiles() async {
    if (kIsWeb) return;
    final items = await _getAllItems();
    for (final item in items) {
      final path = MediaStore.resolve(item.photoPath);
      if (path == null) continue;
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('photo delete failed: $e');
      }
    }
  }
}
