import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'theme_preference_store.dart';

ThemePreferenceStore createThemePreferenceStore() => FileThemePreferenceStore();

class FileThemePreferenceStore implements ThemePreferenceStore {
  Future<File> _file() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'Qodynex', 'Nizami'));
    await directory.create(recursive: true);
    return File(p.join(directory.path, 'appearance.theme'));
  }

  @override
  Future<bool?> readDarkMode() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final value = (await file.readAsString()).trim();
    return switch (value) {
      'dark' => true,
      'light' => false,
      _ => null,
    };
  }

  @override
  Future<void> writeDarkMode(bool enabled) async {
    final file = await _file();
    await file.writeAsString(enabled ? 'dark' : 'light', flush: true);
  }
}
