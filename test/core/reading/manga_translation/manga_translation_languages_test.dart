import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/reading/manga_translation/manga_translation_languages.dart';

void main() {
  test('online catalog has unique Google text endpoint language codes', () {
    final codes = MangaTranslationLanguages.online
        .map((language) => language.code)
        .toList();

    expect(codes.length, greaterThan(100));
    expect(codes.toSet(), hasLength(codes.length));
    expect(codes, containsAll(['ja', 'ko', 'zh', 'en', 'hi']));
  });

  test('catalog records include script metadata for required languages', () {
    final byCode = {
      for (final language in MangaTranslationLanguages.online)
        language.code: language,
    };

    expect(byCode['ja']!.englishName, 'Japanese');
    expect(byCode['ja']!.script, 'Jpan');
    expect(byCode['ko']!.script, 'Kore');
    expect(byCode['zh']!.script, 'Hans');
    expect(byCode['en']!.script, 'Latn');
    expect(byCode['hi']!.script, 'Deva');
    expect(
      () => MangaTranslationLanguages.online.clear(),
      throwsUnsupportedError,
    );
  });

  test('canonicalCodeFor normalizes BCP-47 and native locale tags', () {
    expect(MangaTranslationLanguages.canonicalCodeFor('ja-JP'), 'ja');
    expect(MangaTranslationLanguages.canonicalCodeFor('ZH_hant_TW'), 'zh');
    expect(MangaTranslationLanguages.canonicalCodeFor('pt-BR'), 'pt');
    expect(MangaTranslationLanguages.canonicalCodeFor('en_US'), 'en');
    expect(MangaTranslationLanguages.canonicalCodeFor('unknown-ZZ'), isNull);
    expect(MangaTranslationLanguages.canonicalCodeFor('  '), isNull);
  });

  test('OCR intersection respects provided language and script coverage', () {
    final fromLocales = MangaTranslationLanguages.ocrIntersection([
      'ja-JP',
      'zh-Hant-TW',
    ]);
    expect(fromLocales.map((language) => language.code), ['zh', 'ja']);

    final fromScripts = MangaTranslationLanguages.ocrIntersection(['Jpan']);
    expect(fromScripts.map((language) => language.code), ['ja']);
    expect(
      MangaTranslationLanguages.ocrIntersection([
        'Hant',
      ]).map((language) => language.code),
      ['zh'],
    );
    expect(
      MangaTranslationLanguages.ocrIntersection([
        'Latn',
      ]).map((language) => language.code),
      containsAll(['en', 'es', 'fr']),
    );
    expect(
      MangaTranslationLanguages.ocrIntersection([
        'Latn',
      ]).map((language) => language.code),
      isNot(contains('hi')),
    );
  });

  test(
    'offline intersection canonicalizes and deduplicates available models',
    () {
      final offline = MangaTranslationLanguages.offlineIntersection([
        'zh-Hans-CN',
        'ja_JP',
        'zh_TW',
        'not-in-catalog',
      ]);

      expect(offline.map((language) => language.code), ['zh', 'ja']);
      expect(MangaTranslationLanguages.offlineIntersection(['Latn']), isEmpty);
    },
  );
}
