import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/reading/reader_prefs.dart';
import 'package:watch_app/features/reader/manga_translation_appearance_sheet.dart';

class _AppearancePrefs extends ReaderPrefs {
  double translationFontSize = 20;
  double backgroundOpacity = 0.4;
  Color textColor = ReaderPrefs.defaultMangaTranslationTextColor;
  Color backgroundColor = ReaderPrefs.defaultMangaTranslationBackgroundColor;

  @override
  double get mangaTranslationFontSize => translationFontSize;

  @override
  Future<void> setMangaTranslationFontSize(double value) async {
    translationFontSize = value;
  }

  @override
  double get mangaTranslationBackgroundOpacity => backgroundOpacity;

  @override
  Future<void> setMangaTranslationBackgroundOpacity(double value) async {
    backgroundOpacity = value;
  }

  @override
  Color get mangaTranslationTextColor => textColor;

  @override
  Future<void> setMangaTranslationTextColor(Color value) async {
    textColor = value;
  }

  @override
  Color get mangaTranslationBackgroundColor => backgroundColor;

  @override
  Future<void> setMangaTranslationBackgroundColor(Color value) async {
    backgroundColor = value;
  }
}

void main() {
  testWidgets('shows saved appearance and updates size and opacity', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final prefs = _AppearancePrefs();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MangaTranslationAppearanceSheet(prefs: prefs)),
      ),
    );

    expect(find.text('Translation preview'), findsNWidgets(2));
    expect(
      tester
          .widget<Slider>(
            find.byKey(const ValueKey('manga-translation-appearance-size')),
          )
          .value,
      20,
    );
    expect(
      tester
          .widget<Slider>(
            find.byKey(const ValueKey('manga-translation-appearance-opacity')),
          )
          .value,
      0.4,
    );

    await tester.drag(
      find.byKey(const ValueKey('manga-translation-appearance-size')),
      const Offset(80, 0),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final opacitySlider = find.byKey(
      const ValueKey('manga-translation-appearance-opacity'),
    );
    tester.widget<Slider>(opacitySlider).onChanged!(0.7);
    await tester.pump();
    tester.widget<Slider>(opacitySlider).onChangeEnd!(0.7);

    expect(prefs.mangaTranslationFontSize, isNot(20));
    expect(prefs.mangaTranslationBackgroundOpacity, isNot(0.4));
  });

  testWidgets('opens custom color pickers for translated text and background', (
    tester,
  ) async {
    final prefs = _AppearancePrefs();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MangaTranslationAppearanceSheet(prefs: prefs)),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('manga-translation-appearance-text-color')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Custom colour'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('manga-translation-appearance-background-color'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Custom colour'), findsOneWidget);
  });
}
