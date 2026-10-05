import 'dart:collection';

import 'manga_page_translation_models.dart';
import 'manga_online_translation_service.dart';
import 'manga_translation_platform.dart';

/// Translates OCR text for one page when explicitly requested by the reader.
class MangaPageTranslationService {
  MangaPageTranslationService({
    MangaTranslationPlatform? platform,
    MangaOnlineTextTranslator? onlineTranslator,
    MangaOnlineTranslationService? onlineTranslationService,
  }) : _platform = platform ?? const MangaTranslationMethodChannelPlatform(),
       _onlineTranslationService =
           onlineTranslationService ??
           MangaOnlineTranslationService(googleTranslator: onlineTranslator);

  /// Maximum number of translated pages held in this service's memory cache.
  static const maxCachedPages = 12;

  final MangaTranslationPlatform _platform;
  final MangaOnlineTranslationService _onlineTranslationService;
  final LinkedHashMap<MangaPageTranslationKey, MangaPageTranslationResult>
  _cache = LinkedHashMap();
  final Map<MangaPageTranslationKey, Future<MangaPageTranslationResult?>>
  _inFlight = {};

  int _requestGeneration = 0;

  /// Languages the active platform can recognize with its local OCR engine.
  Future<Set<String>> supportedOcrLanguages() =>
      _platform.supportedOcrLanguages();

  /// Languages available to the optional on-device translation engine.
  /// Platforms with no offline engine return an empty set.
  Future<Set<String>> supportedOfflineLanguages() =>
      _platform.supportedOfflineLanguages();

  /// Checks local OCR/translation model readiness without downloading them.
  Future<MangaTranslationModelStatus> modelStatus({
    required String sourceLanguage,
    required String targetLanguage,
    required MangaTranslationEngine engine,
  }) => _platform.modelStatus(
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    engine: engine,
  );

  /// Downloads missing models after the reader has obtained user consent.
  Future<void> downloadModels({
    required String sourceLanguage,
    required String targetLanguage,
    required MangaTranslationEngine engine,
  }) => _platform.downloadModels(
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    engine: engine,
  );

  Future<bool> isProviderConfigured(
    MangaOnlineTranslationProvider provider,
  ) async {
    try {
      return await _onlineTranslationService.isProviderConfigured(provider);
    } on Object {
      // A secure-store read issue must not block the existing Google path or
      // opening reader settings. The provider remains unavailable until its
      // key can be saved successfully.
      return false;
    }
  }

  Future<void> saveProviderKey(
    MangaOnlineTranslationProvider provider,
    String key,
  ) => _onlineTranslationService.saveProviderKey(provider, key);

  Future<void> removeProviderKey(MangaOnlineTranslationProvider provider) =>
      _onlineTranslationService.removeProviderKey(provider);

  /// Invalidates pending requests after the reader page or translation config
  /// changes. Native work already in progress may finish, but its result is
  /// discarded and is not added to the cache.
  void invalidatePendingRequests() {
    _requestGeneration++;
    _inFlight.clear();
  }

  /// Recognizes and translates [filePath] for this page.
  ///
  /// Call this method only in response to an explicit reader action. OCR gets
  /// only the local image path. Online translation receives each OCR string
  /// through the text-only translator; offline translation uses the native
  /// text translation method.
  ///
  /// Returns null if [invalidatePendingRequests] is called before this request
  /// completes.
  Future<MangaPageTranslationResult?> translatePage({
    required String pageUrl,
    required String filePath,
    required String sourceLanguage,
    required String targetLanguage,
    required MangaTranslationEngine engine,
    MangaOnlineTranslationProvider onlineProvider =
        MangaOnlineTranslationProvider.google,
  }) {
    final generation = _requestGeneration;
    final key = MangaPageTranslationKey(
      pageUrl: pageUrl,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      engine: engine,
      onlineProvider: engine == MangaTranslationEngine.online
          ? onlineProvider
          : MangaOnlineTranslationProvider.google,
    );
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return Future.value(cached);
    }

    final pending = _inFlight[key];
    if (pending != null) return pending;

    late final Future<MangaPageTranslationResult?> request;
    request =
        _translatePage(
          key: key,
          filePath: filePath,
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
          engine: engine,
          onlineProvider: key.onlineProvider,
          generation: generation,
        ).whenComplete(() {
          if (identical(_inFlight[key], request)) {
            _inFlight.remove(key);
          }
        });
    _inFlight[key] = request;
    return request;
  }

  Future<MangaPageTranslationResult?> _translatePage({
    required MangaPageTranslationKey key,
    required String filePath,
    required String sourceLanguage,
    required String targetLanguage,
    required MangaTranslationEngine engine,
    required MangaOnlineTranslationProvider onlineProvider,
    required int generation,
  }) async {
    try {
      final ocrResult = await _platform.recognize(
        filePath: filePath,
        sourceLanguage: sourceLanguage,
      );
      if (generation != _requestGeneration) return null;

      if (ocrResult.regions.isEmpty) {
        final result = MangaPageTranslationResult(
          imageWidth: ocrResult.imageWidth,
          imageHeight: ocrResult.imageHeight,
          regions: const [],
        );
        _cacheResult(key, result);
        return result;
      }

      final sourceTexts = ocrResult.regions
          .map((region) => region.text)
          .toList(growable: false);
      final translatedTexts = switch (engine) {
        MangaTranslationEngine.online => await _translateOnline(
          sourceTexts,
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
          provider: onlineProvider,
          generation: generation,
        ),
        MangaTranslationEngine.offline => await _translateOffline(
          sourceTexts,
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
          generation: generation,
        ),
      };
      if (translatedTexts == null || generation != _requestGeneration) {
        return null;
      }
      if (translatedTexts.length != ocrResult.regions.length) {
        throw FormatException(
          'Received ${translatedTexts.length} translations for '
          '${ocrResult.regions.length} OCR regions',
        );
      }

      final result = MangaPageTranslationResult(
        imageWidth: ocrResult.imageWidth,
        imageHeight: ocrResult.imageHeight,
        regions: [
          for (var index = 0; index < ocrResult.regions.length; index++)
            MangaTranslatedRegion(
              originalText: ocrResult.regions[index].text,
              translatedText: translatedTexts[index],
              normalizedBounds: ocrResult.regions[index].normalizedBounds,
            ),
        ],
      );
      if (generation != _requestGeneration) return null;

      _cacheResult(key, result);
      return result;
    } on Object {
      if (generation != _requestGeneration) return null;
      rethrow;
    }
  }

  void _cacheResult(
    MangaPageTranslationKey key,
    MangaPageTranslationResult result,
  ) {
    _cache.remove(key);
    _cache[key] = result;
    if (_cache.length > maxCachedPages) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<List<String>?> _translateOnline(
    List<String> texts, {
    required String sourceLanguage,
    required String targetLanguage,
    required MangaOnlineTranslationProvider provider,
    required int generation,
  }) => _onlineTranslationService.translateTexts(
    provider: provider,
    texts: texts,
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    isCurrent: () => generation == _requestGeneration,
  );

  Future<List<String>?> _translateOffline(
    List<String> texts, {
    required String sourceLanguage,
    required String targetLanguage,
    required int generation,
  }) async {
    final translated = await _platform.translateTexts(
      texts: texts,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
    if (generation != _requestGeneration) return null;
    if (translated.length != texts.length) {
      throw FormatException(
        'Native translation returned ${translated.length} strings for '
        '${texts.length} inputs',
      );
    }
    return translated;
  }
}
