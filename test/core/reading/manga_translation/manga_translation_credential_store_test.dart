import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/reading/manga_translation/manga_page_translation_models.dart';
import 'package:watch_app/core/reading/manga_translation/manga_translation_credential_store.dart';

void main() {
  group('MangaTranslationCredentialStore', () {
    test('stores provider keys independently and trims input', () async {
      final storage = _FakeSecureStorage();
      final credentials = MangaTranslationCredentialStore(storage: storage);

      await credentials.write(
        MangaOnlineTranslationProvider.gemini,
        '  gemini-secret  ',
      );
      await credentials.write(
        MangaOnlineTranslationProvider.groq,
        'groq-secret',
      );

      expect(
        await credentials.read(MangaOnlineTranslationProvider.gemini),
        'gemini-secret',
      );
      expect(
        await credentials.read(MangaOnlineTranslationProvider.groq),
        'groq-secret',
      );
      expect(
        await credentials.read(MangaOnlineTranslationProvider.google),
        isNull,
      );
    });

    test('deletes one provider key without affecting another', () async {
      final storage = _FakeSecureStorage();
      final credentials = MangaTranslationCredentialStore(storage: storage);
      await credentials.write(MangaOnlineTranslationProvider.gemini, 'g-key');
      await credentials.write(MangaOnlineTranslationProvider.groq, 'r-key');

      await credentials.delete(MangaOnlineTranslationProvider.gemini);

      expect(
        await credentials.read(MangaOnlineTranslationProvider.gemini),
        isNull,
      );
      expect(
        await credentials.read(MangaOnlineTranslationProvider.groq),
        'r-key',
      );
    });

    test('rejects empty or unsupported provider keys', () async {
      final credentials = MangaTranslationCredentialStore(
        storage: _FakeSecureStorage(),
      );

      await expectLater(
        credentials.write(MangaOnlineTranslationProvider.gemini, '  '),
        throwsArgumentError,
      );
      await expectLater(
        credentials.write(MangaOnlineTranslationProvider.google, 'key'),
        throwsArgumentError,
      );
    });
  });
}

class _FakeSecureStorage implements MangaTranslationSecureStorage {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}
