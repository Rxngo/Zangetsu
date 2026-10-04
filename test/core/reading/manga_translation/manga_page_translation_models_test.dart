import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/reading/manga_translation/manga_page_translation_models.dart';

void main() {
  group('MangaPageTranslationKey', () {
    test('cache identity includes every request field', () {
      const key = MangaPageTranslationKey(
        pageUrl: 'https://example.test/page.jpg',
        sourceLanguage: 'ja',
        targetLanguage: 'en',
        engine: MangaTranslationEngine.online,
      );
      const sameKey = MangaPageTranslationKey(
        pageUrl: 'https://example.test/page.jpg',
        sourceLanguage: 'ja',
        targetLanguage: 'en',
        engine: MangaTranslationEngine.online,
      );

      expect(key, sameKey);
      expect(key.hashCode, sameKey.hashCode);
      expect(
        {
          key,
          const MangaPageTranslationKey(
            pageUrl: 'https://example.test/other.jpg',
            sourceLanguage: 'ja',
            targetLanguage: 'en',
            engine: MangaTranslationEngine.online,
          ),
          const MangaPageTranslationKey(
            pageUrl: 'https://example.test/page.jpg',
            sourceLanguage: 'ko',
            targetLanguage: 'en',
            engine: MangaTranslationEngine.online,
          ),
          const MangaPageTranslationKey(
            pageUrl: 'https://example.test/page.jpg',
            sourceLanguage: 'ja',
            targetLanguage: 'fr',
            engine: MangaTranslationEngine.online,
          ),
          const MangaPageTranslationKey(
            pageUrl: 'https://example.test/page.jpg',
            sourceLanguage: 'ja',
            targetLanguage: 'en',
            engine: MangaTranslationEngine.offline,
          ),
          const MangaPageTranslationKey(
            pageUrl: 'https://example.test/page.jpg',
            sourceLanguage: 'ja',
            targetLanguage: 'en',
            engine: MangaTranslationEngine.online,
            onlineProvider: MangaOnlineTranslationProvider.gemini,
          ),
        }.length,
        6,
      );
    });
  });

  group('normalized region bounds', () {
    test('accepts finite bounds within the normalized page', () {
      expect(
        MangaOcrRegion(
          text: 'hello',
          normalizedBounds: const Rect.fromLTRB(0, 0.1, 0.8, 1),
        ).normalizedBounds,
        const Rect.fromLTRB(0, 0.1, 0.8, 1),
      );
    });

    test('rejects non-finite, out-of-range, and inverted bounds', () {
      final invalidBounds = [
        const Rect.fromLTRB(double.nan, 0, 1, 1),
        const Rect.fromLTRB(0, double.infinity, 1, 1),
        const Rect.fromLTRB(-0.01, 0, 1, 1),
        const Rect.fromLTRB(0, 0, 1.01, 1),
        const Rect.fromLTRB(0.8, 0, 0.2, 1),
      ];

      for (final bounds in invalidBounds) {
        expect(
          () => MangaOcrRegion(text: 'bad', normalizedBounds: bounds),
          throwsArgumentError,
        );
        expect(
          () => MangaTranslatedRegion(
            originalText: 'bad',
            translatedText: 'incorrecto',
            normalizedBounds: bounds,
          ),
          throwsArgumentError,
        );
      }
    });
  });

  test('page results defensively copy and expose immutable regions', () {
    final input = <MangaTranslatedRegion>[
      MangaTranslatedRegion(
        originalText: 'こんにちは',
        translatedText: 'hello',
        normalizedBounds: const Rect.fromLTRB(0.1, 0.2, 0.7, 0.3),
      ),
    ];
    final result = MangaPageTranslationResult(
      imageWidth: 100,
      imageHeight: 200,
      regions: input,
    );

    input.clear();

    expect(result.imageWidth, 100);
    expect(result.imageHeight, 200);
    expect(result.regions, hasLength(1));
    expect(() => result.regions.clear(), throwsUnsupportedError);
  });

  test('translation page results reject non-positive image dimensions', () {
    final invalidResults = <Object Function()>[
      () => MangaPageTranslationResult(
        imageWidth: 0,
        imageHeight: 200,
        regions: const <MangaTranslatedRegion>[],
      ),
      () => MangaPageTranslationResult(
        imageWidth: -1,
        imageHeight: 200,
        regions: const <MangaTranslatedRegion>[],
      ),
      () => MangaPageTranslationResult(
        imageWidth: 100,
        imageHeight: 0,
        regions: const <MangaTranslatedRegion>[],
      ),
      () => MangaPageTranslationResult(
        imageWidth: 100,
        imageHeight: -1,
        regions: const <MangaTranslatedRegion>[],
      ),
    ];

    for (final createResult in invalidResults) {
      expect(createResult, throwsArgumentError);
    }
  });

  test('OCR page results defensively copy and expose immutable regions', () {
    final input = <MangaOcrRegion>[
      MangaOcrRegion(
        text: 'こんにちは',
        normalizedBounds: const Rect.fromLTRB(0.1, 0.2, 0.7, 0.3),
      ),
    ];
    final result = MangaPageOcrResult(
      imageWidth: 100,
      imageHeight: 200,
      regions: input,
    );

    input.clear();

    expect(result.imageWidth, 100);
    expect(result.imageHeight, 200);
    expect(result.regions, hasLength(1));
    expect(() => result.regions.clear(), throwsUnsupportedError);
  });

  test('OCR page results reject non-positive image dimensions', () {
    final invalidResults = <Object Function()>[
      () => MangaPageOcrResult(
        imageWidth: 0,
        imageHeight: 200,
        regions: const <MangaOcrRegion>[],
      ),
      () => MangaPageOcrResult(
        imageWidth: -1,
        imageHeight: 200,
        regions: const <MangaOcrRegion>[],
      ),
      () => MangaPageOcrResult(
        imageWidth: 100,
        imageHeight: 0,
        regions: const <MangaOcrRegion>[],
      ),
      () => MangaPageOcrResult(
        imageWidth: 100,
        imageHeight: -1,
        regions: const <MangaOcrRegion>[],
      ),
    ];

    for (final createResult in invalidResults) {
      expect(createResult, throwsArgumentError);
    }
  });

  group('MangaTranslationModelStatus', () {
    test('online readiness ignores source and target translation models', () {
      const status = MangaTranslationModelStatus(
        ocrReady: true,
        sourceTranslationReady: false,
        targetTranslationReady: false,
      );

      expect(status.isReadyFor(MangaTranslationEngine.online), isTrue);
      expect(status.requiresConsentFor(MangaTranslationEngine.online), isFalse);
    });

    test('OCR setup requires consent for either engine', () {
      const status = MangaTranslationModelStatus(
        ocrReady: false,
        sourceTranslationReady: true,
        targetTranslationReady: true,
      );

      expect(status.isReadyFor(MangaTranslationEngine.online), isFalse);
      expect(status.requiresConsentFor(MangaTranslationEngine.online), isTrue);
      expect(status.isReadyFor(MangaTranslationEngine.offline), isFalse);
      expect(status.requiresConsentFor(MangaTranslationEngine.offline), isTrue);
    });

    test('offline readiness requires both translation models', () {
      for (final status in [
        const MangaTranslationModelStatus(
          ocrReady: true,
          sourceTranslationReady: false,
          targetTranslationReady: true,
        ),
        const MangaTranslationModelStatus(
          ocrReady: true,
          sourceTranslationReady: true,
          targetTranslationReady: false,
        ),
      ]) {
        expect(status.isReadyFor(MangaTranslationEngine.offline), isFalse);
        expect(
          status.requiresConsentFor(MangaTranslationEngine.offline),
          isTrue,
        );
      }

      const ready = MangaTranslationModelStatus(
        ocrReady: true,
        sourceTranslationReady: true,
        targetTranslationReady: true,
      );
      expect(ready.isReadyFor(MangaTranslationEngine.offline), isTrue);
      expect(ready.requiresConsentFor(MangaTranslationEngine.offline), isFalse);
    });
  });
}
