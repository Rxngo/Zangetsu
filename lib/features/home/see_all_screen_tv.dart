import 'package:flutter/material.dart';

import '../../core/models/media_item.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/tv/tv_back_button.dart';
import '../../core/tv/tv_poster_tile.dart';
import '../../core/ui/poster_card.dart';

/// TV variant of [SeeAllScreen]: a full-screen D-pad-navigable poster grid.
///
/// Constructor is byte-compatible with [SeeAllScreen] so the caller's
/// `if (isTv)` branch is a one-line forwarding return.
///
/// When [onLoadMore] is provided the grid paginates: as D-pad focus / scroll
/// approaches the last rows the next page is fetched and appended. When it's
/// null the grid is a fixed list over [items] — identical to the pre-pagination
/// behaviour, so search / JS / non-paginating callers are unchanged.
class SeeAllScreenTv extends StatefulWidget {
  const SeeAllScreenTv({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
    this.onLongPress,
    this.tagsFor,
    this.onLoadMore,
  });

  final String title;
  final List<MediaItem> items;
  final void Function(MediaItem) onTap;
  final void Function(MediaItem)? onLongPress;

  /// Optional per-item poster badges (e.g. SUB/DUB/MOVIE). Mirrors
  /// [SeeAllScreen.tagsFor] so callers are unchanged.
  final List<String> Function(MediaItem)? tagsFor;

  /// Optional next-page fetcher for infinite scroll. `page` is 1-based and the
  /// initial [items] ARE page 1, so the first call requests page 2. Returning an
  /// empty list (or only already-seen items) ends pagination. Null → fixed list.
  final Future<List<MediaItem>> Function(int page)? onLoadMore;

  @override
  State<SeeAllScreenTv> createState() => _SeeAllScreenTvState();
}

class _SeeAllScreenTvState extends State<SeeAllScreenTv> {
  /// 6 columns keeps the cards near the home-rail ~140 dp scale on a 1080p TV
  /// (5 rendered them oversized).

  late final List<MediaItem> _items = [...widget.items];
  final Set<String> _seen = {};
  final ScrollController _controller = ScrollController();

  /// The last page already loaded — the initial [items] are page 1.
  int _page = 1;
  bool _loading = false;
  bool _end = false;

  @override
  void initState() {
    super.initState();
    for (final it in _items) {
      _seen.add(_keyOf(it));
    }
    if (widget.onLoadMore != null) {
      _controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Dedupe key — prefer the stable id, fall back to the url.
  String _keyOf(MediaItem m) => m.id.isNotEmpty ? m.id : m.url;

  void _onScroll() {
    if (_loading || _end || !_controller.hasClients) return;
    final pos = _controller.position;
    if (pos.pixels >= pos.maxScrollExtent * 0.8) {
      _loadMore();
    }
  }

  /// Index-based trigger: when a cell within the last two rows is BUILT (D-pad
  /// focus scrolled the grid enough to lazily build it), fetch the next page.
  /// Complements [_onScroll] for the case where the first page fits without
  /// scrolling. Scheduled post-frame so it never calls setState during build.
  void _maybeLoadFromIndex(int index) {
    if (widget.onLoadMore == null || _loading || _end) return;
    if (index < _items.length - tvPosterGridColumns(context) * 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMore();
    });
  }

  Future<void> _loadMore() async {
    final loader = widget.onLoadMore;
    if (loader == null || _loading || _end) return;
    setState(() => _loading = true);
    List<MediaItem> next = const [];
    try {
      next = await loader(_page + 1);
    } catch (_) {
      next = const [];
    }
    if (!mounted) return;
    final fresh = <MediaItem>[];
    for (final it in next) {
      final k = _keyOf(it);
      if (_seen.add(k)) fresh.add(it);
    }
    setState(() {
      _loading = false;
      if (fresh.isEmpty) {
        _end = true;
      } else {
        _items.addAll(fresh);
        _page += 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final paginating = widget.onLoadMore != null;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        automaticallyImplyLeading: false,
        toolbarHeight: 72,
        titleSpacing: 16,
        title: Row(
          children: [
            const TvBackButton(),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                widget.title,
                style: AppText.headline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          GridView.builder(
            controller: paginating ? _controller : null,
            padding: const EdgeInsets.fromLTRB(40, 8, 40, 40),
            cacheExtent: 800,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: tvPosterGridColumns(context),
              // Match the grid geometry to the chosen title placement.
              childAspectRatio: tvPosterGridAspect(context),
              crossAxisSpacing: 18,
              mainAxisSpacing: 22,
            ),
            itemCount: _items.length,
            itemBuilder: (context, i) {
              if (paginating) _maybeLoadFromIndex(i);
              final item = _items[i];
              return TvPosterTile(
                autofocus: i == 0,
                title: item.title,
                logoItem: item,
                imageUrl: item.cover,
                wideImageUrl: item.banner,
                headers: item.coverHeaders,
                genres: item.genres,
                isAdult: item.isAdult,
                scoreBadge: item.score,
                qualityBadge: item.quality,
                dubBadge: item.dubBadge,
                tags: widget.tagsFor?.call(item) ?? const [],
                onTap: () => widget.onTap(item),
                onLongPress: widget.onLongPress == null
                    ? null
                    : () => widget.onLongPress!(item),
              );
            },
          ),
          // Bottom loading indicator while the next page is in flight (only in
          // the paginating configuration, so non-paginating callers are unchanged).
          if (paginating && _loading)
            const Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
