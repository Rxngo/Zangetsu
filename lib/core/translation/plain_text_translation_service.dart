import 'dart:convert';

import 'package:dio/dio.dart';

/// Translates plain text with Google's keyless translation endpoint.
///
/// This service accepts text only. It does not read or send image, file, or
/// page data.
class PlainTextTranslationService {
  PlainTextTranslationService({Dio? dio}) : _dio = dio ?? _createDio();

  static const _endpoint =
      'https://translate.googleapis.com/translate_a/single';
  static const _timeout = Duration(seconds: 12);

  final Dio _dio;

  /// Translates [text] from [sourceLanguage] into [targetLanguage].
  ///
  /// Throws a [FormatException] when the endpoint returns an empty, blocked,
  /// or unrecognised response. Dio transport failures are allowed to reach the
  /// caller so each consumer can choose how to handle them.
  Future<String> translate(
    String text, {
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    final response = await _dio.get<String>(
      _endpoint,
      queryParameters: {
        'client': 'dict-chrome-ex',
        'sl': sourceLanguage,
        'tl': targetLanguage,
        'dt': 't',
        'q': text,
      },
      options: Options(
        responseType: ResponseType.plain,
        connectTimeout: _timeout,
        receiveTimeout: _timeout,
      ),
    );

    final translated = parseTranslatedBody(response.data);
    if (translated == null || translated.isEmpty) {
      throw const FormatException('Invalid translation response body');
    }
    return translated;
  }

  /// Extracts translated segments, joining them in endpoint order.
  ///
  /// Returns null for an empty, blocked, or malformed body. Kept nullable so
  /// the subtitle service can preserve its existing test-compatible parser.
  static String? parseTranslatedBody(String? body) {
    final raw = body?.trim();
    if (raw == null || raw.isEmpty || raw.startsWith('<')) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! List || data.isEmpty || data[0] is! List) return null;
      return (data[0] as List)
          .map(
            (segment) => (segment is List && segment.isNotEmpty)
                ? (segment[0]?.toString() ?? '')
                : '',
          )
          .join();
    } catch (_) {
      return null;
    }
  }

  static Dio _createDio() => Dio(
    BaseOptions(
      responseType: ResponseType.plain,
      connectTimeout: _timeout,
      receiveTimeout: _timeout,
    ),
  );
}
