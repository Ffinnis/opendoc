#if os(macOS)
import XCTest
@testable import opendoc

@MainActor
final class NativeWindowSupportTests: XCTestCase {
    private func dictionary(_ body: String) -> Data {
        Data("<dictionary><suite>\(body)</suite></dictionary>".utf8)
    }

    func testDetectsUnlistedAppsAndUsesCodesInsteadOfNames() {
        let data = dictionary("""
        <command name="make" code="corecrel"/>
        <class name="application" code="capp"><element type="window"/></class>
        <class name="window" code="WiND"/>
        """)
        XCTAssertEqual(NativeWindowSupport.command(in: data), "make new «class WiND»")
    }

    func testReadOnlyWindowsFallBackToWritableDocuments() {
        let data = dictionary("""
        <command name="make" code="corecrel"/>
        <class name="application" code="capp">
          <element type="window" access="r"/><element type="document"/>
        </class>
        <class name="window" code="cwin"/><class name="document" code="docu"/>
        """)
        XCTAssertEqual(NativeWindowSupport.command(in: data), "make new «class docu»")
    }

    func testRequiresCreationCommandAndWritableApplicationElement() {
        XCTAssertNil(NativeWindowSupport.command(in: dictionary("""
        <class name="application" code="capp"><element type="window"/></class>
        <class name="window" code="cwin"/>
        """)))
        XCTAssertNil(NativeWindowSupport.command(in: dictionary("""
        <command name="make" code="corecrel"/>
        <class name="application" code="capp"><element type="window" access="r"/></class>
        <class name="window" code="cwin"/>
        """)))
    }

    func testIncludesOnlyDeclaredStandardDictionary() {
        let standard = dictionary("""
        <command name="make" code="corecrel"/>
        <class name="application" code="capp"><element type="document"/></class>
        <class name="document" code="docu"/>
        """)
        let included = Data("""
        <dictionary xmlns:xi="http://www.w3.org/2003/XInclude">
          <xi:include href="file:///System/Library/ScriptingDefinitions/CocoaStandard.sdef"/>
        </dictionary>
        """.utf8)
        XCTAssertEqual(NativeWindowSupport.command(in: included, standard: standard), "make new «class docu»")
        XCTAssertNil(NativeWindowSupport.command(in: dictionary(""), standard: standard))
        XCTAssertNil(NativeWindowSupport.command(in: Data("not xml".utf8)))
    }

    func testInstalledFinderAndSafariDictionaries() {
        XCTAssertEqual(NativeWindowSupport.command(for: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")), "make new «class brow»")
        XCTAssertEqual(NativeWindowSupport.command(for: URL(fileURLWithPath: "/Applications/Safari.app")), "make new «class docu»")
    }
}
#endif
