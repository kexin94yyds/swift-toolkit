//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

@testable import ReadiumNavigator
import ReadiumShared
import UIKit
import XCTest

final class EPUBSelectionPayloadTests: XCTestCase {
    func testParsesCompleteSelectionPayload() throws {
        let payload = try XCTUnwrap(EPUBSelectionPayload(body: [
            "href": "chapter.xhtml",
            "locations": [
                "domRange": [
                    "start": [
                        "cssSelector": "#target",
                        "textNodeIndex": 0,
                        "charOffset": 1,
                    ],
                    "end": [
                        "cssSelector": "#target",
                        "textNodeIndex": 0,
                        "charOffset": 4,
                    ],
                ],
            ],
            "text": ["highlight": "alu"],
            "rect": [
                "left": NSNumber(value: 10.0),
                "top": NSNumber(value: 20.0),
                "width": NSNumber(value: 30.0),
                "height": NSNumber(value: 40.0),
            ],
        ]))

        XCTAssertEqual(payload.href.string, "chapter.xhtml")
        XCTAssertEqual(payload.text.highlight, "alu")
        XCTAssertNotNil(payload.locations.domRange)
        XCTAssertEqual(payload.frame, CGRect(x: 10, y: 20, width: 30, height: 40))
    }

    func testAcceptsLegacyPayloadWithoutLocations() throws {
        let payload = try XCTUnwrap(EPUBSelectionPayload(body: [
            "href": "chapter.xhtml",
            "text": ["highlight": "value"],
            "rect": ["left": 0.0, "top": 0.0, "width": 1.0, "height": 1.0],
        ]))

        XCTAssertTrue(payload.locations.isEmpty)
    }

    func testRejectsDOMRangeWithoutEnd() {
        XCTAssertNil(EPUBSelectionPayload(body: [
            "href": "chapter.xhtml",
            "locations": [
                "domRange": [
                    "start": [
                        "cssSelector": "#target",
                        "textNodeIndex": 0,
                        "charOffset": 1,
                    ],
                ],
            ],
            "text": ["highlight": "value"],
            "rect": ["left": 0.0, "top": 0.0, "width": 1.0, "height": 1.0],
        ]))
    }

    func testRejectsInvalidDOMRangePoint() {
        XCTAssertNil(EPUBSelectionPayload(body: [
            "href": "chapter.xhtml",
            "locations": [
                "domRange": [
                    "start": [
                        "cssSelector": "#target",
                        "textNodeIndex": -1,
                        "charOffset": 1,
                    ],
                    "end": [
                        "cssSelector": "#target",
                        "textNodeIndex": 0,
                        "charOffset": 4,
                    ],
                ],
            ],
            "text": ["highlight": "value"],
            "rect": ["left": 0.0, "top": 0.0, "width": 1.0, "height": 1.0],
        ]))
    }

    func testRejectsInvalidDOMRangeEndPoint() {
        XCTAssertNil(EPUBSelectionPayload(body: [
            "href": "chapter.xhtml",
            "locations": [
                "domRange": [
                    "start": [
                        "cssSelector": "#target",
                        "textNodeIndex": 0,
                        "charOffset": 1,
                    ],
                    "end": [
                        "cssSelector": "#target",
                        "textNodeIndex": 0,
                        "charOffset": -1,
                    ],
                ],
            ],
            "text": ["highlight": "value"],
            "rect": ["left": 0.0, "top": 0.0, "width": 1.0, "height": 1.0],
        ]))
    }

    func testRejectsInvalidHref() {
        XCTAssertNil(EPUBSelectionPayload(body: [
            "href": "http://[",
            "text": ["highlight": "value"],
            "rect": ["left": 0.0, "top": 0.0, "width": 1.0, "height": 1.0],
        ]))
    }

    func testMakesLocatorForPayloadHrefWhenCurrentLocationIsStale() throws {
        let payload = try XCTUnwrap(EPUBSelectionPayload(body: [
            "href": "second.xhtml",
            "locations": [
                "domRange": [
                    "start": [
                        "cssSelector": "#target",
                        "textNodeIndex": 0,
                        "charOffset": 1,
                    ],
                    "end": [
                        "cssSelector": "#target",
                        "textNodeIndex": 0,
                        "charOffset": 4,
                    ],
                ],
            ],
            "text": ["highlight": "alu"],
            "rect": ["left": 0.0, "top": 0.0, "width": 1.0, "height": 1.0],
        ]))
        let readingOrder = [
            Link(href: "first.xhtml", mediaType: .xhtml),
            Link(href: "second.xhtml", mediaType: .xhtml),
        ]
        let staleLocation = Locator(
            href: AnyURL(string: "first.xhtml")!,
            mediaType: .xhtml,
            locations: .init(progression: 0.8)
        )

        let locator = try XCTUnwrap(payload.makeLocator(
            in: readingOrder,
            baseLocator: staleLocation
        ))

        XCTAssertEqual(locator.href.string, "second.xhtml")
        XCTAssertNil(locator.locations.progression)
        XCTAssertNotNil(locator.locations.domRange)
        XCTAssertEqual(locator.text.highlight, "alu")
    }

    func testPreservesPositionForThePayloadResource() throws {
        let payload = try XCTUnwrap(EPUBSelectionPayload(body: [
            "href": "second.xhtml",
            "text": ["highlight": "value"],
            "rect": ["left": 0.0, "top": 0.0, "width": 1.0, "height": 1.0],
        ]))
        let readingOrder = [
            Link(href: "first.xhtml", mediaType: .xhtml),
            Link(href: "second.xhtml", mediaType: .xhtml),
        ]
        let resourceLocator = Locator(
            href: AnyURL(string: "second.xhtml")!,
            mediaType: .xhtml,
            locations: .init(
                progression: 0.25,
                totalProgression: 0.75,
                position: 12
            )
        )

        let locator = try XCTUnwrap(payload.makeLocator(
            in: readingOrder,
            baseLocator: resourceLocator
        ))

        XCTAssertEqual(locator.href.string, "second.xhtml")
        XCTAssertEqual(locator.locations.progression, 0.25)
        XCTAssertEqual(locator.locations.totalProgression, 0.75)
        XCTAssertEqual(locator.locations.position, 12)
        XCTAssertEqual(locator.text.highlight, "value")
    }

    func testPreservesProgressionForTheSameResource() throws {
        let payload = try XCTUnwrap(EPUBSelectionPayload(body: [
            "href": "chapter.xhtml",
            "text": ["highlight": "value"],
            "rect": ["left": 0.0, "top": 0.0, "width": 1.0, "height": 1.0],
        ]))
        let readingOrder = [Link(href: "chapter.xhtml", mediaType: .xhtml)]
        let currentLocation = Locator(
            href: AnyURL(string: "chapter.xhtml")!,
            mediaType: .xhtml,
            locations: .init(
                progression: 0.4,
                otherLocations: [
                    "domRange": [
                        "start": [
                            "cssSelector": "#stale",
                            "textNodeIndex": 0,
                            "charOffset": 0,
                        ],
                    ],
                ]
            )
        )

        let locator = try XCTUnwrap(payload.makeLocator(
            in: readingOrder,
            baseLocator: currentLocation
        ))

        XCTAssertEqual(locator.locations.progression, 0.4)
        XCTAssertNil(locator.locations.domRange)
        XCTAssertEqual(locator.text.highlight, "value")
    }
}
