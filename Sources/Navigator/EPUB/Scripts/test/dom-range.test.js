//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

// @vitest-environment jsdom

import { beforeEach, describe, expect, it } from "vitest";
import {
  domRangeFromRange,
  rangeFromDOMRange,
  resolveDOMRange,
} from "../src/dom-range";

describe("Readium HTML DOM Range codec", () => {
  beforeEach(() => {
    document.body.innerHTML = "";
  });

  it("round-trips a repeated text-node occurrence", () => {
    document.body.innerHTML =
      '<p id="repeated">same<br>same<br>same<br>same</p>';
    const parent = document.querySelector("#repeated");
    const target = parent.childNodes[4];
    const range = document.createRange();
    range.setStart(target, 0);
    range.setEnd(target, 4);

    const domRange = domRangeFromRange(range);
    const restored = rangeFromDOMRange(document, domRange);

    expect(domRange.start.textNodeIndex).toBe(4);
    expect(domRange.start.charOffset).toBe(0);
    expect(domRange.end.charOffset).toBe(4);
    expect(Array.from(parent.childNodes).indexOf(restored.startContainer)).toBe(
      4
    );
    expect(restored.toString()).toBe("same");
  });

  it("round-trips a cross-element range", () => {
    document.body.innerHTML =
      '<p id="root"><span>left</span><em>right</em></p>';
    const start = document.querySelector("span").firstChild;
    const end = document.querySelector("em").firstChild;
    const range = document.createRange();
    range.setStart(start, 1);
    range.setEnd(end, 3);

    const restored = rangeFromDOMRange(document, domRangeFromRange(range));

    expect(restored.toString()).toBe("eftrig");
    expect(restored.startOffset).toBe(1);
    expect(restored.endOffset).toBe(3);
  });

  it("uses UTF-16 offsets for emoji", () => {
    document.body.innerHTML = '<p id="emoji">A😀B</p>';
    const text = document.querySelector("#emoji").firstChild;
    const range = document.createRange();
    range.setStart(text, 1);
    range.setEnd(text, 3);

    const domRange = domRangeFromRange(range);
    const restored = rangeFromDOMRange(document, domRange);

    expect(domRange.start.charOffset).toBe(1);
    expect(domRange.end.charOffset).toBe(3);
    expect(restored.toString()).toBe("😀");
  });

  it("normalizes element boundaries to text nodes", () => {
    document.body.innerHTML =
      '<p id="root"><span>left</span><em>right</em></p>';
    const parent = document.querySelector("#root");
    const range = document.createRange();
    range.setStart(parent, 0);
    range.setEnd(parent, 2);

    const restored = rangeFromDOMRange(document, domRangeFromRange(range));

    expect(restored.startContainer).toBe(
      document.querySelector("span").firstChild
    );
    expect(restored.startOffset).toBe(0);
    expect(restored.endContainer).toBe(document.querySelector("em").firstChild);
    expect(restored.endOffset).toBe(5);
  });

  it("round-trips CJK text across ruby nodes", () => {
    document.body.innerHTML =
      '<p id="cjk">前<ruby>漢<rt>かん</rt></ruby><span>後</span></p>';
    const start = document.querySelector("#cjk").firstChild;
    const end = document.querySelector("span").firstChild;
    const range = document.createRange();
    range.setStart(start, 0);
    range.setEnd(end, 1);

    const restored = rangeFromDOMRange(document, domRangeFromRange(range));

    expect(restored.toString()).toBe(range.toString());
    expect(restored.startOffset).toBe(0);
    expect(restored.endOffset).toBe(1);
  });

  it("ignores RTL and vertical writing styles when round-tripping", () => {
    document.body.innerHTML =
      '<p id="rtl" dir="rtl">אבגדה</p><p id="vertical" style="writing-mode: vertical-rl">縦書き</p>';

    for (const selector of ["#rtl", "#vertical"]) {
      const text = document.querySelector(selector).firstChild;
      const range = document.createRange();
      range.setStart(text, 1);
      range.setEnd(text, text.data.length - 1);

      const restored = rangeFromDOMRange(document, domRangeFromRange(range));

      expect(restored.toString()).toBe(range.toString());
      expect(restored.startOffset).toBe(1);
      expect(restored.endOffset).toBe(text.data.length - 1);
    }
  });

  it("rejects an element boundary with no descendant text", () => {
    document.body.innerHTML = '<p id="empty"><img alt="cover"></p>';
    const parent = document.querySelector("#empty");
    const range = document.createRange();
    range.setStart(parent, 0);
    range.setEnd(parent, 1);

    expect(domRangeFromRange(range)).toBeNull();
  });

  it("reads the legacy offset field", () => {
    document.body.innerHTML = '<p id="target">value</p>';
    const restored = rangeFromDOMRange(document, {
      start: { cssSelector: "#target", textNodeIndex: 0, offset: 1 },
      end: { cssSelector: "#target", textNodeIndex: 0, offset: 4 },
    });

    expect(restored.toString()).toBe("alu");
  });

  it("rejects a selector which is not unique", () => {
    document.body.innerHTML = "<p>one</p><p>two</p>";
    const result = resolveDOMRange(document, {
      start: { cssSelector: "p", textNodeIndex: 0, charOffset: 0 },
      end: { cssSelector: "p", textNodeIndex: 0, charOffset: 1 },
    });

    expect(result.range).toBeNull();
    expect(result.reason).toBe("dom_selector_not_unique");
  });

  it("rejects a selector which no longer matches", () => {
    document.body.innerHTML = '<p id="target">value</p>';
    const result = resolveDOMRange(document, {
      start: { cssSelector: "#missing", textNodeIndex: 0, charOffset: 0 },
      end: { cssSelector: "#missing", textNodeIndex: 0, charOffset: 1 },
    });

    expect(result.range).toBeNull();
    expect(result.reason).toBe("dom_selector_not_unique");
  });

  it("rejects a child index which points to a non-text node", () => {
    document.body.innerHTML = '<p id="target"><span>value</span></p>';
    const result = resolveDOMRange(document, {
      start: { cssSelector: "#target", textNodeIndex: 0, charOffset: 0 },
      end: { cssSelector: "#target", textNodeIndex: 0, charOffset: 1 },
    });

    expect(result.range).toBeNull();
    expect(result.reason).toBe("dom_node_not_text");
  });

  it("rejects an out-of-bounds offset", () => {
    document.body.innerHTML = '<p id="target">value</p>';
    const result = resolveDOMRange(document, {
      start: { cssSelector: "#target", textNodeIndex: 0, charOffset: 99 },
      end: { cssSelector: "#target", textNodeIndex: 0, charOffset: 100 },
    });

    expect(result.range).toBeNull();
    expect(result.reason).toBe("dom_offset_out_of_bounds");
  });

  it("rejects a negative offset", () => {
    document.body.innerHTML = '<p id="target">value</p>';
    const result = resolveDOMRange(document, {
      start: { cssSelector: "#target", textNodeIndex: 0, charOffset: -1 },
      end: { cssSelector: "#target", textNodeIndex: 0, charOffset: 1 },
    });

    expect(result.range).toBeNull();
    expect(result.reason).toBe("dom_offset_out_of_bounds");
  });

  it("rejects a reversed persistent range", () => {
    document.body.innerHTML = '<p id="target">value</p>';
    const result = resolveDOMRange(document, {
      start: { cssSelector: "#target", textNodeIndex: 0, charOffset: 4 },
      end: { cssSelector: "#target", textNodeIndex: 0, charOffset: 1 },
    });

    expect(result.range).toBeNull();
    expect(result.reason).toBe("dom_reversed");
  });

  it("rejects a collapsed persistent range", () => {
    document.body.innerHTML = '<p id="target">value</p>';
    const result = resolveDOMRange(document, {
      start: { cssSelector: "#target", textNodeIndex: 0, charOffset: 2 },
      end: { cssSelector: "#target", textNodeIndex: 0, charOffset: 2 },
    });

    expect(result.range).toBeNull();
    expect(result.reason).toBe("dom_collapsed");
  });
});
