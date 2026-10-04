import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/reading/manga_translation/manga_page_translation_models.dart';
import 'package:watch_app/core/reading/manga_translation/manga_page_translation_overlay.dart';

void main() {
  group('mapMangaNormalizedBounds', () {
    test('maps contain bounds into the centered displayed image rect', () {
      final mapped = mapMangaNormalizedBounds(
        normalizedBounds: const Rect.fromLTRB(0.25, 0.2, 0.75, 0.8),
        imageSize: const Size(200, 100),
        outputRect: const Rect.fromLTWH(10, 20, 100, 100),
      );

      expect(mapped, const Rect.fromLTRB(35, 55, 85, 85));
    });

    test('maps and clips fitWidth regions crossing the source crop', () {
      final mapped = mapMangaNormalizedBounds(
        normalizedBounds: const Rect.fromLTRB(0.2, 0.1, 0.8, 0.4),
        imageSize: const Size(100, 200),
        outputRect: const Rect.fromLTWH(0, 0, 100, 100),
        fit: BoxFit.fitWidth,
      );

      expect(mapped, const Rect.fromLTRB(20, 0, 80, 30));
    });

    test('keeps a smaller image at its natural size with scaleDown', () {
      final mapped = mapMangaNormalizedBounds(
        normalizedBounds: const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
        imageSize: const Size(50, 25),
        outputRect: const Rect.fromLTWH(10, 20, 100, 100),
        fit: BoxFit.scaleDown,
      );

      expect(mapped, const Rect.fromLTRB(45, 62.5, 75, 77.5));
    });

    test('keeps natural scale with none while clipping the source crop', () {
      final mapped = mapMangaNormalizedBounds(
        normalizedBounds: const Rect.fromLTRB(0.25, 0.2, 0.75, 0.8),
        imageSize: const Size(200, 100),
        outputRect: const Rect.fromLTWH(0, 0, 100, 100),
        fit: BoxFit.none,
      );

      expect(mapped, const Rect.fromLTRB(0, 20, 100, 80));
    });

    test('maps fitHeight into the centered displayed image rect', () {
      final mapped = mapMangaNormalizedBounds(
        normalizedBounds: const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
        imageSize: const Size(100, 200),
        outputRect: const Rect.fromLTWH(10, 20, 100, 100),
        fit: BoxFit.fitHeight,
      );

      expect(mapped, const Rect.fromLTRB(45, 40, 75, 100));
    });

    test(
      'maps cover regions through the centered crop and clips to output',
      () {
        final mapped = mapMangaNormalizedBounds(
          normalizedBounds: const Rect.fromLTRB(0.1, 0.1, 0.4, 0.2),
          imageSize: const Size(200, 100),
          outputRect: const Rect.fromLTWH(0, 0, 100, 100),
          fit: BoxFit.cover,
        );

        expect(mapped, const Rect.fromLTRB(0, 10, 30, 20));
      },
    );

    test('uses the configured alignment for a cover crop', () {
      final mapped = mapMangaNormalizedBounds(
        normalizedBounds: const Rect.fromLTRB(0.1, 0.1, 0.2, 0.2),
        imageSize: const Size(200, 100),
        outputRect: const Rect.fromLTWH(0, 0, 100, 100),
        fit: BoxFit.cover,
        alignment: Alignment.topLeft,
      );

      expect(mapped, const Rect.fromLTRB(20, 10, 40, 20));
    });

    test('returns null when cover crop hides a region entirely', () {
      final mapped = mapMangaNormalizedBounds(
        normalizedBounds: const Rect.fromLTRB(0.05, 0.1, 0.2, 0.2),
        imageSize: const Size(200, 100),
        outputRect: const Rect.fromLTWH(0, 0, 100, 100),
        fit: BoxFit.cover,
      );

      expect(mapped, isNull);
    });

    test('returns null for bounds with zero width or height', () {
      for (final bounds in <Rect>[
        const Rect.fromLTRB(0.5, 0.2, 0.5, 0.8),
        const Rect.fromLTRB(0.2, 0.5, 0.8, 0.5),
      ]) {
        expect(
          mapMangaNormalizedBounds(
            normalizedBounds: bounds,
            imageSize: const Size(100, 100),
            outputRect: const Rect.fromLTWH(0, 0, 100, 100),
          ),
          isNull,
        );
      }
    });

    test('returns null for zero-sized output rects', () {
      final mapped = mapMangaNormalizedBounds(
        normalizedBounds: const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
        imageSize: const Size(100, 100),
        outputRect: const Rect.fromLTWH(0, 0, 0, 100),
      );

      expect(mapped, isNull);
    });

    test('returns null for invalid image dimensions', () {
      for (final imageSize in <Size>[
        Size.zero,
        const Size(-1, 100),
        const Size(100, double.infinity),
      ]) {
        expect(
          mapMangaNormalizedBounds(
            normalizedBounds: const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
            imageSize: imageSize,
            outputRect: const Rect.fromLTWH(0, 0, 100, 100),
          ),
          isNull,
        );
      }
    });
  });

  group('MangaPageTranslationOverlay', () {
    final result = MangaPageTranslationResult(
      imageWidth: 100,
      imageHeight: 100,
      regions: [
        MangaTranslatedRegion(
          originalText: 'こんにちは',
          translatedText: 'Hello there',
          normalizedBounds: const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
        ),
      ],
    );

    testWidgets('renders translated text with an accessible label', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              height: 120,
              child: MangaPageTranslationOverlay(result: result),
            ),
          ),
        ),
      );

      expect(find.text('Hello there'), findsOneWidget);
      expect(find.bySemanticsLabel('Hello there'), findsOneWidget);
    });

    testWidgets('does not intercept page taps', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => tapped = true,
                      child: const ColoredBox(color: Colors.transparent),
                    ),
                  ),
                  MangaPageTranslationOverlay(result: result),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tapAt(const Offset(60, 60));

      expect(tapped, isTrue);
    });

    testWidgets('keeps the full semantic label at large text scale', (
      tester,
    ) async {
      const translatedText =
          'This is the full translation announced to the reader';
      final largeTextResult = MangaPageTranslationResult(
        imageWidth: 100,
        imageHeight: 100,
        regions: [
          MangaTranslatedRegion(
            originalText: '原文',
            translatedText: translatedText,
            normalizedBounds: const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(4)),
            child: Scaffold(
              body: SizedBox(
                width: 120,
                height: 120,
                child: MangaPageTranslationOverlay(result: largeTextResult),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel(translatedText), findsOneWidget);
    });
  });
}
