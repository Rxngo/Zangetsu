/// A language offered by one of the manga translation engines.
class MangaTranslationLanguage {
  const MangaTranslationLanguage({
    required this.code,
    required this.englishName,
    required this.script,
  });

  /// Canonical code used by the reader and the Google text translation
  /// endpoint. Chinese variants share the `zh` catalog code.
  final String code;
  final String englishName;

  /// ISO 15924 script code, used to match platform OCR script coverage.
  final String script;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MangaTranslationLanguage &&
          code == other.code &&
          englishName == other.englishName &&
          script == other.script;

  @override
  int get hashCode => Object.hash(code, englishName, script);
}

/// Language metadata and platform-model intersections for manga translation.
class MangaTranslationLanguages {
  MangaTranslationLanguages._();

  /// Languages accepted by the Google text endpoint, in picker order.
  static final List<MangaTranslationLanguage>
  online = List.unmodifiable(const <MangaTranslationLanguage>[
    MangaTranslationLanguage(
      code: 'af',
      englishName: 'Afrikaans',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'sq',
      englishName: 'Albanian',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'am',
      englishName: 'Amharic',
      script: 'Ethi',
    ),
    MangaTranslationLanguage(code: 'ar', englishName: 'Arabic', script: 'Arab'),
    MangaTranslationLanguage(
      code: 'hy',
      englishName: 'Armenian',
      script: 'Armn',
    ),
    MangaTranslationLanguage(
      code: 'az',
      englishName: 'Azerbaijani',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'eu', englishName: 'Basque', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'be',
      englishName: 'Belarusian',
      script: 'Cyrl',
    ),
    MangaTranslationLanguage(
      code: 'bn',
      englishName: 'Bengali',
      script: 'Beng',
    ),
    MangaTranslationLanguage(
      code: 'bs',
      englishName: 'Bosnian',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'bg',
      englishName: 'Bulgarian',
      script: 'Cyrl',
    ),
    MangaTranslationLanguage(
      code: 'ca',
      englishName: 'Catalan',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'ceb',
      englishName: 'Cebuano',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'zh',
      englishName: 'Chinese',
      script: 'Hans',
    ),
    MangaTranslationLanguage(
      code: 'co',
      englishName: 'Corsican',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'hr',
      englishName: 'Croatian',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'cs', englishName: 'Czech', script: 'Latn'),
    MangaTranslationLanguage(code: 'da', englishName: 'Danish', script: 'Latn'),
    MangaTranslationLanguage(code: 'nl', englishName: 'Dutch', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'en',
      englishName: 'English',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'eo',
      englishName: 'Esperanto',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'et',
      englishName: 'Estonian',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'tl',
      englishName: 'Filipino',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'fi',
      englishName: 'Finnish',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'fr', englishName: 'French', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'fy',
      englishName: 'Frisian',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'gl',
      englishName: 'Galician',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'ka',
      englishName: 'Georgian',
      script: 'Geor',
    ),
    MangaTranslationLanguage(code: 'de', englishName: 'German', script: 'Latn'),
    MangaTranslationLanguage(code: 'el', englishName: 'Greek', script: 'Grek'),
    MangaTranslationLanguage(
      code: 'gu',
      englishName: 'Gujarati',
      script: 'Gujr',
    ),
    MangaTranslationLanguage(
      code: 'ht',
      englishName: 'Haitian Creole',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'ha', englishName: 'Hausa', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'haw',
      englishName: 'Hawaiian',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'he', englishName: 'Hebrew', script: 'Hebr'),
    MangaTranslationLanguage(code: 'hi', englishName: 'Hindi', script: 'Deva'),
    MangaTranslationLanguage(code: 'hmn', englishName: 'Hmong', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'hu',
      englishName: 'Hungarian',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'is',
      englishName: 'Icelandic',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'ig', englishName: 'Igbo', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'id',
      englishName: 'Indonesian',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'ga', englishName: 'Irish', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'it',
      englishName: 'Italian',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'ja',
      englishName: 'Japanese',
      script: 'Jpan',
    ),
    MangaTranslationLanguage(
      code: 'jv',
      englishName: 'Javanese',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'kn',
      englishName: 'Kannada',
      script: 'Knda',
    ),
    MangaTranslationLanguage(code: 'kk', englishName: 'Kazakh', script: 'Cyrl'),
    MangaTranslationLanguage(code: 'km', englishName: 'Khmer', script: 'Khmr'),
    MangaTranslationLanguage(
      code: 'rw',
      englishName: 'Kinyarwanda',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'ko', englishName: 'Korean', script: 'Kore'),
    MangaTranslationLanguage(
      code: 'ku',
      englishName: 'Kurdish',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'ky', englishName: 'Kyrgyz', script: 'Cyrl'),
    MangaTranslationLanguage(code: 'lo', englishName: 'Lao', script: 'Laoo'),
    MangaTranslationLanguage(code: 'la', englishName: 'Latin', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'lv',
      englishName: 'Latvian',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'lt',
      englishName: 'Lithuanian',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'lb',
      englishName: 'Luxembourgish',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'mk',
      englishName: 'Macedonian',
      script: 'Cyrl',
    ),
    MangaTranslationLanguage(
      code: 'mg',
      englishName: 'Malagasy',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'ms', englishName: 'Malay', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'ml',
      englishName: 'Malayalam',
      script: 'Mlym',
    ),
    MangaTranslationLanguage(
      code: 'mt',
      englishName: 'Maltese',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'mi', englishName: 'Maori', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'mr',
      englishName: 'Marathi',
      script: 'Deva',
    ),
    MangaTranslationLanguage(
      code: 'mn',
      englishName: 'Mongolian',
      script: 'Cyrl',
    ),
    MangaTranslationLanguage(
      code: 'my',
      englishName: 'Myanmar',
      script: 'Mymr',
    ),
    MangaTranslationLanguage(code: 'ne', englishName: 'Nepali', script: 'Deva'),
    MangaTranslationLanguage(
      code: 'no',
      englishName: 'Norwegian',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'ny', englishName: 'Nyanja', script: 'Latn'),
    MangaTranslationLanguage(code: 'or', englishName: 'Odia', script: 'Orya'),
    MangaTranslationLanguage(code: 'ps', englishName: 'Pashto', script: 'Arab'),
    MangaTranslationLanguage(
      code: 'fa',
      englishName: 'Persian',
      script: 'Arab',
    ),
    MangaTranslationLanguage(code: 'pl', englishName: 'Polish', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'pt',
      englishName: 'Portuguese',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'pa',
      englishName: 'Punjabi',
      script: 'Guru',
    ),
    MangaTranslationLanguage(
      code: 'ro',
      englishName: 'Romanian',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'ru',
      englishName: 'Russian',
      script: 'Cyrl',
    ),
    MangaTranslationLanguage(code: 'sm', englishName: 'Samoan', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'gd',
      englishName: 'Scottish Gaelic',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'sr',
      englishName: 'Serbian',
      script: 'Cyrl',
    ),
    MangaTranslationLanguage(
      code: 'st',
      englishName: 'Sesotho',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'sn', englishName: 'Shona', script: 'Latn'),
    MangaTranslationLanguage(code: 'sd', englishName: 'Sindhi', script: 'Arab'),
    MangaTranslationLanguage(
      code: 'si',
      englishName: 'Sinhala',
      script: 'Sinh',
    ),
    MangaTranslationLanguage(code: 'sk', englishName: 'Slovak', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'sl',
      englishName: 'Slovenian',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'so', englishName: 'Somali', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'es',
      englishName: 'Spanish',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'su',
      englishName: 'Sundanese',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'sw',
      englishName: 'Swahili',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'sv',
      englishName: 'Swedish',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'tg', englishName: 'Tajik', script: 'Cyrl'),
    MangaTranslationLanguage(code: 'ta', englishName: 'Tamil', script: 'Taml'),
    MangaTranslationLanguage(code: 'tt', englishName: 'Tatar', script: 'Cyrl'),
    MangaTranslationLanguage(code: 'te', englishName: 'Telugu', script: 'Telu'),
    MangaTranslationLanguage(code: 'th', englishName: 'Thai', script: 'Thai'),
    MangaTranslationLanguage(
      code: 'tr',
      englishName: 'Turkish',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'tk',
      englishName: 'Turkmen',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'uk',
      englishName: 'Ukrainian',
      script: 'Cyrl',
    ),
    MangaTranslationLanguage(code: 'ur', englishName: 'Urdu', script: 'Arab'),
    MangaTranslationLanguage(code: 'ug', englishName: 'Uyghur', script: 'Arab'),
    MangaTranslationLanguage(code: 'uz', englishName: 'Uzbek', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'vi',
      englishName: 'Vietnamese',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'cy', englishName: 'Welsh', script: 'Latn'),
    MangaTranslationLanguage(code: 'xh', englishName: 'Xhosa', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'yi',
      englishName: 'Yiddish',
      script: 'Hebr',
    ),
    MangaTranslationLanguage(code: 'yo', englishName: 'Yoruba', script: 'Latn'),
    MangaTranslationLanguage(code: 'zu', englishName: 'Zulu', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'ace',
      englishName: 'Acehnese',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'ach',
      englishName: 'Acholi',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'awa',
      englishName: 'Awadhi',
      script: 'Deva',
    ),
    MangaTranslationLanguage(
      code: 'ban',
      englishName: 'Balinese',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'bem', englishName: 'Bemba', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'bho',
      englishName: 'Bhojpuri',
      script: 'Deva',
    ),
    MangaTranslationLanguage(code: 'bik', englishName: 'Bikol', script: 'Latn'),
    MangaTranslationLanguage(code: 'din', englishName: 'Dinka', script: 'Latn'),
    MangaTranslationLanguage(code: 'doi', englishName: 'Dogri', script: 'Deva'),
    MangaTranslationLanguage(
      code: 'dty',
      englishName: 'Dotyali',
      script: 'Deva',
    ),
    MangaTranslationLanguage(code: 'fj', englishName: 'Fijian', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'gom',
      englishName: 'Konkani',
      script: 'Deva',
    ),
    MangaTranslationLanguage(
      code: 'ilo',
      englishName: 'Ilocano',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'kha', englishName: 'Khasi', script: 'Latn'),
    MangaTranslationLanguage(code: 'kri', englishName: 'Krio', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'mai',
      englishName: 'Maithili',
      script: 'Deva',
    ),
    MangaTranslationLanguage(
      code: 'mak',
      englishName: 'Makassar',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'lus', englishName: 'Mizo', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'mni',
      englishName: 'Meitei',
      script: 'Beng',
    ),
    MangaTranslationLanguage(code: 'mos', englishName: 'Mossi', script: 'Latn'),
    MangaTranslationLanguage(
      code: 'pap',
      englishName: 'Papiamento',
      script: 'Latn',
    ),
    MangaTranslationLanguage(
      code: 'sa',
      englishName: 'Sanskrit',
      script: 'Deva',
    ),
    MangaTranslationLanguage(
      code: 'sat',
      englishName: 'Santali',
      script: 'Olck',
    ),
    MangaTranslationLanguage(
      code: 'scn',
      englishName: 'Sicilian',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'shn', englishName: 'Shan', script: 'Mymr'),
    MangaTranslationLanguage(
      code: 'ti',
      englishName: 'Tigrinya',
      script: 'Ethi',
    ),
    MangaTranslationLanguage(
      code: 'tum',
      englishName: 'Tumbuka',
      script: 'Latn',
    ),
    MangaTranslationLanguage(code: 'war', englishName: 'Waray', script: 'Latn'),
  ]);

  static final Map<String, MangaTranslationLanguage> _byCode = {
    for (final language in online) language.code: language,
  };

  static const Map<String, String> _codeAliases = {
    'fil': 'tl',
    'he': 'he',
    'iw': 'he',
    'jv': 'jv',
    'jw': 'jv',
    'nb': 'no',
    'nn': 'no',
  };

  /// Resolve a platform language or locale tag to an online catalog code.
  ///
  /// Region and script subtags are accepted (`pt-BR`, `zh-Hant-TW`,
  /// `ja_JP`). `null` means the platform tag is not represented by the
  /// catalog.
  static String? canonicalCodeFor(String nativeTag) {
    final tag = nativeTag.trim().replaceAll('_', '-').toLowerCase();
    if (tag.isEmpty) return null;
    final baseCode = tag.split('-').first;
    final code = _codeAliases[baseCode] ?? baseCode;
    return _byCode.containsKey(code) ? code : null;
  }

  /// Languages supported by platform OCR tags or OCR script coverage.
  ///
  /// Exact locale tags select their language. A bare ISO 15924 script tag
  /// (such as `Latn`) selects only catalog languages written in that script.
  /// Results retain the online catalog order and never include other scripts.
  static List<MangaTranslationLanguage> ocrIntersection(
    Iterable<String> nativeTags,
  ) {
    final codes = <String>{};
    final scripts = <String>{};
    for (final tag in nativeTags) {
      final code = canonicalCodeFor(tag);
      if (code != null) {
        codes.add(code);
      } else {
        final script = _canonicalScriptFor(tag);
        if (script != null) scripts.add(script);
      }
    }
    return List.unmodifiable(
      online.where(
        (language) =>
            codes.contains(language.code) ||
            scripts.contains(language.script) ||
            (language.code == 'zh' && scripts.contains('Hant')),
      ),
    );
  }

  /// Catalog languages for which an offline model is available.
  ///
  /// Native codes are normalized to catalog codes and duplicates collapse.
  /// Unlike OCR script coverage, a model for one language does not imply a
  /// model for every language that uses the same writing system.
  static List<MangaTranslationLanguage> offlineIntersection(
    Iterable<String> nativeTags,
  ) {
    final codes = nativeTags.map(canonicalCodeFor).whereType<String>().toSet();
    return List.unmodifiable(
      online.where((language) => codes.contains(language.code)),
    );
  }

  static String? _canonicalScriptFor(String tag) {
    final value = tag.trim().toLowerCase();
    const scripts = {
      'arab': 'Arab',
      'armn': 'Armn',
      'beng': 'Beng',
      'cyrl': 'Cyrl',
      'deva': 'Deva',
      'ethi': 'Ethi',
      'geor': 'Geor',
      'grek': 'Grek',
      'gujr': 'Gujr',
      'guru': 'Guru',
      'hani': 'Hans',
      'hans': 'Hans',
      'hant': 'Hant',
      'hebr': 'Hebr',
      'jpan': 'Jpan',
      'knda': 'Knda',
      'khmr': 'Khmr',
      'kore': 'Kore',
      'laoo': 'Laoo',
      'latn': 'Latn',
      'mlym': 'Mlym',
      'mong': 'Mong',
      'mymr': 'Mymr',
      'olck': 'Olck',
      'orya': 'Orya',
      'sinh': 'Sinh',
      'taml': 'Taml',
      'telu': 'Telu',
      'thai': 'Thai',
    };
    return scripts[value];
  }
}
