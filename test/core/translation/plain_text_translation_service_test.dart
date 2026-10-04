import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/playback/subtitle_translate_service.dart';
import 'package:watch_app/core/translation/plain_text_translation_service.dart';

const _translationBody =
    '[[["Hola ","Hello ",null,null,3],'
    '["mundo","world",null,null,3]],null,"en"]';

Dio _dioRespondingWith(String body) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response<String>(
            requestOptions: options,
            data: body,
            statusCode: 200,
          ),
        );
      },
    ),
  );
  return dio;
}

void main() {
  test(
    'sends exact text params and joins translated response segments',
    () async {
      late RequestOptions request;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<String>(
                requestOptions: options,
                data: _translationBody,
                statusCode: 200,
              ),
            );
          },
        ),
      );
      final service = PlainTextTranslationService(dio: dio);

      final translated = await service.translate(
        'Hello world',
        sourceLanguage: 'fr',
        targetLanguage: 'es',
      );

      expect(
        request.uri.toString(),
        'https://translate.googleapis.com/translate_a/single?client=dict-chrome-ex&sl=fr&tl=es&dt=t&q=Hello+world',
      );
      expect(request.queryParameters, {
        'client': 'dict-chrome-ex',
        'sl': 'fr',
        'tl': 'es',
        'dt': 't',
        'q': 'Hello world',
      });
      expect(request.responseType, ResponseType.plain);
      expect(request.connectTimeout, const Duration(seconds: 12));
      expect(request.receiveTimeout, const Duration(seconds: 12));
      expect(translated, 'Hola mundo');
    },
  );

  test('throws FormatException for a malformed response body', () async {
    final service = PlainTextTranslationService(
      dio: _dioRespondingWith('not json'),
    );

    await expectLater(
      service.translate('Hello', sourceLanguage: 'auto', targetLanguage: 'es'),
      throwsA(isA<FormatException>()),
    );
  });

  test('throws FormatException for block pages and empty responses', () async {
    for (final body in ['<html>blocked</html>', '  ']) {
      final service = PlainTextTranslationService(
        dio: _dioRespondingWith(body),
      );

      await expectLater(
        service.translate(
          'Hello',
          sourceLanguage: 'auto',
          targetLanguage: 'es',
        ),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test(
    'subtitle block response logs without text and keeps original line',
    () async {
      final previousDebugPrint = debugPrint;
      final diagnostics = <String>[];
      debugPrint = (message, {wrapWidth}) {
        if (message != null) diagnostics.add(message);
      };
      addTearDown(() => debugPrint = previousDebugPrint);

      final service = SubtitleTranslateService.forTesting(
        translationService: PlainTextTranslationService(
          dio: _dioRespondingWith('<html>blocked</html>'),
        ),
      );
      const subtitleText = 'Sensitive subtitle text';
      final translated = await service.translate(
        '1\n00:00:01,000 --> 00:00:02,000\n$subtitleText\n',
        'es',
      );

      expect(translated, contains(subtitleText));
      expect(diagnostics, [
        '[translate] unparseable response for "es" — blocked?',
      ]);
      expect(diagnostics.join(), isNot(contains(subtitleText)));
    },
  );

  test('lets transport failures reach the caller', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ),
        ),
      ),
    );
    final service = PlainTextTranslationService(dio: dio);

    await expectLater(
      service.translate('Hello', sourceLanguage: 'auto', targetLanguage: 'es'),
      throwsA(isA<DioException>()),
    );
  });
}
