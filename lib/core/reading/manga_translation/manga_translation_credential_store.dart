import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'manga_page_translation_models.dart';

/// Narrow secure-storage boundary so provider keys can be tested without
/// invoking the platform keychain or Android keystore.
abstract interface class MangaTranslationSecureStorage {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class _FlutterMangaTranslationSecureStorage
    implements MangaTranslationSecureStorage {
  _FlutterMangaTranslationSecureStorage()
    : _storage = const FlutterSecureStorage(aOptions: AndroidOptions());

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// Stores user-owned AI provider credentials in the platform secure store.
class MangaTranslationCredentialStore {
  MangaTranslationCredentialStore({MangaTranslationSecureStorage? storage})
    : _storage = storage ?? _FlutterMangaTranslationSecureStorage();

  final MangaTranslationSecureStorage _storage;

  /// Reads an API key, or `null` for Google because it does not need a key.
  Future<String?> read(MangaOnlineTranslationProvider provider) {
    final key = _storageKey(provider);
    if (key == null) return Future.value(null);
    return _storage.read(key: key);
  }

  /// Whether [provider] has a non-empty key configured.
  Future<bool> isConfigured(MangaOnlineTranslationProvider provider) async =>
      (await read(provider))?.trim().isNotEmpty ?? false;

  /// Saves a non-empty API key for Gemini or Groq.
  Future<void> write(
    MangaOnlineTranslationProvider provider,
    String value,
  ) async {
    final key = _storageKey(provider);
    final normalized = value.trim();
    if (key == null || normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        'value',
        'A provider API key is required.',
      );
    }
    await _storage.write(key: key, value: normalized);
  }

  /// Removes the selected provider's saved key.
  Future<void> delete(MangaOnlineTranslationProvider provider) async {
    final key = _storageKey(provider);
    if (key == null) return;
    await _storage.delete(key: key);
  }

  String? _storageKey(MangaOnlineTranslationProvider provider) =>
      switch (provider) {
        MangaOnlineTranslationProvider.google => null,
        MangaOnlineTranslationProvider.gemini =>
          'manga_translation_gemini_api_key',
        MangaOnlineTranslationProvider.groq => 'manga_translation_groq_api_key',
      };
}
