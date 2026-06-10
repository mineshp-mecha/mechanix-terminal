// import 'dart:io';

// import 'package:flutter_alacritty/features/data/settings.dart';
// import 'package:flutter_alacritty/objectbox.g.dart';

// class SettingsRepository {
//   late final Store store;
//   late final Box<AppSettings> settingsBox;

//   SettingsRepository._create(this.store) {
//     settingsBox = Box<AppSettings>(store);
//   }

//   static Future<SettingsRepository> create() async {
//     final home = Platform.environment['HOME'];
//     final storeDir = Directory('$home/.config/flutter_alacritty/objectbox');
//     final exists = await storeDir.exists();

//     if (!exists) {
//       await storeDir.create(recursive: true);
//     }
//     final store = openStore(directory: storeDir.path);

//     return SettingsRepository._create(store);
//   }

//   AppSettings getSettings() {
//     var settings = settingsBox.get(1);

//     if (settings == null) {
//       settings = AppSettings(id: 0, fontSize: 14.0);

//       final id = settingsBox.put(settings);
//       settings.id = id;
//     }
//     return settings;
//   }

//   void saveSettings(AppSettings settings) {
//     settingsBox.put(settings);
//   }
// }

import 'dart:io';

import 'package:flutter_alacritty/core/utils/app_logger.dart';
import 'package:flutter_alacritty/features/data/settings.dart';
import 'package:flutter_alacritty/objectbox.g.dart';

class SettingsRepository {
  final Store store;
  late final Box<AppSettings> settingsBox;

  SettingsRepository._(this.store) {
    settingsBox = store.box<AppSettings>();
  }

  static Future<SettingsRepository> create() async {
    try {
      final home = Platform.environment['HOME'];

      if (home == null || home.isEmpty) {
        throw Exception('HOME environment variable is not set');
      }

      final storeDir = Directory('$home/.config/flutter_alacritty/objectbox');

      if (!await storeDir.exists()) {
        await storeDir.create(recursive: true);
      }

      final store = openStore(directory: storeDir.path);

      return SettingsRepository._(store);
    } catch (e, stackTrace) {
      AppLogger.e('Unable to initialize settings storage: $e');
      AppLogger.e(stackTrace.toString());
      rethrow;
    }
  }

  AppSettings getSettings() {
    final settings = settingsBox.getAll().firstOrNull;

    if (settings != null) {
      return settings;
    }

    final defaultSettings = AppSettings(fontSize: 14.0);

    print('defaultSettings: $defaultSettings');

    final id = settingsBox.put(defaultSettings);
    defaultSettings.id = id;

    return defaultSettings;
  }

  void saveSettings(AppSettings settings) {
    settingsBox.put(settings);
  }

  void close() {
    store.close();
  }
}
