import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/reading/manga_translation/manga_online_translation_service.dart';
import 'package:watch_app/core/reading/manga_translation/manga_page_translation_models.dart';
import 'package:watch_app/core/reading/manga_translation/manga_translation_credential_store.dart';

void main() {
  group('MangaOnlineTranslationService', () {
    test('keeps the current Google text-only behavior', () async {
      final googleTexts = <String>[];
      final service = MangaOnlineTranslationService(
        googleTranslator:
            (text, {required sourceLanguage, required targetLanguage}) async {
              googleTexts.add(text);
              return '$targetLanguage:$text';
            },
      );

      final result = await service.translateTexts(
        provider: MangaOnlineTranslationProvider.google,
        texts: const ['日本語', '続き'],
        sourceLanguage: 'ja',
        targetLanguage: 'en',
      );

      expect(googleTexts, ['日本語', '続き']);
      expect(result, ['en:日本語', 'en:続き']);
    });

    test('sends Gemini only OCR text with its key in the header', () async {
      final credentials = MangaTranslationCredentialStore(
        storage: _MemorySecureStorage({
          'manga_translation_gemini_api_key': 'g-key',
        }),
      );
      RequestOptions? request;
      final dio = _respondWith((options) {
        request = options;
        return {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': '{"translations":["Hello", "Goodbye"]}'},
                ],
              },
            },
          ],
        };
      });
      final service = MangaOnlineTranslationService(
        dio: dio,
        credentials: credentials,
      );

      final result = await service.translateTexts(
        provider: MangaOnlineTranslationProvider.gemini,
        texts: const ['こんにちは', 'さようなら'],
        sourceLanguage: 'ja',
        targetLanguage: 'en',
      );

      expect(result, ['Hello', 'Goodbye']);
      expect(
        request!.uri.toString(),
        contains('/models/gemini-3.5-flash-lite:generateContent'),
      );
      expect(request!.headers['x-goog-api-key'], 'g-key');
      expect(request!.uri.queryParameters, isEmpty);
      final body = request!.data as Map<String, dynamic>;
      expect(body['contents'].toString(), contains('こんにちは'));
      expect(body['contents'].toString(), contains('さようなら'));
      expect((body['generationConfig'] as Map)['responseFormat'], {
        'text': {
          'mimeType': 'APPLICATION_JSON',
          'schema': {
            'type': 'object',
            'properties': {
              'translations': {
                'type': 'array',
                'items': {'type': 'string'},
              },
            },
            'required': ['translations'],
          },
        },
      });
      expect(body.toString(), isNot(contains('filePath')));
      expect(body.toString(), isNot(contains('https://')));
    });

    test(
      'sends Groq a single ordered JSON request with a bearer key',
      () async {
        final credentials = MangaTranslationCredentialStore(
          storage: _MemorySecureStorage({
            'manga_translation_groq_api_key': 'r-key',
          }),
        );
        RequestOptions? request;
        final dio = _respondWith((options) {
          request = options;
          return {
            'choices': [
              {
                'message': {'content': '{"translations":["Bonjour", "Merci"]}'},
              },
            ],
          };
        });
        final service = MangaOnlineTranslationService(
          dio: dio,
          credentials: credentials,
        );

        final result = await service.translateTexts(
          provider: MangaOnlineTranslationProvider.groq,
          texts: const ['こんにちは', 'ありがとう'],
          sourceLanguage: 'ja',
          targetLanguage: 'fr',
        );

        expect(result, ['Bonjour', 'Merci']);
        expect(
          request!.uri.toString(),
          'https://api.groq.com/openai/v1/chat/completions',
        );
        expect(request!.headers['Authorization'], 'Bearer r-key');
        expect(request!.uri.queryParameters, isEmpty);
        final body = request!.data as Map<String, dynamic>;
        expect(body['model'], 'openai/gpt-oss-20b');
        expect(body['response_format'], {'type': 'json_object'});
        expect(body['messages'].toString(), contains('こんにちは'));
        expect(body['messages'].toString(), contains('ありがとう'));
      },
    );

    test(
      'rejects a generative provider request until its key is configured',
      () async {
        var requestCount = 0;
        final service = MangaOnlineTranslationService(
          dio: Dio()
            ..interceptors.add(
              InterceptorsWrapper(
                onRequest: (options, handler) {
                  requestCount++;
                  handler.next(options);
                },
              ),
            ),
          credentials: MangaTranslationCredentialStore(
            storage: _MemorySecureStorage(),
          ),
        );

        await expectLater(
          service.translateTexts(
            provider: MangaOnlineTranslationProvider.groq,
            texts: const ['source'],
            sourceLanguage: 'ja',
            targetLanguage: 'en',
          ),
          throwsA(isA<MangaOnlineTranslationException>()),
        );
        expect(requestCount, 0);
      },
    );

    test('rejects malformed or count-mismatched provider output', () async {
      final service = MangaOnlineTranslationService(
        dio: _respondWith(
          (_) => {
            'choices': [
              {
                'message': {'content': '{"translations":["one"]}'},
              },
            ],
          },
        ),
        credentials: MangaTranslationCredentialStore(
          storage: _MemorySecureStorage({
            'manga_translation_groq_api_key': 'r-key',
          }),
        ),
      );

      await expectLater(
        service.translateTexts(
          provider: MangaOnlineTranslationProvider.groq,
          texts: const ['one', 'two'],
          sourceLanguage: 'ja',
          targetLanguage: 'en',
        ),
        throwsA(isA<MangaOnlineTranslationException>()),
      );
    });

    test('logs safe diagnostics for rejected provider requests', () async {
      const apiKey = 'private-provider-key';
      const recognizedText = 'private manga text';
      final diagnostics = <String>[];
      final credentials = MangaTranslationCredentialStore(
        storage: _MemorySecureStorage({
          'manga_translation_gemini_api_key': apiKey,
        }),
      );
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response<Object?>(
                    requestOptions: options,
                    statusCode: 400,
                    data: {
                      'error': {
                        'code': 400,
                        'status': 'INVALID_ARGUMENT',
                        'message': 'Rejected $recognizedText using $apiKey',
                      },
                    },
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );
      final service = MangaOnlineTranslationService(
        dio: dio,
        credentials: credentials,
        diagnosticLogger: diagnostics.add,
      );

      await expectLater(
        service.translateTexts(
          provider: MangaOnlineTranslationProvider.gemini,
          texts: const [recognizedText],
          sourceLanguage: 'ja',
          targetLanguage: 'en',
        ),
        throwsA(
          isA<MangaOnlineTranslationException>().having(
            (error) => error.failure,
            'failure',
            MangaOnlineTranslationFailure.unavailable,
          ),
        ),
      );

      expect(diagnostics, hasLength(1));
      expect(diagnostics.single, contains('provider=gemini'));
      expect(diagnostics.single, contains('httpStatus=400'));
      expect(diagnostics.single, contains('providerStatus=INVALID_ARGUMENT'));
      expect(diagnostics.single, contains('[redacted]'));
      expect(diagnostics.single, isNot(contains(apiKey)));
      expect(diagnostics.single, isNot(contains(recognizedText)));
    });
  });
}

Dio _respondWith(Object? Function(RequestOptions) body) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response<Object?>(
            requestOptions: options,
            statusCode: 200,
            data: body(options),
          ),
        );
      },
    ),
  );
  return dio;
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
