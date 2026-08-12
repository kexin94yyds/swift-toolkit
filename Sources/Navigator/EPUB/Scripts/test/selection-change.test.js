//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import { afterEach, describe, expect, it, vi } from "vitest";
import { observeSelectionChanges } from "../src/selection-change";

describe("EPUB selection change bridge", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it("posts a non-empty selection before a menu action can run", () => {
    vi.useFakeTimers();
    const selection = { href: "chapter.xhtml" };
    const postSelection = vi.fn();
    const stop = observeSelectionChanges({
      document,
      getSelection: () => selection,
      postSelection,
    });

    document.dispatchEvent(new Event("selectionchange"));

    expect(postSelection).toHaveBeenCalledOnce();
    expect(postSelection).toHaveBeenLastCalledWith(selection);
    expect(vi.getTimerCount()).toBe(0);
    stop();
  });

  it("delays a collapsed selection until the edit-menu transition settles", () => {
    vi.useFakeTimers();
    const postSelection = vi.fn();
    const stop = observeSelectionChanges({
      document,
      getSelection: () => null,
      postSelection,
    });

    document.dispatchEvent(new Event("selectionchange"));

    expect(postSelection).not.toHaveBeenCalled();
    vi.advanceTimersByTime(49);
    expect(postSelection).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(postSelection).toHaveBeenLastCalledWith(null);
    stop();
  });

  it("cancels a pending clear when a valid range appears", () => {
    vi.useFakeTimers();
    let selection = null;
    const postSelection = vi.fn();
    const stop = observeSelectionChanges({
      document,
      getSelection: () => selection,
      postSelection,
    });

    document.dispatchEvent(new Event("selectionchange"));
    selection = { href: "chapter.xhtml" };
    document.dispatchEvent(new Event("selectionchange"));
    vi.runAllTimers();

    expect(postSelection).toHaveBeenCalledTimes(1);
    expect(postSelection).toHaveBeenLastCalledWith(selection);
    stop();
  });
});
