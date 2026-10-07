import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/download/download_manager.dart';
import 'package:watch_app/core/download/download_record.dart';
import 'package:watch_app/core/hive/safe_box.dart';
import 'package:watch_app/core/models/episode.dart';
import 'package:watch_app/core/models/video_source.dart';
import 'package:watch_app/core/repository/catalogue_repository.dart';

class _EmptyCatalogue implements CatalogueRepository {
  @override
  noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #sources) {
      return Future.value(const <VideoSource>[]);
    }
    return super.noSuchMethod(invocation);
  }
}

class _TestDownloaderStorage implements PersistentStorage {
  @override
  Future<List<Task>> retrieveAllPausedTasks() async => const [];

  @override
  (String, int) get currentDatabaseVersion => ('test', 1);

  @override
  Future<(String, int)> get storedDatabaseVersion async =>
      currentDatabaseVersion;

  @override
  Future<void> initialize() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;
  late DownloadManager manager;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FileDownloader(persistentStorage: _TestDownloaderStorage());
    hiveDir = await Directory.systemTemp.createTemp('download_delete_race');
    hiveBoxDir = hiveDir.path;
    Hive.init(hiveDir.path);
    await DownloadManager.init();
    manager = DownloadManager(_EmptyCatalogue());
  });

  tearDown(() async {
    manager.dispose();
    await Hive.close();
    debugDefaultTargetPlatformOverride = null;
    hiveBoxDir = null;
    if (await hiveDir.exists()) await hiveDir.delete(recursive: true);
  });

  test(
    'delete marks the record canceled before asynchronous cleanup',
    () async {
      await manager.enqueueEpisodes(
        sourceId: 'source',
        showId: 'show',
        showTitle: 'Show',
        showUrl: 'https://example.com/show',
        category: 'sub',
        quality: 'best',
        episodes: const [
          Episode(
            id: 'episode',
            title: 'Episode 1',
            url: 'https://example.com/1',
          ),
        ],
        nowMs: 1,
      );
      final record = manager.all.single;
      expect(record.status, DownloadStatus.unsupported);

      DownloadStatus? statusAtFirstNotification;
      manager.addListener(() {
        final records = manager.all;
        statusAtFirstNotification = records.isEmpty
            ? null
            : records.first.status;
      });

      final deletion = manager.delete(record);

      expect(statusAtFirstNotification, DownloadStatus.canceled);
      await deletion;
      expect(manager.all, isEmpty);
    },
  );
}
