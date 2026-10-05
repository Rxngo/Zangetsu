import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Compact floating control for chapter-wide manga translation.
///
/// The reader owns translation state and actions; this widget only presents
/// them and fades slightly while the reader leaves it untouched.
class MangaTranslationFloatingControl extends StatefulWidget {
  const MangaTranslationFloatingControl({
    super.key,
    required this.label,
    required this.stopLabel,
    required this.showTranslations,
    required this.showOriginalLabel,
    required this.showTranslationsLabel,
    required this.active,
    required this.running,
    required this.stopRequested,
    required this.onTap,
    required this.onToggleVisibility,
    required this.onStop,
  });

  final String label;
  final String stopLabel;
  final bool showTranslations;
  final String showOriginalLabel;
  final String showTranslationsLabel;
  final bool active;
  final bool running;
  final bool stopRequested;
  final VoidCallback onTap;
  final VoidCallback onToggleVisibility;
  final VoidCallback onStop;

  @override
  State<MangaTranslationFloatingControl> createState() =>
      _MangaTranslationFloatingControlState();
}

class _MangaTranslationFloatingControlState
    extends State<MangaTranslationFloatingControl> {
  static const _idleDelay = Duration(seconds: 3);
  static const _fadeDuration = Duration(milliseconds: 220);
  static const _inactiveSurface = Color(0xFF15151B);

  Timer? _idleTimer;
  bool _dimmed = false;

  @override
  void initState() {
    super.initState();
    _scheduleFade();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  void _scheduleFade() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleDelay, () {
      if (!mounted) return;
      setState(() => _dimmed = true);
    });
  }

  void _wake() {
    if (_dimmed) setState(() => _dimmed = false);
    _scheduleFade();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      key: const ValueKey('manga-translation-control-opacity'),
      opacity: _dimmed ? 0.5 : 1,
      duration: _fadeDuration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: widget.label,
            child: Semantics(
              button: !widget.running,
              label: widget.label,
              liveRegion: widget.running,
              child: Material(
                key: const ValueKey(
                  'manga-translation-floating-control-surface',
                ),
                color: widget.active ? AppColors.accent : _inactiveSurface,
                elevation: 3,
                shape: CircleBorder(
                  side: BorderSide(
                    color: widget.active
                        ? Colors.transparent
                        : const Color(0x1AFFFFFF),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTapDown: (_) => _wake(),
                  onTap: widget.running
                      ? null
                      : () {
                          _wake();
                          widget.onTap();
                        },
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: widget.running
                            ? const SizedBox(
                                key: ValueKey('manga-translation-progress'),
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.translate_rounded,
                                key: ValueKey('manga-translation-icon'),
                                size: 21,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.running) ...[
            const SizedBox(width: 4),
            Material(
              color: _inactiveSurface,
              shape: const CircleBorder(
                side: BorderSide(color: Color(0x1AFFFFFF)),
              ),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                key: const ValueKey('manga-translation-visibility-toggle'),
                tooltip: widget.showTranslations
                    ? widget.showOriginalLabel
                    : widget.showTranslationsLabel,
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
                padding: EdgeInsets.zero,
                onPressed: () {
                  _wake();
                  widget.onToggleVisibility();
                },
                icon: Icon(
                  widget.showTranslations
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 19,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Material(
              color: _inactiveSurface,
              shape: const CircleBorder(
                side: BorderSide(color: Color(0x1AFFFFFF)),
              ),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                key: const ValueKey('manga-translation-stop'),
                tooltip: widget.stopLabel,
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
                padding: EdgeInsets.zero,
                onPressed: widget.stopRequested
                    ? null
                    : () {
                        _wake();
                        widget.onStop();
                      },
                icon: const Icon(
                  Icons.stop_rounded,
                  size: 19,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
