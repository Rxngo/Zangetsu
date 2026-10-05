import 'dart:math' as math;

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

class _TranslationBubbleLayout {
  _TranslationBubbleLayout({
    required this.region,
    required this.sourceIndex,
    required this.sourceBounds,
    required this.paragraph,
    required this.preferredTextWidth,
  });

  final MangaTranslatedRegion region;
  final int sourceIndex;
  final Rect sourceBounds;
  final TextPainter paragraph;
  final double preferredTextWidth;
  late double textWidth;
  late Rect bubbleBounds;
}

List<double> _lineWidthCandidates({
  required double preferredWidth,
  required double sourceWidth,
}) {
  final minimumWidth = math.min(preferredWidth, math.max(1.0, sourceWidth - 2));
  return <double>{
    preferredWidth,
    math.max(minimumWidth, preferredWidth * 0.8),
    math.max(minimumWidth, preferredWidth * 0.6),
    minimumWidth,
  }.toList()..sort((a, b) => b.compareTo(a));
}

List<Rect> _bubblePositionCandidates({
  required Rect anchor,
  required Size size,
  required Rect pageBounds,
}) {
  final maxLeft = pageBounds.right - size.width;
  final maxTop = pageBounds.bottom - size.height;
  final lefts = <double>{
    anchor.center.dx - size.width / 2,
    anchor.left,
    anchor.right - size.width,
  };
  final tops = <double>{
    anchor.center.dy - size.height / 2,
    anchor.top,
    anchor.bottom - size.height,
  };
  final candidates = <Rect>{};
  for (final candidateLeft in lefts) {
    final left = candidateLeft.clamp(pageBounds.left, maxLeft).toDouble();
    for (final candidateTop in tops) {
      final top = candidateTop.clamp(pageBounds.top, maxTop).toDouble();
      candidates.add(Rect.fromLTWH(left, top, size.width, size.height));
    }
  }
  return candidates.toList()..sort((first, second) {
    final firstDistance = (first.center - anchor.center).distanceSquared;
    final secondDistance = (second.center - anchor.center).distanceSquared;
    return firstDistance.compareTo(secondDistance);
  });
}

bool _bubbleIsClear({
  required Rect candidate,
  required int sourceIndex,
  required List<Rect> sourceBounds,
  required List<Rect> placedBubbles,
}) {
  for (var index = 0; index < sourceBounds.length; index++) {
    if (index == sourceIndex) continue;
    if (candidate.overlaps(sourceBounds[index].inflate(1))) return false;
  }
  for (final placedBubble in placedBubbles) {
    if (candidate.overlaps(placedBubble.inflate(1))) return false;
  }
  return true;
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
    this.backgroundColor = const Color(0xFF000000),
  });

  /// The page translation whose regions are shown.
  final MangaPageTranslationResult result;

  /// The image fitting behavior used to map regions into the parent.
  final BoxFit fit;

  /// The alignment used when fitting the source image into the parent.
  final Alignment alignment;

  /// An optional style for translated text.
  final TextStyle? textStyle;

  /// The background behind each translated region.
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
        final textDirection = Directionality.of(context);
        final textScaler = MediaQuery.textScalerOf(context);
        final layouts = <_TranslationBubbleLayout>[];
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

          // OCR bounds hug the original glyphs, not the speech balloon. A
          // translation can be much wider, so use that rect as an anchor and
          // wrap to a readable, page-relative width instead of forcing each
          // word into a narrow vertical column.
          final paragraph = TextPainter(
            text: TextSpan(
              text: region.translatedText,
              style: resolvedTextStyle,
            ),
            textAlign: TextAlign.center,
            textDirection: textDirection,
            textScaler: textScaler,
          )..layout();
          final maxLineWidth = math.min(
            outputRect.width,
            math.max(1.0, outputRect.width * 0.42),
          );
          final preferredTextWidth = math.min(
            math.max(1.0, paragraph.width),
            maxLineWidth,
          );
          paragraph.layout(maxWidth: preferredTextWidth);
          layouts.add(
            _TranslationBubbleLayout(
              region: region,
              sourceIndex: layouts.length,
              sourceBounds: bounds,
              paragraph: paragraph,
              preferredTextWidth: preferredTextWidth,
            ),
          );
        }

        final sourceBounds = layouts
            .map((layout) => layout.sourceBounds)
            .toList();
        final placedBubbles = <Rect>[];
        for (final layout in layouts) {
          const horizontalPadding = 2.0;
          const verticalPadding = 2.0;
          var placed = false;
          for (final textWidth in _lineWidthCandidates(
            preferredWidth: layout.preferredTextWidth,
            sourceWidth: layout.sourceBounds.width,
          )) {
            layout.paragraph.layout(maxWidth: textWidth);
            final bubbleWidth = math.min(
              outputRect.width,
              math.max(
                layout.sourceBounds.width,
                textWidth + horizontalPadding,
              ),
            );
            final bubbleHeight = math.min(
              outputRect.height,
              math.max(
                layout.sourceBounds.height,
                layout.paragraph.height + verticalPadding,
              ),
            );
            final candidates = _bubblePositionCandidates(
              anchor: layout.sourceBounds,
              size: Size(bubbleWidth, bubbleHeight),
              pageBounds: outputRect,
            );
            for (final candidate in candidates) {
              if (!_bubbleIsClear(
                candidate: candidate,
                sourceIndex: layout.sourceIndex,
                sourceBounds: sourceBounds,
                placedBubbles: placedBubbles,
              )) {
                continue;
              }
              layout
                ..textWidth = textWidth
                ..bubbleBounds = candidate;
              placedBubbles.add(candidate);
              placed = true;
              break;
            }
            if (placed) break;
          }
          if (!placed) {
            layout
              ..textWidth = math.min(
                layout.preferredTextWidth,
                math.max(1.0, layout.sourceBounds.width - horizontalPadding),
              )
              ..bubbleBounds = layout.sourceBounds;
            placedBubbles.add(layout.sourceBounds);
          }
        }

        final children = <Widget>[];
        for (final layout in layouts) {
          final region = layout.region;

          children.add(
            Positioned.fromRect(
              rect: layout.bubbleBounds,
              child: Semantics(
                label: region.translatedText,
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(1),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: layout.textWidth,
                            child: Text(
                              region.translatedText,
                              textAlign: TextAlign.center,
                              softWrap: true,
                              style: resolvedTextStyle,
                            ),
                          ),
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
