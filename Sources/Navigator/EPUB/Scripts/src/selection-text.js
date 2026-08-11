//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

/**
 * Preserves the selection-text normalization used to reject empty selections
 * and to compare against locators created by older integrations.
 *
 * The selection bridge still emits the original Range text unchanged.
 */
export function normalizeSelectionText(text) {
  if (typeof text !== "string") {
    return "";
  }
  return text.trim().replace(/\n/g, " ").replace(/\s\s+/g, " ");
}
