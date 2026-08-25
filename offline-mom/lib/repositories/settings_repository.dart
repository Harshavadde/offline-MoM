import 'package:hive_flutter/hive_flutter.dart';

import '../models/app_settings.dart';

abstract class SettingsRepository {
  AppSettings getSettings();
  Future<void> save(AppSettings settings);
}

class HiveSettingsRepository implements SettingsRepository {
  HiveSettingsRepository(this._box);

  final Box _box;
  static const _settingsKey = 'app_settings';

  @override
  AppSettings getSettings() {
    final raw = _box.get(_settingsKey);
    if (raw == null) return const AppSettings();
    return AppSettings.fromMap(Map<Object?, Object?>.from(raw as Map));
  }

  @override
  Future<void> save(AppSettings settings) {
    return _box.put(_settingsKey, settings.toMap());
  }
}
