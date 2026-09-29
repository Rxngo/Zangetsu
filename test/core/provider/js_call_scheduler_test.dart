import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/provider/js_call_scheduler.dart';
import 'package:watch_app/core/provider/provider_manager.dart' show ProviderCallAbandoned;

void main() {
  late JsCallScheduler s;

  /// Completes a queued call by hand, so no timers are involved in the
  /// ordering assertions — only the deadlines use real time.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    // Short ceilings: these tests wait on real timers, and a production 20s/30s
    // wait per case is not a unit test.
    s = JsCallScheduler(
      backgroundWaitCeiling: const Duration(seconds: 1),
      interactiveWaitCeiling: const Duration(seconds: 1),
    );
  });

  test('runs one call at a time — the engine cannot be re-entered', () async {
    var running = 0;
    var maxConcurrent = 0;
    final gates = <Completer<void>>[];

    for (var i = 0; i < 3; i++) {
      gates.add(Completer<void>());
      s.enqueue('src', 'm', () async {
        running++;
        if (running > maxConcurrent) maxConcurrent = running;
        await gates[i].future;
        running--;
        return 'ok';
      });
    }
    await settle();
    expect(maxConcurrent, 1, reason: 'a second call started before the first ended');

    gates[0].complete();
    await settle();
    gates[1].complete();
    await settle();
    gates[2].complete();
    await settle();
    expect(maxConcurrent, 1);
  });

  test('an interactive call overtakes a queued background call', () async {
    final order = <String>[];
    final bg = Completer<void>();

    s.enqueue('s', 'bg', () async {
      order.add('bg-running');
      await bg.future;
      return 'bg';
    }, lane: CallLane.background);
    await settle();
    expect(order, ['bg-running'], reason: 'the prefetch should start on an idle queue');

    s.enqueue('s', 'bg2', () async {
      order.add('bg2');
      return 'bg2';
    }, lane: CallLane.background);
    // The viewer taps while the prefetch is still running.
    s.enqueue('s', 'tap', () async {
      order.add('tap');
      return 'tap';
    }, lane: CallLane.interactive);
    await settle();

    expect(order, ['bg-running'], reason: 'the tap must not jump the RUNNING call');
    bg.complete();
    await settle();
    expect(order, ['bg-running', 'tap', 'bg2'],
        reason: 'the tap must overtake the waiting background call');
  });

  test('background still drains when interactive traffic never stops', () async {
    final order = <String>[];
    final hold = Completer<void>();

    // A tap is already running, so the prefetch and the burst genuinely queue.
    s.enqueue('s', 'hold', () async {
      order.add('hold');
      await hold.future;
      return 'hold';
    }, lane: CallLane.interactive);
    await settle();
    s.enqueue('s', 'bg', () async {
      order.add('bg');
      return 'bg';
    }, lane: CallLane.background);
    for (var i = 0; i < 5; i++) {
      s.enqueue('s', 'tap$i', () async {
        order.add('tap$i');
        return 't';
      }, lane: CallLane.interactive);
    }
    await settle();
    hold.complete();
    await settle();

    // Fairness: the prefetch must land inside the burst, not after it.
    final bgAt = order.indexOf('bg');
    expect(bgAt, isNonNegative, reason: 'the prefetch never ran — starved');
    expect(bgAt, lessThan(5), reason: 'background waited for the whole tap burst');
  });

  test('background keeps its own order among itself', () async {
    final order = <String>[];
    final hold = Completer<void>();

    s.enqueue('s', 'hold', () async {
      await hold.future;
      return 'hold';
    }, lane: CallLane.interactive);
    for (final n in ['b1', 'b2', 'b3']) {
      s.enqueue('s', n, () async {
        order.add(n);
        return n;
      }, lane: CallLane.background);
    }
    await settle();
    hold.complete();
    await settle();
    expect(order, ['b1', 'b2', 'b3']);
  });

  test('an abandoned caller never runs its call', () async {
    var ran = false;
    final f = s.enqueue('s', 'gone', () async {
      ran = true;
      return 'x';
    }, abandoned: () => true);
    await expectLater(f, throwsA(isA<ProviderCallAbandoned>()));
    await settle();
    expect(ran, isFalse);
  });

  test('a call that waited past its ceiling fails instead of hanging', () async {
    final hold = Completer<void>();
    s.enqueue('s', 'hold', () async {
      await hold.future;
      return 'hold';
    }, lane: CallLane.interactive);
    await settle();

    // The queue is stuck behind a call that never ends. The deadline must still
    // fire on its own — a check on the next dispatch would overshoot by the
    // full 30s, which is the hang this exists to prevent.
    final started = DateTime.now();
    final slow = s.enqueue(
      's', 'slow', () async => 'slow',
      lane: CallLane.background,
    );
    await expectLater(slow, throwsA(isA<ProviderCallQueueTimeout>()));
    expect(DateTime.now().difference(started).inSeconds,
        lessThanOrEqualTo(2), reason: 'the ceiling overshot');

    hold.complete();
    await settle();
  });

  test('a failure releases the lane for the next caller', () async {
    final f1 = s.enqueue('s', 'boom', () async => throw StateError('boom'));
    final f2 = s.enqueue('s', 'after', () async => 'after');
    await expectLater(f1, throwsA(isA<StateError>()));
    expect(await f2, 'after');
  });

  group('zone marking', () {
    test('defaults to interactive', () {
      expect(currentProviderLane(), CallLane.interactive);
    });

    test('a background origin marks the calls it makes', () async {
      CallLane? seen;
      final hold = Completer<void>();
      s.enqueue('s', 'hold', () async {
        await hold.future;
        return 'hold';
      });

      await inProviderBackground(() async {
        // Read at ENQUEUE time, which is what the scheduler does — the pump
        // runs long after this zone is gone.
        seen = currentProviderLane();
        final f = s.enqueue('s', 'warm', () async => 'warm');
        expect(seen, CallLane.background);
        hold.complete();
        await f;
      });
      expect(seen, CallLane.background);
    });

    test('the zone does not leak back to the caller', () {
      inProviderBackground(() async {});
      expect(currentProviderLane(), CallLane.interactive);
    });
  });

  group('superseded caller', () {
    test('no caller zone means no staleness answer', () {
      expect(staleProviderCaller(), isNull);
    });

    test('a live caller is not stale', () {
      var alive = true;
      inProviderCaller(() async {
        expect(staleProviderCaller()!(), isFalse);
      }, () => alive);
    });

    test('a caller that gave up reads as stale', () {
      var alive = true;
      inProviderCaller(() async {
        alive = false;
        expect(staleProviderCaller()!(), isTrue);
      }, () => alive);
    });

    test('a superseded caller never runs its queued call', () async {
      // The BMG7K8 shape: tap one is superseded while its calls sit queued.
      var alive = true;
      final hold = Completer<void>();
      s.enqueue('s', 'running', () async {
        await hold.future;
        return 'running';
      });

      var ran = false;
      final queued = inProviderCaller(() async {
        final f = s.enqueue('s', 'superseded', () async {
          ran = true;
          return 'x';
        });
        alive = false; // the viewer tapped something else
        return f;
      }, () => alive);

      hold.complete();
      await expectLater(queued, throwsA(isA<ProviderCallAbandoned>()));
      expect(ran, isFalse, reason: 'the dropped call must not reach the source');
    });
  });
}
