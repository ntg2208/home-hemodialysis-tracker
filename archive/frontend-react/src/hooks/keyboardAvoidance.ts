/**
 * Whether a focused field needs scrolling into view, given its vertical rect and
 * the visible viewport height (visualViewport.height — the area above the on-screen
 * keyboard). A field that's fully visible must NOT be scrolled: doing so on every
 * focus change (e.g. tapping the keyboard "Next" between already-visible fields)
 * causes a visible flick.
 */
export function isObscured(
  rect: { top: number; bottom: number },
  viewportHeight: number,
): boolean {
  return rect.bottom > viewportHeight || rect.top < 0;
}
