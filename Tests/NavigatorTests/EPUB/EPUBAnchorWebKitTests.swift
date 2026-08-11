//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

@testable import ReadiumNavigator
@preconcurrency import WebKit
import XCTest

@MainActor
final class EPUBAnchorWebKitTests: XCTestCase {
    func testSelectionPayloadFromXHTMLDocument() async throws {
        let harness = try await WebKitAnchorHarness(
            html: """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Fixture</title></head>
            <body><p>这是一个真机 EPUB 选区。</p></body></html>
            """,
            mimeType: "application/xhtml+xml"
        )

        let selectionExpectation = expectation(description: "XHTML selection payload")
        harness.messageSink.selectionExpectation = selectionExpectation

        try await harness.evaluate("""
        (() => {
          const node = document.querySelector("p").firstChild;
          const range = document.createRange();
          range.setStart(node, 0);
          range.setEnd(node, 4);
          const selection = window.getSelection();
          selection.removeAllRanges();
          selection.addRange(range);
          document.dispatchEvent(new Event("selectionchange"));
        })();
        """)
        await fulfillment(of: [selectionExpectation], timeout: 2)

        let payload = try XCTUnwrap(harness.messageSink.selectionBodies.last)
        let locations = try XCTUnwrap(payload["locations"] as? [String: Any])
        let domRange = try XCTUnwrap(locations["domRange"] as? [String: Any])
        XCTAssertNotNil(domRange["start"])
        XCTAssertNotNil(domRange["end"])
    }

    func testDragEndingOnDecorationForwardsTerminalPointerEvent() async throws {
        let harness = try await WebKitAnchorHarness(
            html: """
            <!doctype html>
            <html><body><p id="target">highlight target</p></body></html>
            """
        )

        let pointerExpectation = expectation(description: "Pointer down and terminal event")
        pointerExpectation.expectedFulfillmentCount = 2
        harness.messageSink.pointerExpectation = pointerExpectation

        _ = try await harness.evaluate("""
        (() => {
          readium.registerDecorationTemplates({
            anchorTest: { layout: "bounds", width: "wrap" },
          });
          const group = readium.getDecorations("pointer-terminal-webkit");
          group.add({
            id: "target",
            locator: {
              href: "chapter.xhtml",
              type: "application/xhtml+xml",
              locations: {
                domRange: {
                  start: { cssSelector: "#target", textNodeIndex: 0, charOffset: 0 },
                  end: { cssSelector: "#target", textNodeIndex: 0, charOffset: 9 },
                },
              },
              text: { highlight: "highlight" },
            },
            style: "anchorTest",
            element: "<div></div>",
          });
          group.setActivable();
        })();
        """)
        try await Task.sleep(nanoseconds: 100_000_000)

        _ = try await harness.evaluate("""
        (() => {
          const group = readium.getDecorations("pointer-terminal-webkit");
          const element = group.items[0].clickableElements[0];
          const rect = element.getBoundingClientRect();
          document.body.dispatchEvent(new PointerEvent("pointerdown", {
            bubbles: true,
            pointerId: 42,
            pointerType: "touch",
            clientX: rect.right + 40,
            clientY: rect.bottom + 40,
          }));
          document.body.dispatchEvent(new PointerEvent("pointerup", {
            bubbles: true,
            pointerId: 42,
            pointerType: "touch",
            clientX: rect.left + rect.width / 2,
            clientY: rect.top + rect.height / 2,
          }));
        })();
        """)

        await fulfillment(of: [pointerExpectation], timeout: 2)
        XCTAssertEqual(
            harness.messageSink.pointerBodies.compactMap { $0["phase"] as? String },
            ["down", "up"]
        )
    }

    func testEightRepeatedSelectionsResolveToDistinctDOMRanges() async throws {
        let harness = try await WebKitAnchorHarness(
            html: """
            <!doctype html>
            <html><head><style>p { line-height: 24px; }</style></head>
            <body><p id="repeated">same<br>same<br>same<br>same<br>same<br>same<br>same<br>same</p></body></html>
            """
        )

        let selectionExpectation = expectation(description: "Eight selection payloads")
        selectionExpectation.expectedFulfillmentCount = 8
        harness.messageSink.selectionExpectation = selectionExpectation

        try await harness.evaluate("""
        (() => {
          const parent = document.querySelector("#repeated");
          let ordinal = 0;
          const selectNext = () => {
            const node = parent.childNodes[ordinal * 2];
            const range = document.createRange();
            range.setStart(node, 0);
            range.setEnd(node, 4);
            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
            document.dispatchEvent(new Event("selectionchange"));
            ordinal += 1;
            if (ordinal < 8) {
              setTimeout(selectNext, 100);
            }
          };
          selectNext();
        })();
        """)
        await fulfillment(of: [selectionExpectation], timeout: 3)

        let payloads = harness.messageSink.selectionBodies
        XCTAssertEqual(payloads.count, 8)
        let locators = try payloads.map(makeLocator(from:))
        let locatorJSON = try jsonString(locators)

        let result = try await harness.evaluate("""
        (() => {
          readium.registerDecorationTemplates({
            anchorTest: { layout: "bounds", width: "wrap" },
          });
          const group = readium.getDecorations("exact-anchor-webkit");
          const parent = document.querySelector("#repeated");
          const locators = \(locatorJSON);
          window.__anchorTestLocators = locators;
          locators.forEach((locator, ordinal) => group.add({
            id: `anchor-${ordinal}`,
            locator,
            style: "anchorTest",
            element: "<div></div>",
          }));
          return group.items.map((item) => ({
            id: item.decoration.id,
            startIndex: Array.from(parent.childNodes).indexOf(item.range.startContainer),
            text: item.range.toString(),
            top: item.range.getBoundingClientRect().top,
          }));
        })();
        """)

        let resolved = try XCTUnwrap(result as? [[String: Any]])
        XCTAssertEqual(resolved.count, 8)
        XCTAssertEqual(resolved.compactMap { $0["id"] as? String }, (0 ..< 8).map { "anchor-\($0)" })
        XCTAssertEqual(resolved.compactMap { ($0["startIndex"] as? NSNumber)?.intValue }, [0, 2, 4, 6, 8, 10, 12, 14])
        XCTAssertEqual(resolved.compactMap { $0["text"] as? String }, Array(repeating: "same", count: 8))
        let resolvedTops = resolved.compactMap { ($0["top"] as? NSNumber)?.doubleValue }
        XCTAssertEqual(resolvedTops.count, 8)
        XCTAssertEqual(Set(resolvedTops).count, 8)

        let ordinalActivationExpectation = expectation(description: "Fourth, fifth and sixth occurrences activated")
        ordinalActivationExpectation.expectedFulfillmentCount = 3
        harness.messageSink.decorationExpectation = ordinalActivationExpectation
        let ordinalActivationResult = try await harness.evaluate("""
        (() => {
          const group = readium.getDecorations("exact-anchor-webkit");
          group.setActivable();
          window.getSelection().removeAllRanges();
          document.dispatchEvent(new Event("selectionchange"));

          return [3, 4, 5].map((ordinal) => {
            const item = group.items.find((candidate) => candidate.decoration.id === `anchor-${ordinal}`);
            const element = item?.clickableElements?.[0];
            if (!element) return false;
            const left = 10000 + ordinal * 2000;
            const rect = {
              bottom: 11000,
              height: 1000,
              left,
              right: left + 1000,
              top: 10000,
              width: 1000,
              x: left,
              y: 10000,
              toJSON() {
                return {
                  bottom: this.bottom,
                  height: this.height,
                  left: this.left,
                  right: this.right,
                  top: this.top,
                  width: this.width,
                  x: this.x,
                  y: this.y,
                };
              },
            };
            element.getBoundingClientRect = () => rect;
            return document.body.dispatchEvent(new MouseEvent("click", {
              bubbles: true,
              clientX: rect.left + rect.width / 2,
              clientY: rect.top + rect.height / 2,
            }));
          });
        })();
        """)
        XCTAssertEqual(
            (ordinalActivationResult as? [NSNumber])?.map(\.boolValue),
            [true, true, true]
        )
        await fulfillment(of: [ordinalActivationExpectation], timeout: 3)
        XCTAssertEqual(
            harness.messageSink.decorationBodies.suffix(3).compactMap { $0["id"] as? String },
            ["anchor-3", "anchor-4", "anchor-5"]
        )

        let lifecycleResult = try await harness.evaluate("""
        (() => {
          const group = readium.getDecorations("exact-anchor-webkit");
          const parent = document.querySelector("#repeated");
          group.update({
            id: "anchor-4",
            locator: window.__anchorTestLocators[4],
            style: "anchorTest",
            element: "<div data-version='updated'></div>",
          });
          group.remove("anchor-3");
          document.body.style.fontSize = "28px";
          document.body.style.color = "rgb(30, 30, 30)";
          document.documentElement.style.columnWidth = "390px";
          document.documentElement.style.columnGap = "0px";
          group.requestLayout();

          const saved = group.items.map((item) => item.decoration);
          group.clear();
          saved.forEach((decoration) => group.add(decoration));
          group.requestLayout();
          group.setActivable();
          window.getSelection().removeAllRanges();
          document.dispatchEvent(new Event("selectionchange"));

          return group.items.map((item) => ({
            id: item.decoration.id,
            startIndex: Array.from(parent.childNodes).indexOf(item.range.startContainer),
            text: item.range.toString(),
            version: item.decoration.element.includes("data-version='updated'") ? "updated" : "original",
          })).sort((left, right) => left.startIndex - right.startIndex);
        })();
        """)

        let restored = try XCTUnwrap(lifecycleResult as? [[String: Any]])
        XCTAssertEqual(restored.compactMap { $0["id"] as? String }, [
            "anchor-0", "anchor-1", "anchor-2", "anchor-4", "anchor-5", "anchor-6", "anchor-7",
        ])
        XCTAssertEqual(restored.compactMap { ($0["startIndex"] as? NSNumber)?.intValue }, [0, 2, 4, 8, 10, 12, 14])
        XCTAssertEqual(restored.compactMap { $0["text"] as? String }, Array(repeating: "same", count: 7))
        XCTAssertEqual(restored.first { $0["id"] as? String == "anchor-4" }?["version"] as? String, "updated")

        let activationExpectation = expectation(description: "Updated fifth occurrence activated")
        harness.messageSink.decorationExpectation = activationExpectation
        try await Task.sleep(nanoseconds: 100_000_000)
        let dispatchResult = try await harness.evaluate("""
        (() => {
          const group = readium.getDecorations("exact-anchor-webkit");
          const item = group.items.find((candidate) => candidate.decoration.id === "anchor-4");
          const element = item?.clickableElements?.[0];
          if (!element) return { dispatched: false, reason: "missing-element" };
          const rect = {
            bottom: 24000,
            height: 1000,
            left: 12000,
            right: 13000,
            top: 23000,
            width: 1000,
            x: 12000,
            y: 23000,
            toJSON() {
              return {
                bottom: this.bottom,
                height: this.height,
                left: this.left,
                right: this.right,
                top: this.top,
                width: this.width,
                x: this.x,
                y: this.y,
              };
            },
          };
          element.getBoundingClientRect = () => rect;
          const selectionCollapsed = window.getSelection().isCollapsed;
          const dispatched = document.body.dispatchEvent(new MouseEvent("click", {
            bubbles: true,
            clientX: rect.left + rect.width / 2,
            clientY: rect.top + rect.height / 2,
          }));
          return {
            dispatched,
            elementConnected: element.isConnected,
            selectionCollapsed,
          };
        })();
        """)
        let diagnostics = try XCTUnwrap(dispatchResult as? [String: Any])
        XCTAssertEqual(diagnostics["dispatched"] as? Bool, true)
        XCTAssertEqual(diagnostics["selectionCollapsed"] as? Bool, true)
        await fulfillment(of: [activationExpectation], timeout: 3)
        let activation = try XCTUnwrap(harness.messageSink.decorationBodies.last)
        XCTAssertEqual(activation["id"] as? String, "anchor-4")
        XCTAssertEqual(activation["group"] as? String, "exact-anchor-webkit")

        let reopenedHarness = try await WebKitAnchorHarness(
            html: """
            <!doctype html>
            <html><head><style>p { line-height: 24px; }</style></head>
            <body><p id="repeated">same<br>same<br>same<br>same<br>same<br>same<br>same<br>same</p></body></html>
            """
        )
        let reopenedResult = try await reopenedHarness.evaluate("""
        (() => {
          readium.registerDecorationTemplates({
            anchorTest: { layout: "bounds", width: "wrap" },
          });
          const group = readium.getDecorations("reopened-exact-anchor-webkit");
          const parent = document.querySelector("#repeated");
          const locators = \(locatorJSON);
          locators.forEach((locator, ordinal) => group.add({
            id: `anchor-${ordinal}`,
            locator,
            style: "anchorTest",
            element: "<div></div>",
          }));
          return group.items.map((item) => ({
            id: item.decoration.id,
            startIndex: Array.from(parent.childNodes).indexOf(item.range.startContainer),
          }));
        })();
        """)
        let reopened = try XCTUnwrap(reopenedResult as? [[String: Any]])
        XCTAssertEqual(reopened.compactMap { $0["id"] as? String }, (0 ..< 8).map { "anchor-\($0)" })
        XCTAssertEqual(reopened.compactMap { ($0["startIndex"] as? NSNumber)?.intValue }, [0, 2, 4, 6, 8, 10, 12, 14])
    }

    func testAmbiguousTextQuoteDecorationFailsClosed() async throws {
        let harness = try await WebKitAnchorHarness(
            html: """
            <!doctype html>
            <html><body><p>same<br>same<br>same<br>same</p></body></html>
            """
        )

        let result = try await harness.evaluate("""
        (() => {
          readium.registerDecorationTemplates({
            anchorTest: { layout: "bounds", width: "wrap" },
          });
          const group = readium.getDecorations("ambiguous-anchor-webkit");
          group.add({
            id: "ambiguous",
            locator: {
              href: "chapter.xhtml",
              type: "application/xhtml+xml",
              locations: {},
              text: { highlight: "same" },
            },
            style: "anchorTest",
            element: "<div></div>",
          });
          group.add({
            id: "non-unique-root",
            locator: {
              href: "chapter.xhtml",
              type: "application/xhtml+xml",
              locations: { cssSelector: "p" },
              text: { highlight: "same" },
            },
            style: "anchorTest",
            element: "<div></div>",
          });
          return group.items.length;
        })();
        """)

        XCTAssertEqual((result as? NSNumber)?.intValue, 0)
    }

    func testWritingSystemsAndElementBoundariesRoundTrip() async throws {
        let harness = try await WebKitAnchorHarness(
            html: """
            <!doctype html>
            <html><body>
              <p id="cjk"><span>前</span><ruby>漢<rt>かん</rt></ruby><span>後</span></p>
              <p id="rtl" dir="rtl">אבגדה</p>
              <p id="vertical" style="writing-mode: vertical-rl">縦書き本文</p>
              <p id="element-boundary"><span>left</span><em>right</em></p>
            </body></html>
            """
        )
        let selectionExpectation = expectation(description: "Writing-system selection payloads")
        selectionExpectation.expectedFulfillmentCount = 4
        harness.messageSink.selectionExpectation = selectionExpectation

        try await harness.evaluate("""
        (() => {
          const selections = [
            () => {
              const parent = document.querySelector("#cjk");
              const range = document.createRange();
              range.setStart(parent.firstElementChild.firstChild, 0);
              range.setEnd(parent.lastElementChild.firstChild, 1);
              return range;
            },
            () => {
              const text = document.querySelector("#rtl").firstChild;
              const range = document.createRange();
              range.setStart(text, 1);
              range.setEnd(text, 4);
              return range;
            },
            () => {
              const text = document.querySelector("#vertical").firstChild;
              const range = document.createRange();
              range.setStart(text, 1);
              range.setEnd(text, 4);
              return range;
            },
            () => {
              const parent = document.querySelector("#element-boundary");
              const range = document.createRange();
              range.setStart(parent, 0);
              range.setEnd(parent, parent.childNodes.length);
              return range;
            },
          ];

          let ordinal = 0;
          const selectNext = () => {
            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(selections[ordinal]());
            document.dispatchEvent(new Event("selectionchange"));
            ordinal += 1;
            if (ordinal < selections.length) setTimeout(selectNext, 100);
          };
          selectNext();
        })();
        """)
        await fulfillment(of: [selectionExpectation], timeout: 3)

        let payloads = harness.messageSink.selectionBodies
        XCTAssertEqual(payloads.count, 4)
        let locators = try payloads.map(makeLocator(from:))
        let expectedText = payloads.compactMap { ($0["text"] as? [String: Any])?["highlight"] as? String }
        XCTAssertEqual(expectedText.count, 4)
        let locatorJSON = try jsonString(locators)

        let result = try await harness.evaluate("""
        (() => {
          readium.registerDecorationTemplates({
            anchorTest: { layout: "bounds", width: "wrap" },
          });
          const group = readium.getDecorations("writing-system-webkit");
          const locators = \(locatorJSON);
          locators.forEach((locator, ordinal) => group.add({
            id: `writing-${ordinal}`,
            locator,
            style: "anchorTest",
            element: "<div></div>",
          }));
          return group.items.map((item) => item.range.toString());
        })();
        """)

        XCTAssertEqual(result as? [String], expectedText)
    }

    func testNonPersistentSelectionFailsClosed() async throws {
        let harness = try await WebKitAnchorHarness(
            html: """
            <!doctype html>
            <html><body><p id="target">value</p></body></html>
            """
        )
        let selectionExpectation = expectation(description: "Null selection payload")
        harness.messageSink.nullSelectionExpectation = selectionExpectation

        try await harness.evaluate("""
        (() => {
          const target = document.querySelector("#target");
          target.id = "x".repeat(5000);
          const range = document.createRange();
          range.selectNodeContents(target);
          const selection = window.getSelection();
          selection.removeAllRanges();
          selection.addRange(range);
          document.dispatchEvent(new Event("selectionchange"));
        })();
        """)
        await fulfillment(of: [selectionExpectation], timeout: 2)

        XCTAssertEqual(harness.messageSink.nullSelectionCount, 1)
        XCTAssertTrue(harness.messageSink.selectionBodies.isEmpty)
    }

    func testCrossElementEmojiSelectionRoundTrips() async throws {
        let harness = try await WebKitAnchorHarness(
            html: """
            <!doctype html>
            <html><body><p id="complex"><span>A😀B</span><em>right</em></p></body></html>
            """
        )
        let selectionExpectation = expectation(description: "Complex selection payload")
        harness.messageSink.selectionExpectation = selectionExpectation

        try await harness.evaluate("""
        (() => {
          const range = document.createRange();
          range.setStart(document.querySelector("span").firstChild, 1);
          range.setEnd(document.querySelector("em").firstChild, 3);
          const selection = window.getSelection();
          selection.removeAllRanges();
          selection.addRange(range);
          document.dispatchEvent(new Event("selectionchange"));
        })();
        """)
        await fulfillment(of: [selectionExpectation], timeout: 2)

        let payload = try XCTUnwrap(harness.messageSink.selectionBodies.last)
        let locatorJSON = try jsonString(makeLocator(from: payload))
        let result = try await harness.evaluate("""
        (() => {
          readium.registerDecorationTemplates({
            anchorTest: { layout: "bounds", width: "wrap" },
          });
          const group = readium.getDecorations("complex-anchor-webkit");
          group.add({
            id: "complex",
            locator: \(locatorJSON),
            style: "anchorTest",
            element: "<div></div>",
          });
          const item = group.items[0];
          return item ? {
            text: item.range.toString(),
            startOffset: item.range.startOffset,
            endOffset: item.range.endOffset,
          } : null;
        })();
        """)

        let resolved = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(resolved["text"] as? String, "😀Brig")
        XCTAssertEqual((resolved["startOffset"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((resolved["endOffset"] as? NSNumber)?.intValue, 3)
    }

    private func makeLocator(from payload: [String: Any]) throws -> [String: Any] {
        try [
            "href": XCTUnwrap(payload["href"]),
            "type": "application/xhtml+xml",
            "locations": XCTUnwrap(payload["locations"]),
            "text": XCTUnwrap(payload["text"]),
        ]
    }

    private func jsonString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}

@MainActor
private final class WebKitAnchorHarness: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let messageSink = WebKitMessageSink()

    private var navigationContinuation: CheckedContinuation<Void, Error>?

    init(html: String, mimeType: String? = nil) async throws {
        let controller = WKUserContentController()
        for name in [
            "decorationActivated",
            "keyEventReceived",
            "log",
            "logError",
            "pointerEventReceived",
            "progressionChanged",
            "selectionChanged",
            "spreadLoaded",
            "spreadLoadStarted",
            "tap",
        ] {
            controller.add(messageSink, name: name)
        }
        controller.addUserScript(WKUserScript(
            source: EPUBSpreadView.loadScript(named: "readium-reflowable"),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)

        super.init()
        webView.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation = continuation
            let baseURL = URL(string: "https://example.invalid/")!
            if let mimeType {
                webView.load(
                    Data(html.utf8),
                    mimeType: mimeType,
                    characterEncodingName: "utf-8",
                    baseURL: baseURL
                )
            } else {
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        }
        try await evaluate("readium.link = { href: 'chapter.xhtml' };")
    }

    func evaluate(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }
}

@MainActor
private final class WebKitMessageSink: NSObject, WKScriptMessageHandler {
    var selectionBodies: [[String: Any]] = []
    var decorationBodies: [[String: Any]] = []
    var pointerBodies: [[String: Any]] = []
    var nullSelectionCount = 0
    weak var selectionExpectation: XCTestExpectation?
    weak var nullSelectionExpectation: XCTestExpectation?
    weak var decorationExpectation: XCTestExpectation?
    weak var pointerExpectation: XCTestExpectation?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "selectionChanged":
            if message.body is NSNull {
                nullSelectionCount += 1
                nullSelectionExpectation?.fulfill()
                return
            }
            guard let body = message.body as? [String: Any] else { return }
            selectionBodies.append(body)
            selectionExpectation?.fulfill()
        case "decorationActivated":
            guard let body = message.body as? [String: Any] else { return }
            decorationBodies.append(body)
            decorationExpectation?.fulfill()
        case "pointerEventReceived":
            guard let body = message.body as? [String: Any] else { return }
            pointerBodies.append(body)
            pointerExpectation?.fulfill()
        default:
            break
        }
    }
}
