//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ReadiumShared
import UIKit

/// Selection information received from the EPUB JavaScript layer.
struct EPUBSelectionPayload {
    let href: AnyURL
    let locations: Locator.Locations
    let text: Locator.Text
    let frame: CGRect

    init(href: AnyURL, locations: Locator.Locations, text: Locator.Text, frame: CGRect) {
        self.href = href
        self.locations = locations
        self.text = text
        self.frame = frame
    }

    init?(body: Any) {
        guard
            let selection = body as? [String: Any],
            let hrefString = selection["href"] as? String,
            let href = AnyURL(string: hrefString),
            let text = try? Locator.Text(json: JSONValue(selection["text"])),
            let frame = CGRect(json: selection["rect"])
        else {
            return nil
        }

        let locations: Locator.Locations
        if let rawLocations = selection["locations"] {
            guard
                let json = JSONValue(rawLocations),
                let decoded = try? Locator.Locations(json: json)
            else {
                return nil
            }
            locations = decoded
        } else {
            locations = .init()
        }

        if let domRange = locations["domRange"] {
            guard
                locations.domRange != nil,
                Self.isValidPersistentDOMRange(domRange)
            else {
                return nil
            }
        }

        self.init(href: href, locations: locations, text: text, frame: frame)
    }

    private static func isValidPersistentDOMRange(_ value: JSONValue) -> Bool {
        guard
            let object = value.object,
            let start = object["start"],
            let end = object["end"]
        else {
            return false
        }
        return isValidPersistentDOMRangePoint(start)
            && isValidPersistentDOMRangePoint(end)
    }

    private static func isValidPersistentDOMRangePoint(_ value: JSONValue) -> Bool {
        guard
            let object = value.object,
            let cssSelector = object["cssSelector"]?.string,
            !cssSelector.isEmpty,
            let textNodeIndex = object["textNodeIndex"]?.integer,
            textNodeIndex >= 0,
            let charOffset = (object["charOffset"] ?? object["offset"])?.integer,
            charOffset >= 0
        else {
            return false
        }
        return true
    }

    func makeLocator(in readingOrder: ReadingOrder, baseLocator: Locator?) -> Locator? {
        guard let resourceIndex = readingOrder.firstIndexWithHREF(href) else {
            return nil
        }

        let link = readingOrder[resourceIndex]
        let locatorBase: Locator
        if
            let baseLocator,
            baseLocator.href.isEquivalentTo(link.url())
        {
            locatorBase = baseLocator
        } else {
            locatorBase = Locator(
                href: link.url(),
                mediaType: link.mediaType ?? .xhtml,
                title: link.title
            )
        }

        return locatorBase.copy(
            href: link.url(),
            locations: {
                $0.otherLocations.removeValue(forKey: "domRange")
                if let domRange = locations["domRange"] {
                    $0.otherLocations["domRange"] = domRange
                }
            },
            text: { $0 = text }
        )
    }
}
