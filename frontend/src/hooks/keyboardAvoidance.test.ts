import { describe, it, expect } from 'vitest';
import { isObscured } from './keyboardAvoidance';

// viewportHeight = visualViewport.height (area NOT covered by the keyboard).
describe('isObscured', () => {
  it('is false when the field sits fully within the visible viewport', () => {
    // field at 100–140, viewport 600 → fully visible, no scroll (this is the
    // box-to-box "Next" case that caused the flicker).
    expect(isObscured({ top: 100, bottom: 140 }, 600)).toBe(false);
  });

  it('is true when the field bottom is below the keyboard line', () => {
    expect(isObscured({ top: 580, bottom: 620 }, 600)).toBe(true);
  });

  it('is true when the field has scrolled above the viewport', () => {
    expect(isObscured({ top: -20, bottom: 10 }, 600)).toBe(true);
  });

  it('is false when the field bottom exactly meets the keyboard line', () => {
    expect(isObscured({ top: 560, bottom: 600 }, 600)).toBe(false);
  });
});
