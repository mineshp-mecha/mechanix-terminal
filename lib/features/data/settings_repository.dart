import 'dart:io';

import 'package:mechanix_terminal/core/utils/app_logger.dart';
import 'package:mechanix_terminal/core/utils/constants.dart';
import 'package:mechanix_terminal/features/data/settings.dart';
import 'package:mechanix_terminal/objectbox.g.dart';

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

      final storeDir = Directory('$home/${Constants.dbPath}');

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
    try { 
      final settings = settingsBox.getAll().firstOrNull;

      if (settings != null) {
        return settings;
      }

      final defaultSettings = AppSettings(fontSize: 14.0);

      final id = settingsBox.put(defaultSettings);
      defaultSettings.id = id;

      return defaultSettings;
    } catch (e, stackTrace) {
      AppLogger.e('Unable to load settings: $e');
      AppLogger.e(stackTrace.toString());
      rethrow;
    }
  }

  void saveSettings(AppSettings settings) {
    settingsBox.put(settings);
  }

  void close() {
    store.close();
  }
}
