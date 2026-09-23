#if os(macOS)
import AppKit
import XCTest
@testable import opendoc

final class AppIconTests: XCTestCase {
    func testAppBundleContainsItsDeclaredIcon() throws {
        let bundle = Bundle(for: DockStore.self)
        let iconFile = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String)
        let filename = iconFile as NSString
        let iconURL = try XCTUnwrap(bundle.url(
            forResource: filename.deletingPathExtension,
            withExtension: filename.pathExtension.isEmpty ? "icns" : filename.pathExtension
        ))
        let image = try XCTUnwrap(NSImage(contentsOf: iconURL))
        XCTAssertTrue(image.isValid, "The installed app must have a decodable icon.")
        // Xcode stores larger representations in Assets.car, separately from the ICNS.
        let iconName = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String)
        let catalogImage = try XCTUnwrap(bundle.image(forResource: iconName))
        XCTAssertTrue(catalogImage.isValid, "The app icon must also resolve from the asset catalog.")
    }
}
#endif
