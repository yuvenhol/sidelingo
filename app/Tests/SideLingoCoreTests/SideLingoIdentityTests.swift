import XCTest
@testable import SideLingoCore

final class SideLingoIdentityTests: XCTestCase {
    func testCanonicalIdentityAndFramedProtocol() {
        XCTAssertEqual(SideLingoIdentity.productName, "SideLingo")
        XCTAssertEqual(SideLingoIdentity.coreModuleName, "SideLingoCore")
        XCTAssertEqual(SideLingoIdentity.executableName, "SideLingo")
        XCTAssertEqual(SideLingoIdentity.bundleIdentifier, "dev.kris.sidelingo")
        XCTAssertEqual(SideLingoIdentity.applicationSupportDirectoryName, "SideLingo")
        XCTAssertEqual(SideLingoIdentity.statusItemTitle, "SL")

        XCTAssertEqual(CompanionFramedProtocol.markerPrefix, "<<<SIDELINGO::")
        XCTAssertEqual(CompanionFramedProtocol.primaryMarker, "<<<SIDELINGO::PRIMARY>>>")
        XCTAssertEqual(
            CompanionFramedProtocol.secondaryTitleMarker,
            "<<<SIDELINGO::SECONDARY_TITLE>>>"
        )
        XCTAssertEqual(CompanionFramedProtocol.secondaryMarker, "<<<SIDELINGO::SECONDARY>>>")
        XCTAssertEqual(CompanionFramedProtocol.endMarker, "<<<SIDELINGO::END>>>")
    }
}
