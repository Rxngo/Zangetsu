import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/playback/playback_prefs.dart';
import 'package:watch_app/core/reading/manga_translation/manga_page_translation_models.dart';
import 'package:watch_app/core/reading/reader_prefs.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('reader_prefs');
    Hive.init(dir.path);
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('defaults', () async {
    await ReaderPrefs.init();
    final p = ReaderPrefs();
    expect(p.fontSize, 16);
    expect(p.lineHeight, 1.6);
    expect(p.theme, 'dark');
    expect(p.marginWidth, 20);
    expect(p.direction, 'ltr');
    expect(p.background, 'black');
    expect(p.keepScreenOn, isTrue);
  });

  test('persists changes', () async {
    await ReaderPrefs.init();
    final p = ReaderPrefs();
    await p.setFontSize(20);
    await p.setDirection('rtl');
    final q = ReaderPrefs();
    expect(q.fontSize, 20);
    expect(q.direction, 'rtl');
  });

  test(
    'manga translation preferences round-trip without changing subtitles',
    () async {
      await ReaderPrefs.init();
      await PlaybackPrefs.init();
      final readerPrefs = ReaderPrefs();
      final playbackPrefs = PlaybackPrefs();
      await playbackPrefs.setSubtitlePreference('fr');
      await playbackPrefs.setTranslateSubtitleTo('de');

      await readerPrefs.setMangaTranslationSourceLanguage('ko');
      await readerPrefs.setMangaTranslationTargetLanguage('hi');
      await readerPrefs.setMangaTranslationEngine(
        MangaTranslationEngine.offline,
      );
      await readerPrefs.setMangaOnlineTranslationProvider(
        MangaOnlineTranslationProvider.groq,
      );

      final reloadedReaderPrefs = ReaderPrefs();
      expect(reloadedReaderPrefs.mangaTranslationSourceLanguage, 'ko');
      expect(reloadedReaderPrefs.mangaTranslationTargetLanguage, 'hi');
      expect(
        reloadedReaderPrefs.mangaTranslationEngine,
        MangaTranslationEngine.offline,
      );
      expect(
        reloadedReaderPrefs.mangaOnlineTranslationProvider,
        MangaOnlineTranslationProvider.groq,
      );
      expect(playbackPrefs.subtitlePreference, 'fr');
      expect(playbackPrefs.translateSubtitleTo, 'de');
    },
  );

  test(
    'manga translation appearance preferences persist independently',
    () async {
      await ReaderPrefs.init();
      final prefs = ReaderPrefs();

      expect(prefs.mangaTranslationFontSize, 14);
      expect(prefs.mangaTranslationTextColor, Colors.white);
      expect(prefs.mangaTranslationBackgroundColor, Colors.black);
      expect(prefs.mangaTranslationBackgroundOpacity, 1);

      await prefs.setMangaTranslationFontSize(21.5);
      await prefs.setMangaTranslationTextColor(const Color(0xFF123456));
      await prefs.setMangaTranslationBackgroundColor(const Color(0xFFABCDEF));
      await prefs.setMangaTranslationBackgroundOpacity(0.35);

      final reloadedPrefs = ReaderPrefs();
      expect(reloadedPrefs.mangaTranslationFontSize, 21.5);
      expect(reloadedPrefs.mangaTranslationTextColor, const Color(0xFF123456));
      expect(
        reloadedPrefs.mangaTranslationBackgroundColor,
        const Color(0xFFABCDEF),
      );
      expect(reloadedPrefs.mangaTranslationBackgroundOpacity, 0.35);
    },
  );

  test(
    'unknown persisted manga translation engine falls back to online',
    () async {
      await ReaderPrefs.init();
      await Hive.box(
        ReaderPrefs.boxName,
      ).put('mangaTranslationEngine', 'future');

      expect(
        ReaderPrefs().mangaTranslationEngine,
        MangaTranslationEngine.online,
      );
    },
  );

  test(
    'unknown persisted manga online provider falls back to Google',
    () async {
      await ReaderPrefs.init();
      await Hive.box(
        ReaderPrefs.boxName,
      ).put('mangaOnlineTranslationProvider', 'future');

      expect(
        ReaderPrefs().mangaOnlineTranslationProvider,
        MangaOnlineTranslationProvider.google,
      );
    },
  );

  test('numeric prefs coerce int round-trips to double', () async {
    // A double-typed setter always converts its argument to a real double
    // before it hits the box, so calling setFontSize(20) can never reproduce
    // the trap. Hive itself can still hand back a stored int for a field
    // that's typed double (e.g. a value written by an older schema, or a
    // raw Hive edit) — write straight to the box, bypassing the setters, to
    // reproduce that. The getter must still hand back a double or this
    // throws a cast error.
    await ReaderPrefs.init();
    final box = Hive.box(ReaderPrefs.boxName);
    await box.put('fontSize', 20);
    await box.put('lineHeight', 2);
    await box.put('marginWidth', 30);
    final p = ReaderPrefs();
    expect(p.fontSize, isA<double>());
    expect(p.fontSize, 20.0);
    expect(p.lineHeight, isA<double>());
    expect(p.lineHeight, 2.0);
    expect(p.marginWidth, isA<double>());
    expect(p.marginWidth, 30.0);
  });
}
