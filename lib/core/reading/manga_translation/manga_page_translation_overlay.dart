import 'package:flutter/material.dart';

import 'manga_page_translation_models.dart';

/// Maps normalized image bounds into the visible portion of an output rect.
///
/// The mapping follows [fit] and [alignment], including source cropping for
/// cover-style fits. Returns `null` when the bounds are not visible or either
/// rect has no area.
Rect? mapMangaNormalizedBounds({
  required Rect normalizedBounds,
  required Size imageSize,
  required Rect outputRect,
  BoxFit fit = BoxFit.contain,
  Alignment alignment = Alignment.center,
}) {
  if (!isValidNormalizedBounds(normalizedBounds) ||
      !imageSize.width.isFinite ||
      !imageSize.height.isFinite ||
      imageSize.width <= 0 ||
      imageSize.height <= 0 ||
      !outputRect.left.isFinite ||
      !outputRect.top.isFinite ||
      !outputRect.right.isFinite ||
      !outputRect.bottom.isFinite ||
      outputRect.isEmpty) {
    return null;
  }

  final fitted = applyBoxFit(fit, imageSize, outputRect.size);
  if (fitted.source.isEmpty || fitted.destination.isEmpty) return null;

  final sourceRect = alignment.inscribe(fitted.source, Offset.zero & imageSize);
  final destinationRect = alignment.inscribe(fitted.destination, outputRect);
  final sourceBounds = Rect.fromLTRB(
    normalizedBounds.left * imageSize.width,
    normalizedBounds.top * imageSize.height,
    normalizedBounds.right * imageSize.width,
    normalizedBounds.bottom * imageSize.height,
  );
  final visibleSourceBounds = sourceBounds.intersect(sourceRect);
  if (visibleSourceBounds.isEmpty) return null;

  final scaleX = destinationRect.width / sourceRect.width;
  final scaleY = destinationRect.height / sourceRect.height;
  final mappedBounds = Rect.fromLTRB(
    destinationRect.left +
        (visibleSourceBounds.left - sourceRect.left) * scaleX,
    destinationRect.top + (visibleSourceBounds.top - sourceRect.top) * scaleY,
    destinationRect.left +
        (visibleSourceBounds.right - sourceRect.left) * scaleX,
    destinationRect.top +
        (visibleSourceBounds.bottom - sourceRect.top) * scaleY,
  );
  final clippedBounds = mappedBounds
      .intersect(destinationRect)
      .intersect(outputRect);
  return clippedBounds.isEmpty ? null : clippedBounds;
}

/// Displays translated page text over its source image without changing it.
///
/// Place this widget in the same layout, transform, and clipping wrappers as
/// the page image. It fills its bounded parent and ignores pointer events so
/// taps and gestures continue to reach the page beneath it.
class MangaPageTranslationOverlay extends StatelessWidget {
  /// Creates an overlay for an already translated page result.
  const MangaPageTranslationOverlay({
    super.key,
    required this.result,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.textStyle,
    this.backgroundColor = const Color(0xCC000000),
  });

  /// The page translation whose regions are shown.
  final MangaPageTranslationResult result;

  /// The image fitting behavior used to map regions into the parent.
  final BoxFit fit;

  /// The alignment used when fitting the source image into the parent.
  final Alignment alignment;

  /// An optional style for translated text.
  final TextStyle? textStyle;

  /// The translucent background behind each translated region.
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return const SizedBox.shrink();
        }

        final outputRect = Offset.zero & constraints.biggest;
        final resolvedTextStyle =
            textStyle ??
            Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ) ??
            const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            );
        final children = <Widget>[];

        for (final region in result.regions) {
          if (region.translatedText.trim().isEmpty) continue;
          final bounds = mapMangaNormalizedBounds(
            normalizedBounds: region.normalizedBounds,
            imageSize: Size(
              result.imageWidth.toDouble(),
              result.imageHeight.toDouble(),
            ),
            outputRect: outputRect,
            fit: fit,
            alignment: alignment,
          );
          if (bounds == null) continue;

          children.add(
            Positioned.fromRect(
              rect: bounds,
              child: Semantics(
                label: region.translatedText,
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 1,
                      ),
                      child: Center(
                        child: Text(
                          region.translatedText,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: resolvedTextStyle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return IgnorePointer(
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: children,
            ),
          ),
        );
      },
    );
  }
}
