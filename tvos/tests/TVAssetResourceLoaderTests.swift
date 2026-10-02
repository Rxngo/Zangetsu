import Foundation

@main
enum TVAssetResourceLoaderTests {
  static func main() throws {
    try testUnsupportedAssetHeaderOptionIsNotUsed()
    testHeaderRouting()
    testHeaderApplication()
    testOnlySupportedMIMEHintsAreOverridden()
    testURLWrappingPreservesURL()
    testMIMEHintOnlyMarksRootPlaylist()
    testHLSPlaylistReferencesAreWrapped()
    testNonHTTPHLSReferencesAreUnchanged()
    try testCancelledRequestsAreNotCompletedOrServed()
    print("All TVAssetResourceLoader tests passed.")
  }

  private static func testUnsupportedAssetHeaderOptionIsNotUsed() throws {
    let controller = try String(
      contentsOfFile: "tvos/Runner/TvSystemPlayerViewController.swift",
      encoding: .utf8
    )
    expect(
      !controller.contains("AVURLAssetHTTPHeaderFieldsKey"),
      "AVPlayer must not use the unsupported arbitrary-header asset option"
    )
    expect(
      controller.contains("AVURLAssetHTTPUserAgentKey"),
      "User-Agent should use AVFoundation's supported asset option"
    )
  }

  private static func testHeaderRouting() {
    expect(
      !TVAssetResourceLoader.requiresResourceLoader(headers: ["User-Agent": "TV test"]),
      "User-Agent-only sources should keep AVPlayer's direct path"
    )
    expect(
      TVAssetResourceLoader.requiresResourceLoader(headers: ["rEfErEr": "https://site.test/"]),
      "Referer sources should use the header-aware resource loader"
    )
  }

  private static func testHeaderApplication() {
    var request = URLRequest(url: URL(string: "https://media.test/video.m3u8")!)
    TVAssetResourceLoader.apply(
      headers: [
        "Referer": "https://source.test/",
        "Cookie": "session=abc",
        "User-Agent": "TV test",
      ],
      to: &request
    )
    expect(
      request.value(forHTTPHeaderField: "Referer") == "https://source.test/", "Referer was dropped")
    expect(request.value(forHTTPHeaderField: "Cookie") == "session=abc", "Cookie was dropped")
    expect(request.value(forHTTPHeaderField: "User-Agent") == "TV test", "User-Agent was dropped")
  }

  private static func testOnlySupportedMIMEHintsAreOverridden() {
    expect(
      TVAssetResourceLoader.shouldOverrideMIMEType("application/x-mpegURL"),
      "HLS MIME should be forwarded to AVURLAsset"
    )
    expect(
      TVAssetResourceLoader.shouldOverrideMIMEType("video/mp4"),
      "MP4 MIME should be forwarded to AVURLAsset"
    )
    expect(
      !TVAssetResourceLoader.shouldOverrideMIMEType("application/dash+xml"),
      "DASH should not be advertised as a format AVPlayer supports"
    )
  }

  private static func testURLWrappingPreservesURL() {
    for source in [
      "https://media.test/path/video.m3u8?token=a%2Fb&quality=1080p",
      "http://media.test/path/video.mp4?key=abc",
    ] {
      let original = URL(string: source)!
      guard let wrapped = TVAssetResourceLoader.assetURL(for: original) else {
        fatalError("Could not wrap \(source)")
      }
      expect(
        TVAssetResourceLoader.upstreamURL(for: wrapped)?.absoluteString == original.absoluteString,
        "Wrapping must preserve the original URL, including its query"
      )
    }
  }

  private static func testMIMEHintOnlyMarksRootPlaylist() {
    let root = URL(string: "https://media.test/watch?id=123")!
    let segment = URL(string: "https://media.test/segment-1.ts")!
    expect(
      TVAssetResourceLoader.isHLSResource(
        url: root,
        rootURL: root,
        mimeTypeHint: "application/x-mpegURL"
      ),
      "The source MIME hint should identify a tokenized HLS root URL"
    )
    expect(
      !TVAssetResourceLoader.isHLSResource(
        url: segment,
        rootURL: root,
        mimeTypeHint: "application/x-mpegURL"
      ),
      "The HLS root MIME hint must not cause media segments to be buffered as playlists"
    )
    expect(
      TVAssetResourceLoader.isHLSResource(
        url: segment,
        rootURL: root,
        mimeTypeHint: nil,
        responseMimeType: "application/vnd.apple.mpegurl"
      ),
      "A child playlist should be detected from its server MIME type"
    )
  }

  private static func testHLSPlaylistReferencesAreWrapped() {
    let playlistURL = URL(string: "https://media.test/hls/master.m3u8?token=abc")!
    let playlist = """
      #EXTM3U
      #EXT-X-KEY:METHOD=AES-128,URI="keys/key.bin?auth=xyz"
      #EXT-X-MAP:URI="init.mp4"
      segment-001.ts?segment=1
      """
    let rewritten = TVAssetResourceLoader.rewriteHLSPlaylist(playlist, baseURL: playlistURL)
    let segment = URL(string: "segment-001.ts?segment=1", relativeTo: playlistURL)!.absoluteURL
    let key = URL(string: "keys/key.bin?auth=xyz", relativeTo: playlistURL)!.absoluteURL
    let initURL = URL(string: "init.mp4", relativeTo: playlistURL)!.absoluteURL
    expect(
      rewritten.contains(TVAssetResourceLoader.assetURL(for: segment)!.absoluteString),
      "Relative HLS segment URL was not wrapped"
    )
    expect(
      rewritten.contains("URI=\"\(TVAssetResourceLoader.assetURL(for: key)!.absoluteString)\""),
      "HLS encryption key URI was not wrapped"
    )
    expect(
      rewritten.contains("URI=\"\(TVAssetResourceLoader.assetURL(for: initURL)!.absoluteString)\""),
      "HLS initialization map URI was not wrapped"
    )
  }

  private static func testNonHTTPHLSReferencesAreUnchanged() {
    let playlistURL = URL(string: "https://media.test/hls/master.m3u8")!
    let playlist = #"#EXT-X-SESSION-DATA:DATA-ID="app",URI="data:text/plain,hello""#
    let rewritten = TVAssetResourceLoader.rewriteHLSPlaylist(playlist, baseURL: playlistURL)
    expect(rewritten == playlist, "Non-HTTP HLS URIs must stay unchanged")
  }

  private static func testCancelledRequestsAreNotCompletedOrServed() throws {
    let source = try String(
      contentsOfFile: "tvos/Runner/TVAssetResourceLoader.swift",
      encoding: .utf8
    )
    let cancellationHandler = try method(
      in: source,
      startingAt: "didCancel loadingRequest:",
      endingAt: "\n  func urlSession("
    )
    expect(
      !cancellationHandler.contains("finishLoading"),
      "AVFoundation-cancelled requests must not be finished again"
    )

    let dataCallback = try method(
      in: source,
      startingAt: "didReceive data: Data",
      endingAt: "\n  func urlSession("
    )
    expect(
      dataCallback.contains("loadingRequest.isCancelled"),
      "Queued data callbacks must ignore cancelled AVFoundation requests"
    )

    let invalidation = try method(
      in: source,
      startingAt: "func invalidate()",
      endingAt: "\n  func resourceLoader("
    )
    expect(
      invalidation.contains("!pending.loadingRequest.isCancelled"),
      "Invalidation must not finish requests AVFoundation already cancelled"
    )

    let completionCallback = try method(
      in: source,
      startingAt: "didCompleteWithError error: Error?",
      endingAt: "\n  private static func requestedRange("
    )
    let cancellationChecks =
      completionCallback.components(
        separatedBy: "pending.loadingRequest.isCancelled"
      ).count - 1
    expect(
      cancellationChecks >= 2,
      "Playlist completion must recheck cancellation immediately before responding"
    )
  }

  private static func method(in source: String, startingAt start: String, endingAt end: String)
    throws -> String
  {
    guard let startRange = source.range(of: start),
      let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex)
    else {
      throw NSError(domain: "TVAssetResourceLoaderTests", code: 1)
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
  }

  private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: \(message)") }
  }
}
