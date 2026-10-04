import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

  func testCanonicalLanguageCodeMapsVisionTagsToCatalogCodes() {
    XCTAssertEqual(MangaTranslationBridge.canonicalLanguageCode("ja-JP"), "ja")
    XCTAssertEqual(MangaTranslationBridge.canonicalLanguageCode("zh-Hans"), "zh")
    XCTAssertEqual(MangaTranslationBridge.canonicalLanguageCode("zh-Hant"), "zh")
    XCTAssertEqual(MangaTranslationBridge.canonicalLanguageCode("fil-PH"), "tl")
    XCTAssertEqual(MangaTranslationBridge.canonicalLanguageCode("jw-ID"), "jv")
    XCTAssertEqual(MangaTranslationBridge.canonicalLanguageCode("nb-NO"), "no")
    XCTAssertEqual(MangaTranslationBridge.canonicalLanguageCode("nn-NO"), "no")
    XCTAssertNil(MangaTranslationBridge.canonicalLanguageCode("xyz-ZZ"))
  }

  func testVisionBoundsConvertFromBottomLeftToTopLeftExactlyOnce() {
    let converted = MangaTranslationBridge.flutterBounds(
      fromVision: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
    )

    XCTAssertEqual(converted.minX, 0.1, accuracy: 0.000001)
    XCTAssertEqual(converted.minY, 0.4, accuracy: 0.000001)
    XCTAssertEqual(converted.maxX, 0.4, accuracy: 0.000001)
    XCTAssertEqual(converted.maxY, 0.8, accuracy: 0.000001)
  }

}
