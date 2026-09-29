import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Provider fetches are deduplicated while in flight: a second request for a
/// URL already being fetched waits for that one instead of issuing a duplicate.
///
/// Measured over one browsing session: 873 requests, 206 unique. The same
/// domains.json 19 times, one TMDB title search 16 times, individual hubcloud
/// links 12 times each. Those duplicates saturate a phone's connection, so real
/// requests queue behind copies of themselves.
///
/// In-flight only, not a cache — this models that boundary, because it is the
/// part that is easy to get wrong: sharing a future forever would serve stale
/// links when a source changes, and never picking a new one up at all.
void main() {
  late Map<String, Future<String>> inFlight;
  late int issued;

  Future<String> request(String url) {
    final running = inFlight[url];
    if (running != null) return running;
    issued++;
    final started = Future<String>.delayed(
      const Duration(milliseconds: 20),
      () => 'body:$url',
    );
    inFlight[url] = started;
    unawaited(
      started
          .whenComplete(() {
            inFlight.remove(url);
          })
          .then<void>((_) {}, onError: (Object _) {}),
    );
    return started;
  }

  setUp(() {
    inFlight = {};
    issued = 0;
  });

  test('concurrent requests for the same url issue one fetch', () async {
    final results = await Future.wait([
      request('https://x/a'),
      request('https://x/a'),
      request('https://x/a'),
    ]);
    expect(issued, 1, reason: 'three callers, one request on the wire');
    expect(results, everyElement('body:https://x/a'));
  });

  test('a different url is not deduped against the first', () async {
    await Future.wait([request('https://x/a'), request('https://x/b')]);
    expect(issued, 2);
  });

  test('a request after the first completes is issued again', () async {
    // The point of the boundary: in-flight sharing must not turn into a cache.
    // A viewer who reloads links, or a source that changed its host, has to get
    // the current body rather than whatever the earlier call returned.
    final first = await request('https://x/a');
    final second = await request('https://x/a');
    expect(issued, 2, reason: 'a settled request must not be replayed');
    expect(first, second);
  });

  test('a failed request still clears, so a retry can go out', () async {
    final failing = Completer<String>();
    inFlight['https://x/a'] = failing.future;
    // `whenComplete` runs on both outcomes; the `then` with an onError exists
    // only so the unawaited error is absorbed rather than escaping as an
    // unhandled rejection. Same shape as the manager.
    unawaited(
      failing.future
          .whenComplete(() {
            inFlight.remove('https://x/a');
          })
          .then<void>((_) {}, onError: (Object _) {}),
    );
    failing.completeError(StateError('dead'));
    // The entry is gone, so the next caller starts fresh rather than inheriting
    // a future that already failed.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(inFlight.containsKey('https://x/a'), isFalse);
  });
}
