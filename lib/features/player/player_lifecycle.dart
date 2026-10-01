import 'dart:async';

/// Prevents another media_kit player from being created while a full-screen
/// player's native stop/dispose is still in flight during route transitions.
class PlayerRouteTeardownBarrier {
  int _leases = 0;
  Completer<void> _idle = Completer<void>()..complete();

  PlayerRouteTeardownLease acquire() {
    if (_leases++ == 0) _idle = Completer<void>();
    return PlayerRouteTeardownLease._(() {
      if (_leases == 0) return;
      if (--_leases == 0) _idle.complete();
    });
  }

  Future<void> waitUntilIdle() async {
    while (_leases > 0) {
      await _idle.future;
    }
  }
}

class PlayerRouteTeardownLease {
  PlayerRouteTeardownLease._(this._release);

  final void Function() _release;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

final playerRouteTeardownBarrier = PlayerRouteTeardownBarrier();

/// Coordinates a player open with its native teardown.
///
/// A route can disappear while media_kit is still opening a source. Disposing
/// the native player concurrently with that open leaves a stale video surface
/// behind, so the open must settle after stop and before dispose.
class PlayerLifecycleGate {
  int _generation = 0;
  bool _closing = false;
  final Set<Future<void>> _opens = <Future<void>>{};

  /// Returns a token for a new open, or `-1` once shutdown has started.
  int beginOpen() => _closing ? -1 : ++_generation;

  /// Whether work belonging to [token] may still touch the player.
  bool canContinue(int token) => !_closing && token > 0 && token == _generation;

  /// Tracks an asynchronous native open until it has fully settled.
  Future<T> trackOpen<T>(int token, Future<T> Function() operation) {
    if (!canContinue(token)) {
      return Future<T>.error(StateError('player is closing'));
    }
    late final Future<T> tracked;
    tracked = operation();
    final marker = tracked.then<void>((_) {}, onError: (error, stackTrace) {});
    _opens.add(marker);
    marker.whenComplete(() {
      _opens.remove(marker);
    });
    return tracked;
  }

  /// Runs native preparation steps and the open as one teardown-tracked unit.
  /// After every awaited step it checks the token before allowing another
  /// native call, so a route close cannot continue setup on a disposed player.
  Future<bool> runPlayerOpenSteps(
    int token,
    List<Future<void> Function()> steps,
  ) async {
    var completed = false;
    try {
      await trackOpen(token, () async {
        for (final step in steps) {
          if (!canContinue(token)) return;
          await step();
        }
        completed = true;
      });
    } catch (_) {
      if (canContinue(token)) rethrow;
    }
    return completed && canContinue(token);
  }

  /// Stops the native player, waits for any open to settle, then disposes it.
  Future<void> close({
    required Future<void> Function() stop,
    required Future<void> Function() dispose,
  }) async {
    if (_closing) return;
    _closing = true;
    _generation++;
    // Start stop immediately to interrupt native loading, but do not make
    // disposal depend on that platform future: a stuck stop is exactly what
    // leaves the old surface alive after the route has gone.
    unawaited(stop().catchError((_) {}));
    final opens = List<Future<void>>.of(_opens);
    if (opens.isNotEmpty) await Future.wait(opens);
    await dispose();
  }
}
