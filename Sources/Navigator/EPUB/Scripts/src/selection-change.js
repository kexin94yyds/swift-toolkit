//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

export function observeSelectionChanges({
  document,
  getSelection,
  postSelection,
  clearDelay = 50,
  schedule = setTimeout,
  cancel = clearTimeout,
}) {
  let pendingClear;

  const selectionDidChange = () => {
    const selection = getSelection();

    cancel(pendingClear);
    pendingClear = undefined;

    if (selection) {
      // The edit menu can dispatch a custom action before a debounced bridge
      // callback runs. Publish a valid range immediately so native code can
      // retain it before WebKit collapses the DOM selection.
      postSelection(selection);
      return;
    }

    // WebKit may transiently collapse the DOM selection while presenting or
    // dismissing the edit menu. Delay only the clear notification, and cancel
    // it if another valid range appears first.
    pendingClear = schedule(() => {
      pendingClear = undefined;
      if (!getSelection()) {
        postSelection(null);
      }
    }, clearDelay);
  };

  document.addEventListener("selectionchange", selectionDidChange);

  return () => {
    cancel(pendingClear);
    document.removeEventListener("selectionchange", selectionDidChange);
  };
}
