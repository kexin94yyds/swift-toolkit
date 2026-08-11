//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import { getCssSelector } from "css-selector-generator";

const maxSelectorLength = 4096;

/**
 * Serializes a browser Range with the standard Readium HTML DOM Range
 * extension.
 *
 * Element boundary points are normalized to text-node boundaries so that
 * `textNodeIndex` always identifies an entry in `parent.childNodes` and
 * `charOffset` always uses the browser's UTF-16 text-node coordinates.
 */
export function domRangeFromRange(range) {
  try {
    if (!range || range.collapsed) {
      return null;
    }
    const document = range.startContainer.ownerDocument;
    if (!document) {
      return null;
    }

    const start = normalizeBoundary(
      range.startContainer,
      range.startOffset,
      "start"
    );
    const end = normalizeBoundary(range.endContainer, range.endOffset, "end");
    if (!start || !end) {
      return null;
    }

    const normalized = rangeForBoundaries(document, start, end);
    if (!normalized || normalized.collapsed) {
      return null;
    }

    const startPoint = pointFromBoundary(document, start);
    const endPoint = pointFromBoundary(document, end);
    if (!startPoint || !endPoint) {
      return null;
    }

    return { start: startPoint, end: endPoint };
  } catch {
    return null;
  }
}

/**
 * Resolves the standard Readium HTML DOM Range extension in `document`.
 */
export function rangeFromDOMRange(document, domRange) {
  return resolveDOMRange(document, domRange).range;
}

/**
 * Resolves a DOM Range and returns a stable, content-free failure reason.
 */
export function resolveDOMRange(document, domRange) {
  if (!document || !domRange || !domRange.start) {
    return failed("dom_missing");
  }

  const start = boundaryFromPoint(document, domRange.start);
  if (!start.boundary) {
    return failed(start.reason);
  }

  const end = boundaryFromPoint(document, domRange.end || domRange.start);
  if (!end.boundary) {
    return failed(end.reason);
  }

  const range = rangeForBoundaries(document, start.boundary, end.boundary);
  if (!range) {
    return failed("dom_reversed");
  }
  if (range.collapsed) {
    return failed("dom_collapsed");
  }

  return { range, reason: null };
}

function failed(reason) {
  return { range: null, reason };
}

function normalizeBoundary(container, offset, edge) {
  if (container.nodeType === Node.TEXT_NODE) {
    if (!validOffset(offset, container.data.length)) {
      return null;
    }
    return { node: container, offset };
  }

  if (container.nodeType !== Node.ELEMENT_NODE) {
    return null;
  }
  if (
    !Number.isInteger(offset) ||
    offset < 0 ||
    offset > container.childNodes.length
  ) {
    return null;
  }

  if (edge === "start") {
    for (let index = offset; index < container.childNodes.length; index += 1) {
      const node = firstTextNode(container.childNodes[index]);
      if (node) {
        return { node, offset: 0 };
      }
    }
  } else {
    for (let index = offset - 1; index >= 0; index -= 1) {
      const node = lastTextNode(container.childNodes[index]);
      if (node) {
        return { node, offset: node.data.length };
      }
    }
  }

  return null;
}

function firstTextNode(node) {
  if (node.nodeType === Node.TEXT_NODE) {
    return node;
  }
  for (const child of Array.from(node.childNodes || [])) {
    const result = firstTextNode(child);
    if (result) {
      return result;
    }
  }
  return null;
}

function lastTextNode(node) {
  if (node.nodeType === Node.TEXT_NODE) {
    return node;
  }
  const children = Array.from(node.childNodes || []);
  for (let index = children.length - 1; index >= 0; index -= 1) {
    const result = lastTextNode(children[index]);
    if (result) {
      return result;
    }
  }
  return null;
}

function pointFromBoundary(document, boundary) {
  const parent = boundary.node.parentElement;
  if (!parent) {
    return null;
  }

  const textNodeIndex = Array.from(parent.childNodes).indexOf(boundary.node);
  if (textNodeIndex < 0) {
    return null;
  }

  const cssSelector = getCssSelector(parent);
  if (
    typeof cssSelector !== "string" ||
    cssSelector.length === 0 ||
    cssSelector.length > maxSelectorLength
  ) {
    return null;
  }

  let matches;
  try {
    matches = document.querySelectorAll(cssSelector);
  } catch {
    return null;
  }
  if (matches.length !== 1 || matches[0] !== parent) {
    return null;
  }

  return {
    cssSelector,
    textNodeIndex,
    charOffset: boundary.offset,
  };
}

function boundaryFromPoint(document, point) {
  if (
    !point ||
    typeof point.cssSelector !== "string" ||
    point.cssSelector.length === 0 ||
    point.cssSelector.length > maxSelectorLength ||
    !Number.isInteger(point.textNodeIndex) ||
    point.textNodeIndex < 0
  ) {
    return { boundary: null, reason: "dom_point_invalid" };
  }

  let matches;
  try {
    matches = document.querySelectorAll(point.cssSelector);
  } catch {
    return { boundary: null, reason: "dom_selector_invalid" };
  }
  if (matches.length !== 1) {
    return { boundary: null, reason: "dom_selector_not_unique" };
  }

  const element = matches[0];
  if (point.textNodeIndex >= element.childNodes.length) {
    return { boundary: null, reason: "dom_node_out_of_bounds" };
  }

  const node = element.childNodes[point.textNodeIndex];
  if (node.nodeType !== Node.TEXT_NODE) {
    return { boundary: null, reason: "dom_node_not_text" };
  }

  const offset = point.charOffset ?? point.offset ?? 0;
  if (!validOffset(offset, node.data.length)) {
    return { boundary: null, reason: "dom_offset_out_of_bounds" };
  }

  return { boundary: { node, offset }, reason: null };
}

function validOffset(offset, length) {
  return Number.isInteger(offset) && offset >= 0 && offset <= length;
}

function rangeForBoundaries(document, start, end) {
  if (!boundariesAreOrdered(document, start, end)) {
    return null;
  }

  const range = document.createRange();
  range.setStart(start.node, start.offset);
  range.setEnd(end.node, end.offset);
  return range;
}

function boundariesAreOrdered(document, start, end) {
  if (start.node === end.node) {
    return start.offset <= end.offset;
  }

  const startRange = document.createRange();
  startRange.setStart(start.node, start.offset);
  startRange.collapse(true);

  const endRange = document.createRange();
  endRange.setStart(end.node, end.offset);
  endRange.collapse(true);

  return startRange.compareBoundaryPoints(Range.START_TO_START, endRange) <= 0;
}
