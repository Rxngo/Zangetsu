import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/media_item.dart';
import '../../../core/repository/source_repository.dart';
import '../../../core/zmode/match_store.dart';
import '../../../core/zmode/source_matcher.dart';
import '../../../core/zmode/zmode_ids.dart';

class WrongTitleState {
  const WrongTitleState({
    this.results = const [],
    this.loading = false,
    this.query = '',
  });

  final List<MediaItem> results;
  final bool loading;

  /// What the running search is for. Shown while it runs, so a slow source
  /// says what it is doing instead of only spinning.
  final String query;

  WrongTitleState copyWith({
    List<MediaItem>? results,
    bool? loading,
    String? query,
  }) => WrongTitleState(
    results: results ?? this.results,
    loading: loading ?? this.loading,
    query: query ?? this.query,
  );
}

/// Manual re-match against one source: search it and pin the right result.
/// The source can be changed from inside the sheet — a title missing from one
/// source is the most likely moment to want a different one, and backing out
/// to change it and coming back is the long way round.
class WrongTitleCubit extends Cubit<WrongTitleState> {
  WrongTitleCubit({
    required SourceRepository sources,
    required SourceMatcher matcher,
    required ZCanonical canonical,
    required String sourceId,
  }) : _sources = sources,
       _matcher = matcher,
       _canonical = canonical,
       _sourceId = sourceId,
       super(const WrongTitleState());

  final SourceRepository _sources;
  final SourceMatcher _matcher;
  final ZCanonical _canonical;

  /// The title being corrected — the sheet needs it to ask the store which
  /// result is already pinned, so that one can be marked rather than offered
  /// again as if it were a different show.
  ZCanonical get canonical => _canonical;

  /// The source this correction currently applies to.
  String _sourceId;
  String get sourceId => _sourceId;
  String? _metadataRetryQuery;
  List<String> _metadataRetryAliases = const [];
  int? _metadataRetryMalId;

  /// Correct against a different source, re-running the same query against it.
  /// This only changes which source THIS correction searches — nothing is
  /// persisted until [choose] actually pins a result (see [pinManual]).
  /// Writing a kind-wide default just from browsing the dropdown was the bug
  /// this design fixes: every title started naming whichever source was last
  /// glanced at here.
  Future<void> setSource(String id) async {
    if (id == _sourceId) return;
    _sourceId = id;
    await search(
      state.query,
      retryWithMetadataAliases: state.query == _metadataRetryQuery,
      metadataAliases: _metadataRetryAliases,
      malId: _metadataRetryMalId,
    );
  }

  int _searchGeneration = 0;

  Future<void> search(
    String query, {
    bool retryWithMetadataAliases = false,
    List<String> metadataAliases = const [],
    int? malId,
  }) async {
    final q = query.trim();
    if (retryWithMetadataAliases) {
      _metadataRetryQuery = q;
      _metadataRetryAliases = metadataAliases;
      _metadataRetryMalId = malId;
    } else if (q != _metadataRetryQuery) {
      _metadataRetryQuery = null;
      _metadataRetryAliases = const [];
      _metadataRetryMalId = null;
    }
    final generation = ++_searchGeneration;
    emit(state.copyWith(loading: true, query: q));
    try {
      var results = await _sources.search(q, sourceId: _sourceId);
      if (!_isCurrentSearch(generation)) return;
      results = _uniqueResults(results);
      emit(state.copyWith(results: results));

      if (retryWithMetadataAliases &&
          !_hasClearMatch(results, [q, ...metadataAliases], malId)) {
        for (final alias in _distinctAliases(q, metadataAliases).take(3)) {
          try {
            final aliasResults = await _sources.search(
              alias,
              sourceId: _sourceId,
            );
            if (!_isCurrentSearch(generation)) return;
            results = _uniqueResults([...results, ...aliasResults]);
            emit(state.copyWith(results: results));
            if (_hasClearMatch(results, [q, ...metadataAliases], malId)) break;
          } catch (e) {
            debugPrint('[zmode] manual alias search on $_sourceId failed: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[zmode] manual search on $_sourceId failed: $e');
      if (_isCurrentSearch(generation)) {
        emit(state.copyWith(results: const []));
      }
    } finally {
      if (_isCurrentSearch(generation)) {
        emit(state.copyWith(loading: false));
      }
    }
  }

  bool _isCurrentSearch(int generation) =>
      !isClosed && generation == _searchGeneration;

  static List<String> _distinctAliases(String query, List<String> aliases) {
    String key(String value) =>
        value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    final seen = {key(query)};
    return [
      for (final alias in aliases)
        if (alias.trim().isNotEmpty && seen.add(key(alias))) alias.trim(),
    ];
  }

  bool _hasClearMatch(
    List<MediaItem> results,
    List<String> knownTitles,
    int? malId,
  ) {
    String key(String value) =>
        value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    return results.any((result) {
      final resultTitles = [
        result.title,
        if (result.englishTitle != null) result.englishTitle!,
      ];
      return knownTitles.any(
        (title) =>
            titleIdentityMatches(result, title, wantedMalId: malId) ||
            resultTitles.any((resultTitle) => key(resultTitle) == key(title)),
      );
    });
  }

  static List<MediaItem> _uniqueResults(List<MediaItem> results) {
    final seen = <String>{};
    return [
      for (final result in results)
        if (seen.add(
          '${result.sourceId}\u0000${result.url.isEmpty ? result.id : result.url}',
        ))
          result,
    ];
  }

  Future<SourceMatch> choose(MediaItem item) =>
      _matcher.pinManual(_canonical, item);
}
