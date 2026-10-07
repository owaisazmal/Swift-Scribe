import XCTest
@testable import OwlLuna

@MainActor
final class LaunchOverlayTests: XCTestCase {
    /// The owl plays only for the first scene of a real launch: not for UI tests, not under XCTest, not for a second window.
    func testGatePlaysOnlyForTheFirstSceneOfARealLaunch() {
        XCTAssertTrue(LaunchAnimation.isEnabled(arguments: ["OwlLuna"], underTest: false, firstScene: true))
        XCTAssertFalse(LaunchAnimation.isEnabled(arguments: ["OwlLuna", "-storageRoot", "Launch"], underTest: false, firstScene: true))
        XCTAssertFalse(LaunchAnimation.isEnabled(arguments: ["OwlLuna", "-skipLaunchAnimation"], underTest: false, firstScene: true))
        XCTAssertFalse(LaunchAnimation.isEnabled(arguments: ["OwlLuna"], underTest: true, firstScene: true))
        XCTAssertFalse(LaunchAnimation.isEnabled(arguments: ["OwlLuna"], underTest: false, firstScene: false))
    }

    func testGateIsOffInTheTestProcess() {
        XCTAssertFalse(LaunchAnimation.isEnabled)
        XCTAssertFalse(LaunchAnimation.isEnabled, "and stays off once the first scene is claimed")
    }

    func testEveryGroupHasPartsInBothLaunchPalettes() {
        for (name, groups) in [("light", OwlLunaMarkGroups.launchLight), ("dark", .launchDark)] {
            XCTAssertNotNil(groups.skyTop, "\(name) tile")
            XCTAssertNotNil(groups.glow, "\(name) halo")
            for group in OwlLunaMarkGroups.Group.allCases {
                XCTAssertFalse(groups.parts(group).isEmpty, "\(name) \(group)")
            }
        }
        XCTAssertNotEqual(OwlLunaMarkGroups.launchLight.skyTop, OwlLunaMarkGroups.launchDark.skyTop)
    }
}
