import 'theme_preference_store_stub.dart'
    if (dart.library.io) 'theme_preference_store_io.dart'
    as implementation;

abstract interface class ThemePreferenceStore {
  Future<bool?> readDarkMode();

  Future<void> writeDarkMode(bool enabled);
}

ThemePreferenceStore createThemePreferenceStore() =>
    implementation.createThemePreferenceStore();

class MemoryThemePreferenceStore implements ThemePreferenceStore {
  MemoryThemePreferenceStore([this.value]);

  bool? value;

  @override
  Future<bool?> readDarkMode() async => value;

  @override
  Future<void> writeDarkMode(bool enabled) async {
    value = enabled;
  }
}
