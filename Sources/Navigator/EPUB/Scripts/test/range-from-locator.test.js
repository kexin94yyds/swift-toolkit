//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

// @vitest-environment jsdom

import { beforeEach, describe, expect, it } from "vitest";
import { getCurrentSelection, location2RangeInfo } from "../src/selection";
import { rangeFromLocator, resolveLocatorRange } from "../src/utils";

describe("EPUB locator range resolution", () => {
  beforeEach(() => {
    document.body.innerHTML =
      '<p id="repeated">same<br>same<br>same<br>same</p>';
  });

  it("prefers a standard DOM range over an ambiguous text quote", () => {
    const range = rangeFromLocator({
      locations: {
        domRange: {
          start: {
            cssSelector: "#repeated",
            textNodeIndex: 4,
            charOffset: 0,
          },
          end: {
            cssSelector: "#repeated",
            textNodeIndex: 4,
            charOffset: 4,
          },
        },
      },
      text: { highlight: "same" },
    });

    expect(range).not.toBeNull();
    const children = Array.from(document.querySelector("#repeated").childNodes);
    expect(children.indexOf(range.startContainer)).toBe(4);
    expect(range.startOffset).toBe(0);
    expect(children.indexOf(range.endContainer)).toBe(4);
    expect(range.endOffset).toBe(4);
  });

  it("does not silently choose the first ambiguous text quote", () => {
    const range = resolveLocatorRange(
      {
        locations: {},
        text: { highlight: "same" },
      },
      { requireUniqueTextQuote: true }
    ).range;

    expect(range).toBeNull();
  });

  it("rejects a non-unique text-quote root for decorations", () => {
    document.body.innerHTML = "<p>same</p><p>same</p>";
    const resolution = resolveLocatorRange(
      {
        locations: { cssSelector: "p" },
        text: { highlight: "same" },
      },
      { requireUniqueTextQuote: true }
    );

    expect(resolution).toEqual({
      range: null,
      method: null,
      reason: "root_selector_not_unique",
    });
  });

  it("keeps first-root compatibility for non-decoration navigation", () => {
    document.body.innerHTML = "<p>first same</p><p>second same</p>";
    const range = rangeFromLocator({
      locations: { cssSelector: "p" },
      text: { highlight: "same" },
    });

    expect(range).not.toBeNull();
    expect(range.startContainer.parentElement.textContent).toBe("first same");
  });

  it("keeps the legacy first-match fallback for non-decoration navigation", () => {
    const range = rangeFromLocator({
      locations: {},
      text: { highlight: "same" },
    });

    expect(range).not.toBeNull();
    expect(range.toString()).toBe("same");
  });

  it("reports an ambiguous text quote without exposing locator content", () => {
    const resolution = resolveLocatorRange(
      {
        locations: {},
        text: { highlight: "same" },
      },
      { requireUniqueTextQuote: true }
    );

    expect(resolution).toEqual({
      range: null,
      method: null,
      reason: "quote_ambiguous",
    });
  });

  it("uses unique surrounding context to resolve a repeated quote", () => {
    document.body.innerHTML =
      "<p>first same ending</p><p>second same finish</p>";
    const range = rangeFromLocator({
      locations: {},
      text: {
        before: "second ",
        highlight: "same",
        after: " finish",
      },
    });

    expect(range).not.toBeNull();
    expect(range.startContainer.parentElement.textContent).toBe(
      "second same finish"
    );
  });

  it("maps the standard charOffset field into legacy range info", () => {
    const info = location2RangeInfo({
      locations: {
        domRange: {
          start: {
            cssSelector: "#repeated",
            textNodeIndex: 0,
            charOffset: 1,
          },
          end: {
            cssSelector: "#repeated",
            textNodeIndex: 0,
            charOffset: 3,
          },
        },
      },
    });

    expect(info.startOffset).toBe(1);
    expect(info.endOffset).toBe(3);
  });

  it("resolves eight repeated occurrences to eight distinct ranges", () => {
    document.body.innerHTML = `<p id="repeated">${Array(8)
      .fill("same")
      .join("<br>")}</p>`;
    const parent = document.querySelector("#repeated");

    const indices = Array.from({ length: 8 }, (_, ordinal) => {
      const textNodeIndex = ordinal * 2;
      const range = rangeFromLocator({
        locations: {
          domRange: {
            start: {
              cssSelector: "#repeated",
              textNodeIndex,
              charOffset: 0,
            },
            end: {
              cssSelector: "#repeated",
              textNodeIndex,
              charOffset: 4,
            },
          },
        },
        text: { highlight: "same" },
      });
      return Array.from(parent.childNodes).indexOf(range.startContainer);
    });

    expect(indices).toEqual([0, 2, 4, 6, 8, 10, 12, 14]);
  });

  it("falls back with a stable reason when a DOM range quote mismatches", () => {
    document.body.innerHTML = '<p id="target">unique value</p>';
    const resolution = resolveLocatorRange({
      locations: {
        domRange: {
          start: {
            cssSelector: "#target",
            textNodeIndex: 0,
            charOffset: 0,
          },
          end: {
            cssSelector: "#target",
            textNodeIndex: 0,
            charOffset: 6,
          },
        },
      },
      text: { highlight: "value" },
    });

    expect(resolution.method).toBe("textQuote");
    expect(resolution.reason).toBe("dom_quote_mismatch");
    expect(resolution.range.toString()).toBe("value");
  });

  it("allows comparison against a legacy normalized quote", () => {
    document.body.innerHTML = '<p id="target">left\n   right</p>';
    const resolution = resolveLocatorRange({
      locations: {
        domRange: {
          start: {
            cssSelector: "#target",
            textNodeIndex: 0,
            charOffset: 0,
          },
          end: {
            cssSelector: "#target",
            textNodeIndex: 0,
            charOffset: 13,
          },
        },
      },
      text: { highlight: "left right" },
    });

    expect(resolution.method).toBe("domRange");
    expect(resolution.reason).toBeNull();
  });

  it("keeps the selection bridge's original highlight whitespace", () => {
    document.body.innerHTML = '<p id="target">left\n   right</p>';
    globalThis.readium = { link: { href: "chapter.xhtml" } };
    const text = document.querySelector("#target").firstChild;
    const range = document.createRange();
    range.setStart(text, 0);
    range.setEnd(text, text.data.length);
    range.getBoundingClientRect = () => ({
      bottom: 1,
      height: 1,
      left: 0,
      right: 1,
      top: 0,
      width: 1,
      x: 0,
      y: 0,
    });
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);

    const payload = getCurrentSelection();

    expect(payload.text.highlight).toBe("left\n   right");
  });

  it("does not publish a new selection when its DOM range is not persistent", () => {
    const target = document.createElement("p");
    target.id = "x".repeat(5000);
    target.textContent = "value";
    document.body.replaceChildren(target);
    globalThis.readium = { link: { href: "chapter.xhtml" } };

    const range = document.createRange();
    range.selectNodeContents(target);
    range.getBoundingClientRect = () => ({
      bottom: 1,
      height: 1,
      left: 0,
      right: 1,
      top: 0,
      width: 1,
      x: 0,
      y: 0,
    });
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);

    expect(getCurrentSelection()).toBeNull();
  });
});
