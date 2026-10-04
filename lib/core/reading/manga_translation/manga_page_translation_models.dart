import 'dart:ui';

/// The network or on-device engine used to translate a manga page.
enum MangaTranslationEngine { online, offline }

/// Online service used to translate OCR text from a manga page.
enum MangaOnlineTranslationProvider { google, gemini, groq }

/// Identifies one page-translation request in a cache.
///
/// The page URL, direction, and engine all affect the result, so all four
/// fields participate in equality and hashing.
class MangaPageTranslationKey {
  const MangaPageTranslationKey({
    required this.pageUrl,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.engine,
    this.onlineProvider = MangaOnlineTranslationProvider.google,
  });

  final String pageUrl;
  final String sourceLanguage;
  final String targetLanguage;
  final MangaTranslationEngine engine;
  final MangaOnlineTranslationProvider onlineProvider;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MangaPageTranslationKey &&
          pageUrl == other.pageUrl &&
          sourceLanguage == other.sourceLanguage &&
          targetLanguage == other.targetLanguage &&
          engine == other.engine &&
          onlineProvider == other.onlineProvider;

  @override
  int get hashCode => Object.hash(
    pageUrl,
    sourceLanguage,
    targetLanguage,
    engine,
    onlineProvider,
  );
}

/// Whether [bounds] can be used as normalized page coordinates.
///
/// Bounds use top-left origin coordinates from 0 to 1, inclusive. Rejecting
/// invalid values here keeps OCR output safe to scale and paint over a page.
bool isValidNormalizedBounds(Rect bounds) {
  return bounds.left.isFinite &&
      bounds.top.isFinite &&
      bounds.right.isFinite &&
      bounds.bottom.isFinite &&
      bounds.left >= 0 &&
      bounds.top >= 0 &&
      bounds.right <= 1 &&
      bounds.bottom <= 1 &&
      bounds.left <= bounds.right &&
      bounds.top <= bounds.bottom;
}

void _validateNormalizedBounds(Rect bounds) {
  if (!isValidNormalizedBounds(bounds)) {
    throw ArgumentError.value(
      bounds,
      'normalizedBounds',
      'must be finite, ordered, and within [0, 1]',
    );
  }
}

void _validateImageDimensions(int imageWidth, int imageHeight) {
  if (imageWidth <= 0) {
    throw ArgumentError.value(imageWidth, 'imageWidth', 'must be positive');
  }
  if (imageHeight <= 0) {
    throw ArgumentError.value(imageHeight, 'imageHeight', 'must be positive');
  }
}

/// One recognized text region on a manga page.
class MangaOcrRegion {
  MangaOcrRegion({required this.text, required Rect normalizedBounds})
    : normalizedBounds = normalizedBounds {
    _validateNormalizedBounds(normalizedBounds);
  }

  final String text;
  final Rect normalizedBounds;
}

/// One translated text region, positioned over its original text.
class MangaTranslatedRegion {
  MangaTranslatedRegion({
    required this.originalText,
    required this.translatedText,
    required Rect normalizedBounds,
  }) : normalizedBounds = normalizedBounds {
    _validateNormalizedBounds(normalizedBounds);
  }

  final String originalText;
  final String translatedText;
  final Rect normalizedBounds;
}

/// OCR regions and source-image dimensions for one page.
class MangaPageOcrResult {
  MangaPageOcrResult({
    required this.imageWidth,
    required this.imageHeight,
    required Iterable<MangaOcrRegion> regions,
  }) : regions = List.unmodifiable(regions) {
    _validateImageDimensions(imageWidth, imageHeight);
  }

  final int imageWidth;
  final int imageHeight;
  final List<MangaOcrRegion> regions;
}

/// Translated regions and source-image dimensions for one page.
class MangaPageTranslationResult {
  MangaPageTranslationResult({
    required this.imageWidth,
    required this.imageHeight,
    required Iterable<MangaTranslatedRegion> regions,
  }) : regions = List.unmodifiable(regions) {
    _validateImageDimensions(imageWidth, imageHeight);
  }

  final int imageWidth;
  final int imageHeight;
  final List<MangaTranslatedRegion> regions;
}

/// Readiness of local OCR and offline translation models.
class MangaTranslationModelStatus {
  const MangaTranslationModelStatus({
    required this.ocrReady,
    required this.sourceTranslationReady,
    required this.targetTranslationReady,
  });

  final bool ocrReady;
  final bool sourceTranslationReady;
  final bool targetTranslationReady;

  /// Whether the models needed by [engine] are ready to translate a page.
  ///
  /// Online translation does not require local translation models, but still
  /// needs OCR. Offline translation needs OCR and both language models.
  bool isReadyFor(MangaTranslationEngine engine) {
    if (!ocrReady) return false;
    return switch (engine) {
      MangaTranslationEngine.online => true,
      MangaTranslationEngine.offline =>
        sourceTranslationReady && targetTranslationReady,
    };
  }

  /// Whether using [engine] requires consent to set up missing local models.
  bool requiresConsentFor(MangaTranslationEngine engine) =>
      !ocrReady ||
      (engine == MangaTranslationEngine.offline &&
          (!sourceTranslationReady || !targetTranslationReady));
}
