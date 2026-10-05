import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/reading/manga_translation/manga_online_translation_service.dart';
import 'package:watch_app/core/reading/manga_translation/manga_page_translation_models.dart';
import 'package:watch_app/core/reading/manga_translation/manga_page_translation_service.dart';
import 'package:watch_app/core/reading/manga_translation/manga_translation_credential_store.dart';
import 'package:watch_app/core/reading/manga_translation/manga_translation_platform.dart';

void main() {
  group('MangaPageTranslationService', () {
    test('sends OCR text only to the online text translator', () async {
      final platform = _FakeMangaTranslationPlatform();
      platform.ocrResult = _ocrResult();
      final onlineTexts = <String>[];
      final service = MangaPageTranslationService(
        platform: platform,
        onlineTranslator:
            (text, {required sourceLanguage, required targetLanguage}) async {
              onlineTexts.add(text);
              expect(sourceLanguage, 'ja');
              expect(targetLanguage, 'en');
              return 'translated $text';
            },
      );

      expect(platform.recognizeCalls, isEmpty);
      final result = await service.translatePage(
        pageUrl: 'https://example.test/page-1.jpg',
        filePath: '/local/page-1.jpg',
        sourceLanguage: 'ja',
        targetLanguage: 'en',
        engine: MangaTranslationEngine.online,
      );

      expect(platform.recognizeCalls, [
        (filePath: '/local/page-1.jpg', sourceLanguage: 'ja'),
      ]);
      expect(onlineTexts, ['日本語', '次の文']);
      expect(platform.offlineTexts, isEmpty);
      expect(result!.regions.map((region) => region.translatedText), [
        'translated 日本語',
        'translated 次の文',
      ]);
      _expectGeometryPreserved(result);
    });

    test(
      'routes OCR text to native translation for the offline engine',
      () async {
        final platform = _FakeMangaTranslationPlatform();
        platform.ocrResult = _ocrResult();
        final onlineTexts = <String>[];
        final service = MangaPageTranslationService(
          platform: platform,
          onlineTranslator:
              (text, {required sourceLanguage, required targetLanguage}) async {
                onlineTexts.add(text);
                return 'unexpected';
              },
        );

        final result = await service.translatePage(
          pageUrl: 'https://example.test/page-1.jpg',
          filePath: '/local/page-1.jpg',
          sourceLanguage: 'ja',
          targetLanguage: 'en',
          engine: MangaTranslationEngine.offline,
        );

        expect(platform.offlineTexts, hasLength(1));
        expect(platform.offlineTexts.single.texts, ['日本語', '次の文']);
        expect(platform.offlineTexts.single.sourceLanguage, 'ja');
        expect(platform.offlineTexts.single.targetLanguage, 'en');
        expect(onlineTexts, isEmpty);
        expect(result!.regions.map((region) => region.translatedText), [
          'offline 日本語',
          'offline 次の文',
        ]);
        _expectGeometryPreserved(result);
      },
    );

    test(
      'coalesces concurrent requests for the same uncached page key',
      () async {
        final platform = _FakeMangaTranslationPlatform()
          ..ocrResult = _ocrResult();
        final onlineTexts = <String>[];
        final service = MangaPageTranslationService(
          platform: platform,
          onlineTranslator:
              (text, {required sourceLanguage, required targetLanguage}) async {
                onlineTexts.add(text);
                return 'translated $text';
              },
        );

        Future<MangaPageTranslationResult?> request() => service.translatePage(
          pageUrl: 'https://example.test/page.jpg',
          filePath: '/local/page.jpg',
          sourceLanguage: 'ja',
          targetLanguage: 'en',
          engine: MangaTranslationEngine.online,
        );

        final requests = [request(), request()];
        final results = await Future.wait(requests);

        expect(platform.recognizeCalls, hasLength(1));
        expect(onlineTexts, ['日本語', '次の文']);
        expect(identical(results.first, results.last), isTrue);
      },
    );

    test(
      'returns an empty result without translating when OCR finds no text',
      () async {
        for (final engine in MangaTranslationEngine.values) {
          final platform = _FakeMangaTranslationPlatform()
            ..ocrResult = MangaPageOcrResult(
              imageWidth: 600,
              imageHeight: 900,
              regions: const [],
            );
          final onlineTexts = <String>[];
          final service = MangaPageTranslationService(
            platform: platform,
            onlineTranslator:
                (
                  text, {
                  required sourceLanguage,
                  required targetLanguage,
                }) async {
                  onlineTexts.add(text);
                  return 'translated $text';
                },
          );

          final result = await service.translatePage(
            pageUrl: 'https://example.test/empty.jpg',
            filePath: '/local/empty.jpg',
            sourceLanguage: 'ja',
            targetLanguage: 'en',
            engine: engine,
          );

          expect(result!.imageWidth, 600);
          expect(result.imageHeight, 900);
          expect(result.regions, isEmpty);
          expect(platform.offlineTexts, isEmpty);
          expect(onlineTexts, isEmpty);
        }
      },
    );

    test('rejects a native translation result count mismatch', () async {
      final platform = _FakeMangaTranslationPlatform()
        ..ocrResult = _ocrResult()
        ..offlineResult = ['only one'];
      final service = MangaPageTranslationService(
        platform: platform,
        onlineTranslator:
            (text, {required sourceLanguage, required targetLanguage}) async =>
                text,
      );

      await expectLater(
        service.translatePage(
          pageUrl: 'https://example.test/page-1.jpg',
          filePath: '/local/page-1.jpg',
          sourceLanguage: 'ja',
          targetLanguage: 'en',
          engine: MangaTranslationEngine.offline,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('caches independently by page URL, languages, and engine', () async {
      final platform = _FakeMangaTranslationPlatform()
        ..ocrResult = _ocrResult();
      final service = MangaPageTranslationService(
        platform: platform,
        onlineTranslator:
            (text, {required sourceLanguage, required targetLanguage}) async =>
                '$targetLanguage:$text',
      );

      Future<void> translate({
        String pageUrl = 'https://example.test/page.jpg',
        String sourceLanguage = 'ja',
        String targetLanguage = 'en',
        MangaTranslationEngine engine = MangaTranslationEngine.online,
      }) async {
        await service.translatePage(
          pageUrl: pageUrl,
          filePath: '/local/page.jpg',
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
          engine: engine,
        );
      }

      await translate();
      await translate();
      expect(platform.recognizeCalls, hasLength(1));

      await translate(pageUrl: 'https://example.test/other.jpg');
      await translate(sourceLanguage: 'ko');
      await translate(targetLanguage: 'fr');
      await translate(engine: MangaTranslationEngine.offline);
      expect(platform.recognizeCalls, hasLength(5));
    });

    test('caches online results independently by provider', () async {
      final platform = _FakeMangaTranslationPlatform();
      var generativeRequests = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              generativeRequests++;
              handler.resolve(
                Response<Object?>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'candidates': [
                      {
                        'content': {
                          'parts': [
                            {
                              'text':
                                  '{"translations":["Gemini 1", "Gemini 2"]}',
                            },
                          ],
                        },
                      },
                    ],
                  },
                ),
              );
            },
          ),
        );
      final onlineService = MangaOnlineTranslationService(
        dio: dio,
        credentials: MangaTranslationCredentialStore(
          storage: _MemorySecureStorage({
            'manga_translation_gemini_api_key': 'test-key',
          }),
        ),
        googleTranslator:
            (text, {required sourceLanguage, required targetLanguage}) async =>
                'Google $text',
      );
      final service = MangaPageTranslationService(
        platform: platform,
        onlineTranslationService: onlineService,
      );

      Future<MangaPageTranslationResult?> request(
        MangaOnlineTranslationProvider provider,
      ) => service.translatePage(
        pageUrl: 'https://example.test/same-page.jpg',
        filePath: '/local/same-page.jpg',
        sourceLanguage: 'ja',
        targetLanguage: 'en',
        engine: MangaTranslationEngine.online,
        onlineProvider: provider,
      );

      final googleResult = await request(MangaOnlineTranslationProvider.google);
      final geminiResult = await request(MangaOnlineTranslationProvider.gemini);
      final cachedGeminiResult = await request(
        MangaOnlineTranslationProvider.gemini,
      );

      expect(googleResult!.regions.map((region) => region.translatedText), [
        'Google 日本語',
        'Google 次の文',
      ]);
      expect(geminiResult!.regions.map((region) => region.translatedText), [
        'Gemini 1',
        'Gemini 2',
      ]);
      expect(identical(geminiResult, cachedGeminiResult), isTrue);
      expect(platform.recognizeCalls, hasLength(2));
      expect(generativeRequests, 1);
    });

    test('keeps only the 12 most recently used page results', () async {
      final platform = _FakeMangaTranslationPlatform()
        ..ocrResult = _ocrResult();
      final service = MangaPageTranslationService(
        platform: platform,
        onlineTranslator:
            (text, {required sourceLanguage, required targetLanguage}) async =>
                text,
      );

      Future<void> translate(int page) async {
        await service.translatePage(
          pageUrl: 'https://example.test/page-$page.jpg',
          filePath: '/local/page-$page.jpg',
          sourceLanguage: 'ja',
          targetLanguage: 'en',
          engine: MangaTranslationEngine.online,
        );
      }

      for (var page = 0; page < 12; page++) {
        await translate(page);
      }
      await translate(0); // Make page 0 the most recently used entry.
      await translate(12);
      final recognizeCountAfterEviction = platform.recognizeCalls.length;

      await translate(0);
      expect(platform.recognizeCalls, hasLength(recognizeCountAfterEviction));

      await translate(1);
      expect(
        platform.recognizeCalls,
        hasLength(recognizeCountAfterEviction + 1),
      );
    });

    test(
      'invalidates stale work without removing a newer same-key request',
      () async {
        final platform = _FakeMangaTranslationPlatform()
          ..ocrResult = _ocrResult();
        final staleTranslation = Completer<String>();
        final currentTranslation = Completer<String>();
        var translationCalls = 0;
        final service = MangaPageTranslationService(
          platform: platform,
          onlineTranslator:
              (text, {required sourceLanguage, required targetLanguage}) {
                translationCalls++;
                if (translationCalls == 1) return staleTranslation.future;
                if (translationCalls == 2) return currentTranslation.future;
                return Future.value('translated $text');
              },
        );

        Future<MangaPageTranslationResult?> request() => service.translatePage(
          pageUrl: 'https://example.test/page.jpg',
          filePath: '/local/page.jpg',
          sourceLanguage: 'ja',
          targetLanguage: 'en',
          engine: MangaTranslationEngine.online,
        );

        final staleResult = request();
        await Future<void>.delayed(Duration.zero);
        expect(translationCalls, 1);

        service.invalidatePendingRequests();
        final currentResult = request();
        await Future<void>.delayed(Duration.zero);
        expect(translationCalls, 2);
        expect(platform.recognizeCalls, hasLength(2));

        staleTranslation.complete('stale translation');
        expect(await staleResult, isNull);

        final coalescedResult = request();
        expect(translationCalls, 2);
        expect(platform.recognizeCalls, hasLength(2));

        currentTranslation.complete('translated 日本語');
        final freshResult = await currentResult;
        final secondResult = await coalescedResult;
        expect(freshResult!.regions.first.translatedText, 'translated 日本語');
        expect(identical(freshResult, secondResult), isTrue);
        expect(translationCalls, 3);
      },
    );
  });
}

class _MemorySecureStorage implements MangaTranslationSecureStorage {
  _MemorySecureStorage([Map<String, String>? initial]) : values = initial ?? {};

  final Map<String, String> values;

  @override
  Future<void> delete({required String key}) async => values.remove(key);

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}

MangaPageOcrResult _ocrResult() => MangaPageOcrResult(
  imageWidth: 1600,
  imageHeight: 2400,
  regions: [
    MangaOcrRegion(
      text: '日本語',
      normalizedBounds: const Rect.fromLTRB(0.1, 0.2, 0.5, 0.3),
    ),
    MangaOcrRegion(
      text: '次の文',
      normalizedBounds: const Rect.fromLTRB(0.2, 0.6, 0.8, 0.75),
    ),
  ],
);

void _expectGeometryPreserved(MangaPageTranslationResult result) {
  expect(result.imageWidth, 1600);
  expect(result.imageHeight, 2400);
  expect(result.regions.map((region) => region.normalizedBounds), [
    const Rect.fromLTRB(0.1, 0.2, 0.5, 0.3),
    const Rect.fromLTRB(0.2, 0.6, 0.8, 0.75),
  ]);
}

class _FakeMangaTranslationPlatform implements MangaTranslationPlatform {
  MangaPageOcrResult ocrResult = _ocrResult();
  List<String>? offlineResult;
  final recognizeCalls = <({String filePath, String sourceLanguage})>[];
  final offlineTexts =
      <({List<String> texts, String sourceLanguage, String targetLanguage})>[];

  @override
  Future<MangaPageOcrResult> recognize({
    required String filePath,
    required String sourceLanguage,
  }) async {
    recognizeCalls.add((filePath: filePath, sourceLanguage: sourceLanguage));
    return ocrResult;
  }

  @override
  Future<List<String>> translateTexts({
    required List<String> texts,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    offlineTexts.add((
      texts: List.of(texts),
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    ));
    return offlineResult ?? texts.map((text) => 'offline $text').toList();
  }

  @override
  Future<Set<String>> supportedOcrLanguages() async => const {};

  @override
  Future<Set<String>> supportedOfflineLanguages() async => const {};

  @override
  Future<MangaTranslationModelStatus> modelStatus({
    required String sourceLanguage,
    required String targetLanguage,
    required MangaTranslationEngine engine,
  }) async => const MangaTranslationModelStatus(
    ocrReady: true,
    sourceTranslationReady: true,
    targetTranslationReady: true,
  );

  @override
  Future<void> downloadModels({
    required String sourceLanguage,
    required String targetLanguage,
    required MangaTranslationEngine engine,
  }) async {}
}
