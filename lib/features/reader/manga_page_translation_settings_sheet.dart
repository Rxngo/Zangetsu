import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/reading/manga_translation/manga_page_translation_models.dart';
import '../../core/reading/manga_translation/manga_online_translation_service.dart';
import '../../core/reading/manga_translation/manga_translation_platform.dart';
import '../../core/reading/manga_translation/manga_translation_languages.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../l10n/l10n.dart';
import 'reader_chrome.dart';

/// Persists a changed manga page translation selection.
typedef MangaPageTranslationSelectionChanged =
    void Function(
      String sourceLanguage,
      String targetLanguage,
      MangaTranslationEngine engine,
      MangaOnlineTranslationProvider provider,
    );

/// Starts translation for the chapter containing the visible page.
typedef MangaPageTranslationCallback =
    Future<MangaPageTranslationResult?> Function(
      String sourceLanguage,
      String targetLanguage,
      MangaTranslationEngine engine,
      MangaOnlineTranslationProvider provider,
    );

typedef MangaTranslationProviderKeySave =
    Future<void> Function(MangaOnlineTranslationProvider provider, String key);

typedef MangaTranslationProviderKeyDelete =
    Future<void> Function(MangaOnlineTranslationProvider provider);
typedef MangaTranslationProviderKeyCheck =
    Future<bool> Function(MangaOnlineTranslationProvider provider);

/// Reader-styled controls for choosing languages and explicitly translating
/// the current chapter. The parent owns model status and setup behavior.
class MangaPageTranslationSettingsSheet extends StatefulWidget {
  const MangaPageTranslationSettingsSheet({
    super.key,
    required this.sourceLanguages,
    required this.onlineTargetLanguages,
    this.offlineTargetLanguages = const [],
    required this.initialSourceLanguage,
    required this.initialTargetLanguage,
    required this.initialEngine,
    this.initialProvider = MangaOnlineTranslationProvider.google,
    required this.onSelectionChanged,
    this.onTranslate,
    required this.onCheckProviderKey,
    required this.onSaveProviderKey,
    required this.onDeleteProviderKey,
    this.settingsOnly = false,
    this.closeOnSuccess = false,
  }) : assert(settingsOnly || onTranslate != null);

  /// Languages supported by OCR as source languages.
  final List<MangaTranslationLanguage> sourceLanguages;

  /// Target languages supported by the online engine.
  final List<MangaTranslationLanguage> onlineTargetLanguages;

  /// Target languages supported by the offline engine. An empty list hides
  /// the offline engine option, which keeps unsupported platforms online only.
  final List<MangaTranslationLanguage> offlineTargetLanguages;

  final String initialSourceLanguage;
  final String initialTargetLanguage;
  final MangaTranslationEngine initialEngine;
  final MangaOnlineTranslationProvider initialProvider;
  final MangaPageTranslationSelectionChanged onSelectionChanged;
  final MangaPageTranslationCallback? onTranslate;
  final MangaTranslationProviderKeyCheck onCheckProviderKey;
  final MangaTranslationProviderKeySave onSaveProviderKey;
  final MangaTranslationProviderKeyDelete onDeleteProviderKey;

  /// Hides the chapter action when this sheet is used to edit app-wide
  /// preferences. Translation remains an explicit reader-only operation.
  final bool settingsOnly;

  /// Closes the controls after the chapter job's first page finishes. The
  /// standalone default keeps the completion state visible without a page
  /// behind it.
  final bool closeOnSuccess;

  @override
  State<MangaPageTranslationSettingsSheet> createState() =>
      _MangaPageTranslationSettingsSheetState();
}

class _MangaPageTranslationSettingsSheetState
    extends State<MangaPageTranslationSettingsSheet> {
  late String _sourceLanguage;
  late String _targetLanguage;
  late MangaTranslationEngine _engine;
  late MangaOnlineTranslationProvider _provider;
  final Map<MangaOnlineTranslationProvider, bool> _providerKeysConfigured = {
    MangaOnlineTranslationProvider.gemini: false,
    MangaOnlineTranslationProvider.groq: false,
  };
  final Set<MangaOnlineTranslationProvider> _providerKeyStatusKnown = {};
  final Set<MangaOnlineTranslationProvider> _providerKeyStatusLoading = {};

  bool _isTranslating = false;
  bool _isUpdatingKey = false;
  bool _hasTranslation = false;
  String? _errorMessage;
  String? _keySavedMessage;

  List<MangaTranslationLanguage> get _allSourceOptions =>
      _uniqueLanguages(widget.sourceLanguages);

  List<MangaTranslationLanguage> get _offlineSourceOptions {
    final offlineCodes = _offlineTargets
        .map((language) => language.code)
        .toSet();
    return _allSourceOptions
        .where((language) => offlineCodes.contains(language.code))
        .toList(growable: false);
  }

  List<MangaTranslationLanguage> get _sourceOptions => _sourcesFor(_engine);

  List<MangaTranslationLanguage> get _onlineTargets =>
      _uniqueLanguages(widget.onlineTargetLanguages);

  List<MangaTranslationLanguage> get _offlineTargets =>
      _uniqueLanguages(widget.offlineTargetLanguages);

  bool get _offlineAvailable => _offlineTargets.any(
    (target) =>
        _offlineSourceOptions.any((source) => source.code != target.code),
  );

  List<MangaTranslationLanguage> get _availableTargets {
    final options = switch (_engine) {
      MangaTranslationEngine.online => _onlineTargets,
      MangaTranslationEngine.offline => _offlineTargets,
    };
    return options
        .where((language) => language.code != _sourceLanguage)
        .toList(growable: false);
  }

  MangaTranslationLanguage? get _selectedSource =>
      _findLanguage(_sourceOptions, _sourceLanguage);

  MangaTranslationLanguage? get _selectedTarget =>
      _findLanguage(_availableTargets, _targetLanguage);

  bool get _providerKeyConfigured =>
      _provider == MangaOnlineTranslationProvider.google ||
      (_providerKeysConfigured[_provider] ?? false);
  bool get _isLoadingProviderKey =>
      _providerKeyStatusLoading.contains(_provider);

  bool get _canTranslate =>
      !widget.settingsOnly &&
      widget.onTranslate != null &&
      !_isTranslating &&
      !_isUpdatingKey &&
      _selectedSource != null &&
      _selectedTarget != null &&
      (_engine == MangaTranslationEngine.offline || _providerKeyConfigured);

  @override
  void initState() {
    super.initState();
    _resetSelection(
      sourceLanguage: widget.initialSourceLanguage,
      targetLanguage: widget.initialTargetLanguage,
      engine: widget.initialEngine,
      provider: widget.initialProvider,
    );
    unawaited(_loadProviderKeyStatus(_provider));
  }

  Future<void> _loadProviderKeyStatus(
    MangaOnlineTranslationProvider provider,
  ) async {
    if (provider == MangaOnlineTranslationProvider.google ||
        _providerKeyStatusKnown.contains(provider) ||
        !_providerKeyStatusLoading.add(provider)) {
      return;
    }
    if (mounted && provider == _provider) setState(() {});
    try {
      final configured = await widget.onCheckProviderKey(provider);
      if (!mounted) return;
      setState(() {
        _providerKeysConfigured[provider] = configured;
        _providerKeyStatusKnown.add(provider);
        _providerKeyStatusLoading.remove(provider);
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _providerKeysConfigured[provider] = false;
        _providerKeyStatusKnown.add(provider);
        _providerKeyStatusLoading.remove(provider);
      });
    }
  }

  @override
  void didUpdateWidget(covariant MangaPageTranslationSettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceLanguages != widget.sourceLanguages ||
        oldWidget.onlineTargetLanguages != widget.onlineTargetLanguages ||
        oldWidget.offlineTargetLanguages != widget.offlineTargetLanguages) {
      _resetSelection(
        sourceLanguage: _sourceLanguage,
        targetLanguage: _targetLanguage,
        engine: _engine,
        provider: _provider,
      );
      _clearResult();
    }
  }

  void _resetSelection({
    required String sourceLanguage,
    required String targetLanguage,
    required MangaTranslationEngine engine,
    required MangaOnlineTranslationProvider provider,
  }) {
    _engine = engine == MangaTranslationEngine.offline && !_offlineAvailable
        ? MangaTranslationEngine.online
        : engine;

    final sourceOptions = _sourcesFor(_engine);
    final selectedSource = _findLanguage(sourceOptions, sourceLanguage);
    _sourceLanguage =
        selectedSource?.code ?? sourceOptions.firstOrNull?.code ?? '';

    final targetOptions = switch (_engine) {
      MangaTranslationEngine.online => _uniqueLanguages(
        widget.onlineTargetLanguages,
      ),
      MangaTranslationEngine.offline => _uniqueLanguages(
        widget.offlineTargetLanguages,
      ),
    }.where((language) => language.code != _sourceLanguage).toList();
    _targetLanguage =
        _findLanguage(targetOptions, targetLanguage)?.code ??
        targetOptions.firstOrNull?.code ??
        '';
    _provider = provider;
  }

  void _setSourceLanguage(String language) {
    if (_isTranslating || language == _sourceLanguage) return;
    final nextTargets = _targetsFor(_engine, sourceLanguage: language);
    final target =
        _findLanguage(nextTargets, _targetLanguage)?.code ??
        nextTargets.firstOrNull?.code ??
        '';
    _commitSelection(language, target, _engine, _provider);
  }

  void _setTargetLanguage(String language) {
    if (_isTranslating || language == _targetLanguage) return;
    _commitSelection(_sourceLanguage, language, _engine, _provider);
  }

  void _setEngine(MangaTranslationEngine engine) {
    if (_isTranslating ||
        engine == _engine ||
        (engine == MangaTranslationEngine.offline && !_offlineAvailable)) {
      return;
    }
    final nextSources = _sourcesFor(engine);
    final source =
        _findLanguage(nextSources, _sourceLanguage)?.code ??
        nextSources.firstOrNull?.code ??
        '';
    final nextTargets = _targetsFor(engine, sourceLanguage: source);
    final target =
        _findLanguage(nextTargets, _targetLanguage)?.code ??
        nextTargets.firstOrNull?.code ??
        '';
    _commitSelection(source, target, engine, _provider);
  }

  void _setProvider(MangaOnlineTranslationProvider provider) {
    if (_isTranslating || provider == _provider) return;
    _commitSelection(_sourceLanguage, _targetLanguage, _engine, provider);
    unawaited(_loadProviderKeyStatus(provider));
  }

  List<MangaTranslationLanguage> _sourcesFor(MangaTranslationEngine engine) {
    return switch (engine) {
      MangaTranslationEngine.online => _allSourceOptions,
      MangaTranslationEngine.offline => _offlineSourceOptions,
    };
  }

  List<MangaTranslationLanguage> _targetsFor(
    MangaTranslationEngine engine, {
    required String sourceLanguage,
  }) {
    final options = switch (engine) {
      MangaTranslationEngine.online => _onlineTargets,
      MangaTranslationEngine.offline => _offlineTargets,
    };
    return options
        .where((language) => language.code != sourceLanguage)
        .toList(growable: false);
  }

  void _commitSelection(
    String sourceLanguage,
    String targetLanguage,
    MangaTranslationEngine engine,
    MangaOnlineTranslationProvider provider,
  ) {
    final changed =
        sourceLanguage != _sourceLanguage ||
        targetLanguage != _targetLanguage ||
        engine != _engine ||
        provider != _provider;
    if (!changed) return;
    setState(() {
      _sourceLanguage = sourceLanguage;
      _targetLanguage = targetLanguage;
      _engine = engine;
      _provider = provider;
      _clearResult();
    });
    widget.onSelectionChanged(sourceLanguage, targetLanguage, engine, provider);
  }

  void _clearResult() {
    _isTranslating = false;
    _hasTranslation = false;
    _errorMessage = null;
    _keySavedMessage = null;
  }

  Future<void> _editProviderKey() async {
    if (_provider == MangaOnlineTranslationProvider.google ||
        _isTranslating ||
        _isUpdatingKey) {
      return;
    }
    final key = await showDialog<String>(
      context: context,
      builder: (_) => const _MangaTranslationApiKeyDialog(),
    );
    if (!mounted || key == null || key.isEmpty) return;

    setState(() {
      _isUpdatingKey = true;
      _keySavedMessage = null;
      _errorMessage = null;
    });
    try {
      await widget.onSaveProviderKey(_provider, key);
      if (!mounted) return;
      setState(() {
        _providerKeysConfigured[_provider] = true;
        _isUpdatingKey = false;
        _keySavedMessage = context.l10n.mangaTranslationApiKeySaved;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isUpdatingKey = false;
        _errorMessage = context.l10n.mangaTranslationApiKeySaveFailed;
      });
    }
  }

  Future<void> _removeProviderKey() async {
    if (_provider == MangaOnlineTranslationProvider.google ||
        _isTranslating ||
        _isUpdatingKey) {
      return;
    }
    setState(() {
      _isUpdatingKey = true;
      _keySavedMessage = null;
      _errorMessage = null;
    });
    try {
      await widget.onDeleteProviderKey(_provider);
      if (!mounted) return;
      setState(() {
        _providerKeysConfigured[_provider] = false;
        _isUpdatingKey = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isUpdatingKey = false;
        _errorMessage = context.l10n.mangaTranslationApiKeySaveFailed;
      });
    }
  }

  Future<void> _openLanguagePicker({required bool source}) async {
    if (_isTranslating) return;
    final options = source ? _sourceOptions : _availableTargets;
    if (options.isEmpty) return;
    final selected = await showModalBottomSheet<MangaTranslationLanguage>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _MangaTranslationLanguagePicker(
        languages: options,
        title: source
            ? context.l10n.mangaTranslationSourceLanguage
            : context.l10n.mangaTranslationTargetLanguage,
      ),
    );
    if (!mounted || selected == null) return;
    if (source) {
      _setSourceLanguage(selected.code);
    } else {
      _setTargetLanguage(selected.code);
    }
  }

  Future<void> _translatePage() async {
    final source = _selectedSource;
    final target = _selectedTarget;
    final onTranslate = widget.onTranslate;
    if (source == null ||
        target == null ||
        onTranslate == null ||
        _isTranslating) {
      return;
    }

    setState(() {
      _isTranslating = true;
      _hasTranslation = false;
      _errorMessage = null;
    });
    try {
      final result = await onTranslate(
        source.code,
        target.code,
        _engine,
        _provider,
      );
      if (!mounted) return;
      if (widget.closeOnSuccess && result != null) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _isTranslating = false;
        _hasTranslation =
            result != null &&
            (!widget.closeOnSuccess || result.regions.isNotEmpty);
        _errorMessage =
            result == null || (widget.closeOnSuccess && result.regions.isEmpty)
            ? context.l10n.mangaTranslationNoResult
            : null;
      });
    } on MangaTranslationPlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _isTranslating = false;
        _errorMessage = context.l10n.mangaTranslationError;
      });
      if (error.code == 'restart_required') {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.l10n.mangaTranslationRestartRequiredTitle),
            content: Text(context.l10n.mangaTranslationRestartRequiredMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.ok),
              ),
            ],
          ),
        );
      }
    } on MangaOnlineTranslationException catch (error) {
      if (!mounted) return;
      final l10n = context.l10n;
      setState(() {
        _isTranslating = false;
        _errorMessage = switch (error.failure) {
          MangaOnlineTranslationFailure.missingApiKey =>
            l10n.mangaTranslationApiKeyMissing,
          MangaOnlineTranslationFailure.invalidApiKey =>
            l10n.mangaTranslationInvalidApiKey,
          MangaOnlineTranslationFailure.rateLimited =>
            l10n.mangaTranslationRateLimited,
          MangaOnlineTranslationFailure.invalidResponse =>
            l10n.mangaTranslationInvalidResponse,
          MangaOnlineTranslationFailure.unavailable =>
            l10n.mangaTranslationProviderError,
        };
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isTranslating = false;
        _errorMessage = context.l10n.mangaTranslationError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ReaderSheetShell(
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(l10n.mangaPageTranslationTitle, style: AppText.headline),
                  const SizedBox(height: 12),
                  readerSheetGroup([
                    KeyedSubtree(
                      key: const ValueKey('manga-translation-source'),
                      child: readerSheetRow(
                        icon: Icons.translate_rounded,
                        label: l10n.mangaTranslationSourceLanguage,
                        trailing: _languageLabel(_selectedSource, l10n),
                        onTap: _isTranslating
                            ? null
                            : () => _openLanguagePicker(source: true),
                      ),
                    ),
                    KeyedSubtree(
                      key: const ValueKey('manga-translation-target'),
                      child: readerSheetRow(
                        icon: Icons.g_translate_rounded,
                        label: l10n.mangaTranslationTargetLanguage,
                        trailing: _languageLabel(_selectedTarget, l10n),
                        onTap: _isTranslating || _availableTargets.isEmpty
                            ? null
                            : () => _openLanguagePicker(source: false),
                      ),
                    ),
                  ]),
                  if (_offlineAvailable) ...[
                    const SizedBox(height: 12),
                    readerSheetGroup([
                      readerSheetRow(
                        icon: Icons.hub_rounded,
                        label: l10n.mangaTranslationEngine,
                        child: ReaderSegmentedControl(
                          options: [
                            (
                              value: MangaTranslationEngine.online.name,
                              label: l10n.mangaTranslationOnline,
                            ),
                            (
                              value: MangaTranslationEngine.offline.name,
                              label: l10n.mangaTranslationOffline,
                            ),
                          ],
                          selected: _engine.name,
                          enabled: !_isTranslating,
                          onSelect: (value) => _setEngine(
                            value == MangaTranslationEngine.offline.name
                                ? MangaTranslationEngine.offline
                                : MangaTranslationEngine.online,
                          ),
                        ),
                      ),
                    ]),
                  ],
                  if (_engine == MangaTranslationEngine.online) ...[
                    const SizedBox(height: 12),
                    readerSheetGroup([
                      readerSheetRow(
                        icon: Icons.cloud_outlined,
                        label: l10n.mangaTranslationProvider,
                        child: ReaderSegmentedControl(
                          options: [
                            (
                              value: MangaOnlineTranslationProvider.google.name,
                              label: l10n.mangaTranslationGoogle,
                            ),
                            (
                              value: MangaOnlineTranslationProvider.gemini.name,
                              label: l10n.mangaTranslationGemini,
                            ),
                            (
                              value: MangaOnlineTranslationProvider.groq.name,
                              label: l10n.mangaTranslationGroq,
                            ),
                          ],
                          selected: _provider.name,
                          enabled: !_isTranslating && !_isUpdatingKey,
                          onSelect: (value) => _setProvider(
                            MangaOnlineTranslationProvider.values.firstWhere(
                              (provider) => provider.name == value,
                            ),
                          ),
                        ),
                      ),
                      if (_provider != MangaOnlineTranslationProvider.google)
                        readerSheetRow(
                          icon: Icons.key_rounded,
                          label: l10n.mangaTranslationApiKey,
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  key: const ValueKey(
                                    'manga-translation-api-key-action',
                                  ),
                                  onPressed:
                                      _isTranslating ||
                                          _isUpdatingKey ||
                                          _isLoadingProviderKey
                                      ? null
                                      : _editProviderKey,
                                  icon: Icon(
                                    _providerKeyConfigured
                                        ? Icons.edit_outlined
                                        : Icons.add_rounded,
                                  ),
                                  label: Text(
                                    _providerKeyConfigured
                                        ? l10n.mangaTranslationChangeApiKey
                                        : l10n.mangaTranslationAddApiKey,
                                  ),
                                ),
                              ),
                              if (_providerKeyConfigured) ...[
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  key: const ValueKey(
                                    'manga-translation-api-key-remove',
                                  ),
                                  onPressed:
                                      _isTranslating ||
                                          _isUpdatingKey ||
                                          _isLoadingProviderKey
                                      ? null
                                      : _removeProviderKey,
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                  ),
                                  label: Text(
                                    l10n.mangaTranslationRemoveApiKey,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      if (_provider != MangaOnlineTranslationProvider.google)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: Text(
                            l10n.mangaTranslationProviderBillingNote,
                            style: AppText.caption.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                    ]),
                  ],
                  if (_keySavedMessage != null) ...[
                    const SizedBox(height: 10),
                    _StatusMessage(
                      icon: Icons.check_circle_outline_rounded,
                      message: _keySavedMessage!,
                      color: Colors.greenAccent,
                    ),
                  ],
                  if (!widget.settingsOnly) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const ValueKey('manga-translation-submit'),
                      onPressed: _canTranslate ? _translatePage : null,
                      icon: _isTranslating
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.translate_rounded),
                      label: Text(
                        _isTranslating
                            ? l10n.mangaTranslationInProgress
                            : l10n.mangaTranslationAction,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                      ),
                    ),
                  ],
                  if (_errorMessage != null && !widget.settingsOnly) ...[
                    const SizedBox(height: 12),
                    _StatusMessage(
                      icon: Icons.error_outline_rounded,
                      message: _errorMessage!,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ] else if (_hasTranslation && !widget.settingsOnly) ...[
                    const SizedBox(height: 12),
                    _StatusMessage(
                      icon: Icons.check_circle_outline_rounded,
                      message: l10n.mangaTranslationSuccess,
                      color: Colors.greenAccent,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _languageLabel(
    MangaTranslationLanguage? language,
    AppLocalizations l10n,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          language?.englishName ?? l10n.mangaTranslationNoLanguages,
          style: AppText.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(width: 6),
        const Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: AppColors.textTertiary,
        ),
      ],
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.icon,
    required this.message,
    this.color = AppColors.textSecondary,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: AppText.caption.copyWith(color: color)),
        ),
      ],
    );
  }
}

class _MangaTranslationApiKeyDialog extends StatefulWidget {
  const _MangaTranslationApiKeyDialog();

  @override
  State<_MangaTranslationApiKeyDialog> createState() =>
      _MangaTranslationApiKeyDialogState();
}

class _MangaTranslationApiKeyDialogState
    extends State<_MangaTranslationApiKeyDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.mangaTranslationApiKeyTitle),
      content: TextField(
        key: const ValueKey('manga-translation-api-key-input'),
        controller: _controller,
        autofocus: true,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: l10n.mangaTranslationApiKey,
          hintText: l10n.mangaTranslationApiKeyHint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('manga-translation-api-key-save'),
          onPressed: () {
            final value = _controller.text.trim();
            if (value.isNotEmpty) Navigator.of(context).pop(value);
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class _MangaTranslationLanguagePicker extends StatefulWidget {
  const _MangaTranslationLanguagePicker({
    required this.languages,
    required this.title,
  });

  final List<MangaTranslationLanguage> languages;
  final String title;

  @override
  State<_MangaTranslationLanguagePicker> createState() =>
      _MangaTranslationLanguagePickerState();
}

class _MangaTranslationLanguagePickerState
    extends State<_MangaTranslationLanguagePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final query = _query.trim().toLowerCase();
    final matches = widget.languages
        .where((language) {
          return query.isEmpty ||
              language.englishName.toLowerCase().contains(query) ||
              language.code.toLowerCase().contains(query);
        })
        .toList(growable: false);

    return ReaderSheetShell(
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(widget.title, style: AppText.headline),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: TextField(
                  key: const ValueKey('manga-translation-language-search'),
                  autofocus: true,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: l10n.mangaTranslationSearchLanguages,
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: AppColors.surface2,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.hairline),
                    ),
                  ),
                ),
              ),
              if (matches.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      l10n.mangaTranslationNoLanguageMatch,
                      style: AppText.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final language = matches[index];
                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          key: ValueKey('manga-language-${language.code}'),
                          title: Text(language.englishName),
                          subtitle: Text(language.code),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textTertiary,
                          ),
                          onTap: () => Navigator.of(context).pop(language),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

List<MangaTranslationLanguage> _uniqueLanguages(
  Iterable<MangaTranslationLanguage> languages,
) {
  final byCode = <String, MangaTranslationLanguage>{};
  for (final language in languages) {
    final code = language.code.trim();
    if (code.isNotEmpty) byCode.putIfAbsent(code, () => language);
  }
  return byCode.values.toList(growable: false);
}

MangaTranslationLanguage? _findLanguage(
  Iterable<MangaTranslationLanguage> languages,
  String code,
) {
  for (final language in languages) {
    if (language.code == code) return language;
  }
  return null;
}
