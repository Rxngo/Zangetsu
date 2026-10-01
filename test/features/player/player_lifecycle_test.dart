import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/features/player/player_lifecycle.dart';

void main() {
  test(
    'route teardown lease blocks a replacement player until disposal',
    () async {
      final barrier = PlayerRouteTeardownBarrier();
      final lease = barrier.acquire();
      var resumed = false;

      final waiting = barrier.waitUntilIdle().then((_) => resumed = true);
      await Future<void>.delayed(Duration.zero);
      expect(resumed, isFalse);

      lease.release();
      await waiting;
      expect(resumed, isTrue);
    },
  );

  test('shutdown waits for an in-flight open before disposing', () async {
    final gate = PlayerLifecycleGate();
    final openDone = Completer<void>();
    final events = <String>[];
    final token = gate.beginOpen();
    final opening = gate.trackOpen(token, () async {
      events.add('open-start');
      await openDone.future;
      events.add('open-done');
    });

    final closing = gate.close(
      stop: () async {
        events.add('stop');
        openDone.complete();
      },
      dispose: () async => events.add('dispose'),
    );

    await closing;
    await opening;
    expect(events, ['open-start', 'stop', 'open-done', 'dispose']);
    expect(gate.canContinue(token), isFalse);
  });

  test(
    'shutdown stops setup steps before they touch a disposed player',
    () async {
      final gate = PlayerLifecycleGate();
      final setupWaiting = Completer<void>();
      final events = <String>[];
      final token = gate.beginOpen();
      final setup = gate.runPlayerOpenSteps(token, [
        () async {
          events.add('prepare-start');
          await setupWaiting.future;
          events.add('prepare-done');
        },
        () async => events.add('set-property'),
        () async => events.add('player-open'),
      ]);

      final closing = gate.close(
        stop: () async {
          events.add('stop');
          setupWaiting.complete();
        },
        dispose: () async => events.add('dispose'),
      );

      expect(await setup, isFalse);
      await closing;
      expect(events, ['prepare-start', 'stop', 'prepare-done', 'dispose']);
    },
  );
}
