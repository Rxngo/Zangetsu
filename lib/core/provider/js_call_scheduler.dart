import 'dart:async';
import 'dart:collection';

// Circular on purpose: the scheduler serves the manager's abandon signal and
// the manager owns the scheduler. Dart allows it, and moving the exception to
// a third file just to dodge it would be churn for a lint.
import 'provider_manager.dart' show ProviderCallAbandoned;

/// Which queue a provider call is waiting in.
///
/// The JS engine is a single context — two calls at once corrupts it — so every
/// call from every source crosses the same one-at-a-time bridge. The stall this
/// fixes is ORDER, not concurrency: a 30s probe sat in front of a detail screen
/// whose own work took 0.1s. Two lanes, one engine: a tap overtakes a waiting
/// prefetch, but a running call is never interrupted.
enum CallLane {
  /// A tap: detail, search, episodes, Play, anything the viewer is watching.
  interactive,

  /// Housekeeping nobody is waiting on: prefetch, re-probes, cache warming.
  background,
}

/// Zone key carrying "is the caller that scheduled this still waiting?".
final Object _callerAliveKey = Object();

/// Runs [body] tagging every provider call it makes as belonging to a caller
/// that [alive] may stop caring about.
///
/// This is how a superseded playback sweep stops holding the bridge. The
/// scheduler checks the answer when a call reaches the front of the queue, so
/// a sweep that was replaced while its calls sat queued drops them instead of
/// running each one — measured in BMG7K8: three overlapping taps, and the
/// second and third waited 20s in the queue behind the first tap's abandoned
/// fan-out. Nothing had told the queue those calls were unwanted.
Future<T> inProviderCaller<T>(Future<T> Function() body, bool Function() alive) =>
    runZoned(body, zoneValues: {_callerAliveKey: alive});

/// Whether the caller that scheduled the call now being enqueued has gone away.
bool Function()? staleProviderCaller() {
  final alive = Zone.current[_callerAliveKey];
  return alive is bool Function() ? () => !alive() : null;
}

/// Zone key marking a provider call as housekeeping nobody is waiting on.
final Object _backgroundCallKey = Object();

/// Runs [body] with every provider call it makes tagged background.
///
/// A zone, not a parameter, because the call chain is six layers deep (detail
/// screen → repository → manager → provider → host) and threading a flag
/// through all of them is a diff nobody can review. Set it at the few
/// fire-and-forget origins instead of at every call site.
Future<T> inProviderBackground<T>(Future<T> Function() body) =>
    runZoned(body, zoneValues: {_backgroundCallKey: true});

/// The lane for a call being enqueued right now.
///
/// Read at enqueue time, which is the right moment: the tap being protected is
/// the one that is QUEUED, and by the time the pump runs, the zone that
/// scheduled a prefetch is long gone.
CallLane currentProviderLane() =>
    Zone.current[_backgroundCallKey] == true
        ? CallLane.background
        : CallLane.interactive;

/// Thrown when a call gave up after waiting too long in the queue.
///
/// A retryable state for the UI, never a hang — and NOT a mark against the
/// source, which is exactly why this isn't [ProviderCallAbandoned]'s twin on
/// the health tally: a crowded queue says nothing about the source's quality.
class ProviderCallQueueTimeout implements Exception {
  const ProviderCallQueueTimeout(this.sourceId, this.method, this.waited);

  final String sourceId;
  final String method;
  final Duration waited;

  @override
  String toString() =>
      'Provider call $sourceId.$method waited ${waited.inSeconds}s in the queue';
}

/// Serialises provider calls across two lanes, interactive first.
///
/// Fairness guard: every [fairnessEvery]th dispatch goes to the background lane
/// even when interactive work is waiting, so a tapping spree can't starve a
/// prefetch forever. Strict priority without it is a different freeze.
class JsCallScheduler {
  JsCallScheduler({
    // How long a call may stand in the queue before it is given up on. A
    // call's real latency is its own runtime plus everyone ahead of it, so
    // this is a backstop against a wedged engine, not the primary bound -
    // `ProviderManager.maxProviderCallTimeout` caps the run itself.
    //
    // Deliberately the same length as that cap. An earlier version used 8s
    // here, reasoning that a shorter wait fails fast; measured, that threw away
    // real answers - `hdhub4u.getVideoSources waited 8s in the queue` fired on
    // a source that had already matched the title and loaded its page, so the
    // viewer got nothing for a search that was about to succeed. The queue
    // should not be the thing that decides a call is too slow; the call's own
    // budget should. Anything waiting longer than one call can run is standing
    // behind a call that has already overrun, and fails on that basis.
    this.backgroundWaitCeiling = const Duration(seconds: 25),
    this.interactiveWaitCeiling = const Duration(seconds: 25),
    this.fairnessEvery = 4,
  });

  final Duration backgroundWaitCeiling;
  final Duration interactiveWaitCeiling;
  final int fairnessEvery;

  final _interactive = Queue();
  final _background = Queue();
  int _sinceBackground = 0;
  bool _draining = false;

  /// Logs the wait of any call that queued behind other work. Without this the
  /// next freeze is a mystery — the whole queue is otherwise invisible.
  static void Function(String message)? debugLog;

  Future<T> enqueue<T>(
    String sourceId,
    String method,
    Future<T> Function() action, {
    CallLane lane = CallLane.interactive,
    bool Function()? abandoned,
  }) {
    final done = Completer<T>();
    // The zone answer is folded in HERE, not left to each caller, so a call
    // can't forget it. It is evaluated when the call reaches the front of the
    // queue, not when it was enqueued — that gap is the whole point: a sweep
    // superseded while its calls sat queued drops them instead of running each
    // one in front of the tap that replaced it.
    final isAbandoned = staleProviderCaller();
    final entry = _Entry<T>(
      sourceId: sourceId,
      method: method,
      action: action,
      done: done,
      lane: lane,
      enqueuedAt: DateTime.now(),
      abandoned: () =>
          (abandoned?.call() ?? false) || (isAbandoned?.call() ?? false),
    );
    (lane == CallLane.background ? _background : _interactive).add(entry);
    // A real timer, NOT a check on the next dispatch: the queue can be busy
    // with a 30s call, and a deadline that only gets examined when the pump
    // next advances would overshoot by exactly that 30s — the hang it exists
    // to prevent. The entry drops itself out of the queue when it fires.
    final ceiling = lane == CallLane.background
        ? backgroundWaitCeiling
        : interactiveWaitCeiling;
    entry.deadline = Timer(ceiling, () => _expire(entry, ceiling));
    _drain();
    return done.future;
  }

  void _expire(_Entry entry, Duration ceiling) {
    final q = entry.lane == CallLane.background ? _background : _interactive;
    if (!q.remove(entry)) return; // already served
    entry.fail(ProviderCallQueueTimeout(
        entry.sourceId, entry.method, ceiling));
    _drain();
  }

  void _drain() {
    if (_draining) return;
    _draining = true;
    scheduleMicrotask(_pump);
  }

  /// The ONE place the one-at-a-time guarantee lives.
  ///
  /// A single loop that keeps serving while work remains. It must not be a
  /// chain of "serve one, re-schedule the next" hops: the flag would clear
  /// before the call finished and a second pump would start alongside it —
  /// the exact engine re-entrancy the serial queue existed to prevent.
  Future<void> _pump() async {
    while (true) {
      final entry = _take();
      if (entry == null) {
        _draining = false;
        return;
      }
      await _serve(entry);
    }
  }

  _Entry? _take() {
    // Deadlines are enforced by their own timers (see [_expire]); all this has
    // to do is never hand out an already-expired entry.
    final now = DateTime.now();
    for (final q in [_interactive, _background]) {
      while (q.isNotEmpty) {
        final e = q.first;
        final ceiling = e.lane == CallLane.background
            ? backgroundWaitCeiling
            : interactiveWaitCeiling;
        if (now.difference(e.enqueuedAt) < ceiling) break;
        q.removeFirst();
        e.deadline?.cancel();
        e.fail(ProviderCallQueueTimeout(
            e.sourceId, e.method, now.difference(e.enqueuedAt)));
      }
    }

    if (_background.isEmpty) return _interactive.isEmpty ? null : _interactive.removeFirst();
    if (_interactive.isEmpty) return _background.removeFirst();
    if (++_sinceBackground >= fairnessEvery) {
      _sinceBackground = 0;
      return _background.removeFirst();
    }
    return _interactive.removeFirst();
  }

  Future<void> _serve(_Entry entry) async {
    // Checked HERE, not at enqueue time: the whole point is the wait in
    // between. A viewer who backed out while this sat in the queue is no
    // longer owed an answer, and running it anyway is what made the next
    // screen take 12s, then 24s, then 27s in the shared report.
    if (entry.abandoned?.call() ?? false) {
      entry.fail(const ProviderCallAbandoned());
      return;
    }
    final waited = DateTime.now().difference(entry.enqueuedAt);
    if (waited > const Duration(milliseconds: 250)) {
      debugLog?.call(
        'call ${entry.sourceId}.${entry.method} ${entry.lane.name} '
        'waited ${waited.inMilliseconds}ms in the queue '
        '(interactive ${_interactive.length}, background ${_background.length})',
      );
    }
    try {
      entry.complete(await entry.action());
    } catch (e) {
      entry.fail(e);
    }
  }
}

class _Entry<T> {
  _Entry({
    required this.sourceId,
    required this.method,
    required this.action,
    required this.done,
    required this.lane,
    required this.enqueuedAt,
    this.abandoned,
  });

  final String sourceId;
  final String method;
  final Future<T> Function() action;
  final Completer<T> done;
  final CallLane lane;
  final DateTime enqueuedAt;
  final bool Function()? abandoned;
  Timer? deadline;

  void complete(T value) {
    deadline?.cancel();
    if (!done.isCompleted) done.complete(value);
  }

  void fail(Object e) {
    deadline?.cancel();
    if (!done.isCompleted) done.completeError(e);
  }
}
