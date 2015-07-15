import Foundation
import XCTest
import Storage
import Shared
import XCGLogger

private var log = XCGLogger.defaultInstance()

class TestFavicons : ProfileTest {
    func testFaviconProtocol() {
        withTestProfile { profile -> Void in
            let expectation = self.expectationWithDescription("asynchronous request")
            let favicon = Favicon(url: "favicon", type: IconType.Icon)
            let site = Site(url: "url", title: "")

            profile.favicons.addFavicon(favicon, forSite: site) >>== { id in
                // XCTAssertNotNil(id)
                return profile.favicons.getFaviconsForSite(site)
            } >>== { icons in
                XCTAssertEqual(icons.count, 1)
                println("Found icon \(icons[0])")
                // XCTAssert(favicon == icons[0]!, "Found correct favicon")

                var iconArray = icons.asArray().filter { return $0 != nil } as! [Favicon]
                profile.favicons.removeIcons(iconArray)
            // } >>== { success in
                expectation.fulfill()
            }
/*
            } >>== { success in
                expectation.fulfill()
            }
*/

            self.waitForExpectationsWithTimeout(10, handler: nil)
        }
    }

    func testFaviconManager() {

    }
}