import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/reading/manga_translation/manga_page_translation_models.dart';
import 'package:watch_app/core/reading/manga_translation/manga_translation_languages.dart';
import 'package:watch_app/features/reader/manga_page_translation_settings_sheet.dart';
import 'package:watch_app/l10n/app_localizations.dart';

const _japanese = MangaTranslationLanguage(
  code: 'ja',
  englishName: 'Japanese',
  script: 'Jpan',
);
const _english = MangaTranslationLanguage(
  code: 'en',
  englishName: 'English',
  script: 'Latn',
);
const _french = MangaTranslationLanguage(
  code: 'fr',
  englishName: 'French',
  script: 'Latn',
);
const _hindi = MangaTranslationLanguage(
  code: 'hi',
  englishName: 'Hindi',
  script: 'Deva',
);

typedef _Selection = (
  String,
  String,
  MangaTranslationEngine,
  MangaOnlineTranslationProvider,
);

Future<void> _pumpSheet(
  WidgetTester tester, {
  String sourceLanguage = 'ja',
  String targetLanguage = 'en',
  MangaTranslationEngine initialEngine = MangaTranslationEngine.online,
  MangaOnlineTranslationProvider initialProvider =
      MangaOnlineTranslationProvider.google,
  bool geminiKeyConfigured = false,
  bool groqKeyConfigured = false,
  List<MangaTranslationLanguage> sourceLanguages = const [
    _japanese,
    _english,
    _french,
    _hindi,
  ],
  List<MangaTranslationLanguage> onlineTargetLanguages = const [
    _english,
    _french,
    _hindi,
  ],
  List<MangaTranslationLanguage> offlineTargetLanguages = const [],
  bool settingsOnly = false,
  required MangaPageTranslationSelectionChanged onSelectionChanged,
  required MangaPageTranslationCallback onTranslate,
  MangaTranslationProviderKeyCheck? onCheckProviderKey,
  MangaTranslationProviderKeySave? onSaveProviderKey,
  MangaTranslationProviderKeyDelete? onDeleteProviderKey,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MangaPageTranslationSettingsSheet(
          sourceLanguages: sourceLanguages,
          onlineTargetLanguages: onlineTargetLanguages,
          offlineTargetLanguages: offlineTargetLanguages,
          initialSourceLanguage: sourceLanguage,
          initialTargetLanguage: targetLanguage,
          initialEngine: initialEngine,
          initialProvider: initialProvider,
          settingsOnly: settingsOnly,
          onSelectionChanged: onSelectionChanged,
          onTranslate: onTranslate,
          onCheckProviderKey:
              onCheckProviderKey ??
              (provider) async {
                return switch (provider) {
                  MangaOnlineTranslationProvider.gemini => geminiKeyConfigured,
                  MangaOnlineTranslationProvider.groq => groqKeyConfigured,
                  MangaOnlineTranslationProvider.google => false,
                };
              },
          onSaveProviderKey: onSaveProviderKey ?? (_, _) async {},
          onDeleteProviderKey: onDeleteProviderKey ?? (_) async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('MangaPageTranslationSettingsSheet', () {
    testWidgets('does not translate or persist the initial selection', (
      tester,
    ) async {
      var translateCalls = 0;
      final changes = <_Selection>[];

      await _pumpSheet(
        tester,
        onSelectionChanged: (source, target, engine, provider) {
          changes.add((source, target, engine, provider));
        },
        onTranslate: (source, target, engine, provider) async {
          translateCalls++;
          return null;
        },
      );

      expect(translateCalls, 0);
      expect(changes, isEmpty);
    });

    testWidgets(
      'settings-only mode keeps controls but hides translate action',
      (tester) async {
        var translateCalls = 0;
        await _pumpSheet(
          tester,
          settingsOnly: true,
          onSelectionChanged: (_, _, _, _) {},
          onTranslate: (_, _, _, _) async {
            translateCalls++;
            return null;
          },
        );

        expect(
          find.byKey(const ValueKey('manga-translation-source')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('manga-translation-target')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('manga-translation-submit')),
          findsNothing,
        );
        expect(translateCalls, 0);
      },
    );

    testWidgets('offers only online engine when offline targets are absent', (
      tester,
    ) async {
      await _pumpSheet(
        tester,
        onSelectionChanged: (_, _, _, _) {},
        onTranslate: (_, _, _, _) async => null,
      );

      expect(find.text('Online'), findsNothing);
      expect(find.text('Offline'), findsNothing);
    });

    testWidgets('loads a provider key only when that provider is selected', (
      tester,
    ) async {
      final checkedProviders = <MangaOnlineTranslationProvider>[];
      await _pumpSheet(
        tester,
        onSelectionChanged: (_, _, _, _) {},
        onTranslate: (_, _, _, _) async => null,
        onCheckProviderKey: (provider) async {
          checkedProviders.add(provider);
          return false;
        },
      );

      expect(checkedProviders, isEmpty);
      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();

      expect(checkedProviders, [MangaOnlineTranslationProvider.gemini]);
      expect(find.text('Add API key'), findsOneWidget);
    });

    testWidgets('selecting Gemini requires and securely saves an API key', (
      tester,
    ) async {
      final changes = <_Selection>[];
      String? savedKey;
      await _pumpSheet(
        tester,
        onSelectionChanged: (source, target, engine, provider) {
          changes.add((source, target, engine, provider));
        },
        onTranslate: (_, _, _, _) async => null,
        onSaveProviderKey: (provider, key) async {
          expect(provider, MangaOnlineTranslationProvider.gemini);
          savedKey = key;
        },
      );

      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();

      expect(changes, [
        (
          'ja',
          'en',
          MangaTranslationEngine.online,
          MangaOnlineTranslationProvider.gemini,
        ),
      ]);
      expect(find.text('Add API key'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('manga-translation-submit')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(
        find.byKey(const ValueKey('manga-translation-api-key-action')),
      );
      await tester.pumpAndSettle();
      final keyField = tester.widget<TextField>(
        find.byKey(const ValueKey('manga-translation-api-key-input')),
      );
      expect(keyField.obscureText, isTrue);
      await tester.enterText(
        find.byKey(const ValueKey('manga-translation-api-key-input')),
        'user-secret',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('manga-translation-api-key-save')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(
        find.byKey(const ValueKey('manga-translation-api-key-save')),
      );
      await tester.pumpAndSettle();

      expect(savedKey, 'user-secret');
      expect(find.text('API key saved securely'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('manga-translation-submit')),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('removing the selected provider key disables translation', (
      tester,
    ) async {
      var removedProvider = MangaOnlineTranslationProvider.google;
      await _pumpSheet(
        tester,
        initialProvider: MangaOnlineTranslationProvider.groq,
        groqKeyConfigured: true,
        onSelectionChanged: (_, _, _, _) {},
        onTranslate: (_, _, _, _) async => null,
        onDeleteProviderKey: (provider) async => removedProvider = provider,
      );

      expect(find.text('Remove API key'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('manga-translation-api-key-remove')),
      );
      await tester.pumpAndSettle();

      expect(removedProvider, MangaOnlineTranslationProvider.groq);
      expect(find.text('Add API key'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('manga-translation-submit')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('changing engine persists a valid target selection', (
      tester,
    ) async {
      final changes = <_Selection>[];
      await _pumpSheet(
        tester,
        sourceLanguage: 'fr',
        offlineTargetLanguages: const [_english, _french],
        onSelectionChanged: (source, target, engine, provider) {
          changes.add((source, target, engine, provider));
        },
        onTranslate: (_, _, _, _) async => null,
      );

      await tester.tap(find.text('Offline'));
      await tester.pumpAndSettle();

      expect(changes, [
        (
          'fr',
          'en',
          MangaTranslationEngine.offline,
          MangaOnlineTranslationProvider.google,
        ),
      ]);
    });

    testWidgets('switching offline repairs an unsupported source first', (
      tester,
    ) async {
      final changes = <_Selection>[];
      await _pumpSheet(
        tester,
        sourceLanguage: 'ja',
        offlineTargetLanguages: const [_english, _french],
        onSelectionChanged: (source, target, engine, provider) {
          changes.add((source, target, engine, provider));
        },
        onTranslate: (_, _, _, _) async => null,
      );

      await tester.tap(find.text('Offline'));
      await tester.pumpAndSettle();

      expect(changes, [
        (
          'en',
          'fr',
          MangaTranslationEngine.offline,
          MangaOnlineTranslationProvider.google,
        ),
      ]);

      await tester.tap(find.byKey(const ValueKey('manga-translation-source')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('manga-language-ja')), findsNothing);
      expect(find.byKey(const ValueKey('manga-language-en')), findsOneWidget);
    });

    testWidgets('searches the source language catalog and persists a choice', (
      tester,
    ) async {
      final changes = <_Selection>[];
      var translateCalls = 0;
      await _pumpSheet(
        tester,
        onSelectionChanged: (source, target, engine, provider) {
          changes.add((source, target, engine, provider));
        },
        onTranslate: (_, _, _, _) async {
          translateCalls++;
          return null;
        },
      );

      await tester.tap(find.byKey(const ValueKey('manga-translation-source')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('manga-translation-language-search')),
        'hin',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('manga-language-hi')), findsOneWidget);
      expect(find.byKey(const ValueKey('manga-language-ja')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('manga-language-hi')));
      await tester.pumpAndSettle();

      expect(changes, [
        (
          'hi',
          'en',
          MangaTranslationEngine.online,
          MangaOnlineTranslationProvider.google,
        ),
      ]);
      expect(translateCalls, 0);
    });

    testWidgets('translates only on tap and shows loading then success', (
      tester,
    ) async {
      final completer = Completer<MangaPageTranslationResult?>();
      final calls = <_Selection>[];
      await _pumpSheet(
        tester,
        onSelectionChanged: (_, _, _, _) {},
        onTranslate: (source, target, engine, provider) {
          calls.add((source, target, engine, provider));
          return completer.future;
        },
      );

      expect(calls, isEmpty);
      await tester.tap(find.byKey(const ValueKey('manga-translation-submit')));
      await tester.pump();

      expect(calls, [
        (
          'ja',
          'en',
          MangaTranslationEngine.online,
          MangaOnlineTranslationProvider.google,
        ),
      ]);
      expect(find.text('Translating…'), findsOneWidget);

      completer.complete(
        MangaPageTranslationResult(
          imageWidth: 100,
          imageHeight: 100,
          regions: const [],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Translation ready'), findsOneWidget);
    });

    testWidgets('locks language and engine choices while translating', (
      tester,
    ) async {
      final completer = Completer<MangaPageTranslationResult?>();
      final changes = <_Selection>[];
      await _pumpSheet(
        tester,
        offlineTargetLanguages: const [_english, _french],
        onSelectionChanged: (source, target, engine, provider) {
          changes.add((source, target, engine, provider));
        },
        onTranslate: (_, _, _, _) => completer.future,
      );

      await tester.tap(find.byKey(const ValueKey('manga-translation-submit')));
      await tester.pump();

      final sourceTapTarget = find.descendant(
        of: find.byKey(const ValueKey('manga-translation-source')),
        matching: find.byType(InkWell),
      );
      final offlineTapTarget = find.ancestor(
        of: find.text('Offline'),
        matching: find.byType(InkWell),
      );
      expect(sourceTapTarget, findsNothing);
      expect(tester.widget<InkWell>(offlineTapTarget).onTap, isNull);

      await tester.tap(find.text('Offline'));
      await tester.pump();
      expect(changes, isEmpty);
      expect(find.text('Translating…'), findsOneWidget);

      completer.complete(null);
      await tester.pumpAndSettle();
    });

    testWidgets('shows an error when translation fails', (tester) async {
      await _pumpSheet(
        tester,
        onSelectionChanged: (_, _, _, _) {},
        onTranslate: (_, _, _, _) async =>
            throw StateError('network unavailable'),
      );

      await tester.tap(find.byKey(const ValueKey('manga-translation-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Translation failed'), findsOneWidget);
    });
  });
}
