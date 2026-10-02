import 'package:flutter/material.dart';

import '../../core/models/episode.dart';
import '../../core/reading/chapter_nav.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../l10n/l10n.dart';
import 'chapter_download_selection.dart';

/// Lets a reader choose an inclusive range of exact chapter rows to download.
///
/// The result contains list indexes, not chapter numbers: multiple scanlation
/// groups can publish the same numbered chapter, and provider ordering is the
/// source of truth for the run.
class ChapterDownloadRangeSheet extends StatefulWidget {
  const ChapterDownloadRangeSheet({
    required this.chapters,
    required this.initialFromIndex,
    required this.initialToIndex,
    required this.unavailableUrls,
    this.isChapter = true,
    super.key,
  });

  final List<Episode> chapters;
  final int initialFromIndex;
  final int initialToIndex;
  final Set<String> unavailableUrls;
  final bool isChapter;

  @override
  State<ChapterDownloadRangeSheet> createState() =>
      _ChapterDownloadRangeSheetState();
}

class _ChapterDownloadRangeSheetState extends State<ChapterDownloadRangeSheet> {
  late int _fromIndex;
  late int _toIndex;

  @override
  void initState() {
    super.initState();
    final last = widget.chapters.isEmpty ? 0 : widget.chapters.length - 1;
    _fromIndex = widget.initialFromIndex.clamp(0, last).toInt();
    _toIndex = widget.initialToIndex.clamp(_fromIndex, last).toInt();
  }

  String _itemLabel(int index) {
    final chapter = widget.chapters[index];
    final prefix = widget.isChapter ? 'Ch.' : 'E';
    return '$prefix${widget.isChapter ? ' ' : ''}${chapterNumberLabel(widget.chapters, index)} · ${chapter.title}';
  }

  Future<void> _pickIndex({required bool isStart}) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _DownloadRangeIndexPicker(
        chapters: widget.chapters,
        isChapter: widget.isChapter,
        canSelect: (index) => isStart || index >= _fromIndex,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _fromIndex = picked;
        if (_toIndex < picked) _toIndex = picked;
      } else {
        _toIndex = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chapters = widget.chapters;
    final selected = chapters.isEmpty
        ? const <Episode>[]
        : selectChapterDownloadRange(
            chapters: chapters,
            fromIndex: _fromIndex,
            toIndex: _toIndex,
            unavailableUrls: widget.unavailableUrls,
          );
    final canDownload = selected.isNotEmpty;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(context.l10n.custom, style: AppText.headline),
            const SizedBox(height: 8),
            _RangeEndpointTile(
              label: context.l10n.startChapter,
              value: chapters.isEmpty ? '' : _itemLabel(_fromIndex),
              onTap: chapters.isEmpty ? null : () => _pickIndex(isStart: true),
            ),
            _RangeEndpointTile(
              label: context.l10n.endChapter,
              value: chapters.isEmpty ? '' : _itemLabel(_toIndex),
              onTap: chapters.isEmpty ? null : () => _pickIndex(isStart: false),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: canDownload
                    ? () => Navigator.pop(context, (
                        from: _fromIndex,
                        to: _toIndex,
                      ))
                    : null,
                icon: const Icon(Icons.download_rounded),
                label: Text(context.l10n.download),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeEndpointTile extends StatelessWidget {
  const _RangeEndpointTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppText.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DownloadRangeIndexPicker extends StatefulWidget {
  const _DownloadRangeIndexPicker({
    required this.chapters,
    required this.isChapter,
    required this.canSelect,
  });

  final List<Episode> chapters;
  final bool isChapter;
  final bool Function(int index) canSelect;

  @override
  State<_DownloadRangeIndexPicker> createState() =>
      _DownloadRangeIndexPickerState();
}

class _DownloadRangeIndexPickerState extends State<_DownloadRangeIndexPicker> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final indexes = [
      for (var i = 0; i < widget.chapters.length; i++)
        if (query.isEmpty ||
            '${chapterNumberLabel(widget.chapters, i)} ${widget.chapters[i].title} ${widget.chapters[i].scanlator ?? ''}'
                .toLowerCase()
                .contains(query))
          i,
    ];
    final media = MediaQuery.of(context);
    final availableHeight = media.size.height - media.viewInsets.bottom;
    final maxHeight = availableHeight * 0.82;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: maxHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: TextField(
                controller: _search,
                autofocus: true,
                style: AppText.body.copyWith(color: AppColors.textPrimary),
                cursorColor: AppColors.accent,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
                  hintText: widget.isChapter
                      ? context.l10n.findChapter
                      : context.l10n.findEpisode,
                  hintStyle: AppText.body.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  filled: true,
                  fillColor: AppColors.surface2,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: indexes.length,
                itemBuilder: (context, row) {
                  final index = indexes[row];
                  final chapter = widget.chapters[index];
                  final enabled = widget.canSelect(index);
                  return ListTile(
                    enabled: enabled,
                    titleTextStyle: AppText.body.copyWith(
                      color: enabled
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                    ),
                    title: Text(
                      '${widget.isChapter ? 'Ch. ' : 'E'}${chapterNumberLabel(widget.chapters, index)} · ${chapter.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: chapter.scanlator == null
                        ? null
                        : Text(
                            chapter.scanlator!,
                            style: AppText.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textTertiary,
                    ),
                    onTap: enabled ? () => Navigator.pop(context, index) : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
