# Material You Light Mode — Design Spec
<!-- 2026-06-03 -->

## Overview

Replace the current dark navy/cyan theme with a Material You (M3) light mode. Seed colour: cyan/teal. All screen transitions get a scale-fade animation. Icons stay outline-only (no fills). Bottom nav gets a tonal indicator pill on the active tab. No new dependencies — Tailwind-first throughout.

---

## 1. Color Tokens

New tokens added to `tailwind.config.js` under `theme.extend.colors`, replacing the three existing tokens (`bg`, `panel`, `accent`):

| Token | Hex | Usage |
|---|---|---|
| `bg` | `#fafdfe` | Page background (slightly cyan-tinted white) |
| `panel` | `#ffffff` | Cards, nav bar, modals |
| `surface-container` | `#e8f7f9` | Stat cells, tinted inset areas |
| `primary` | `#006874` | CTA buttons, active icon, focused borders |
| `primary-container` | `#97f0ff` | Nav pill, heparin "Used" chip, tonal fills |
| `on-primary` | `#ffffff` | Text/icons on primary buttons |
| `on-primary-container` | `#001f24` | Text/icons on primary-container fills |
| `on-surface` | `#191c1d` | Primary text |
| `on-surface-variant` | `#3f484a` | Secondary text, headings |
| `outline` | `#6f797a` | Input borders (unfocused), dividers |
| `outline-variant` | `#dbe4e6` | Card borders, subtle separators |
| `tertiary` | `#2e7d32` | Success states, "saved" badge, timer (on-time) |
| `warning` | `#e65100` | Timer overtime, elevated readings |
| `error` | `#b71c1c` | Error states, End session button |

The tokens `bg` and `panel` keep their names so existing usage (`bg-bg`, `bg-panel`) continues to compile without a find-replace pass.

---

## 2. Screen Transitions

### Treatment flow (Home → Pre → Active → Post → Home)

Each screen's root `<div>` gets `className="screen-enter ..."`. Because React unmounts and remounts the screen component on every state change, the CSS animation fires automatically on every transition — no extra state or wrapper component needed.

```css
/* index.css */
@keyframes screen-enter {
  from { opacity: 0; transform: scale(1.04); }
  to   { opacity: 1; transform: scale(1); }
}
.screen-enter {
  animation: screen-enter 280ms cubic-bezier(0.2, 0, 0, 1) both;
}
```

Duration: 280ms. Easing: M3 standard (`cubic-bezier(0.2, 0, 0, 1)`).

### AddReadingModal — bottom sheet

Replace the current centered fixed overlay with a bottom sheet that slides up from the screen edge. The backdrop fades in simultaneously.

```css
@keyframes sheet-up {
  from { transform: translateY(100%); }
  to   { transform: translateY(0); }
}
@keyframes backdrop-in {
  from { opacity: 0; }
  to   { opacity: 1; }
}
.sheet-enter {
  animation: sheet-up 300ms ease-out both;
}
.backdrop-enter {
  animation: backdrop-in 250ms ease-out both;
}
```

The modal container changes from `inset-0 flex items-center justify-center` to `inset-0 flex items-end` with the inner panel using `rounded-t-3xl w-full max-h-[85vh] overflow-y-auto`.

Dismiss (×) closes immediately with no exit animation (acceptable for a personal app — keeps code simple).

### Tab bar (AppShell bottom nav)

No page-level animation on tab switch — content changes are instant. Only the tonal pill behind the active icon animates, via a CSS `transition` on `background-color`.

---

## 3. Icons

Lucide icons are outline/stroke by default. Several places in the codebase pass `fill="currentColor"`, which makes them appear solid. Strip these:

| File | Icon | Change |
|---|---|---|
| `Treatment/screens/Home.tsx` | `<Play>` in Start session button | Remove `fill="currentColor"` |
| `Treatment/screens/PreTreatment.tsx` | `<Play>` in Start session button | Remove `fill="currentColor"` |
| `Treatment/components/SaveButton.tsx` | Any icon passed as `icon` prop that has fill | Callers control the icon; remove fill at call sites |
| `Treatment/screens/ActiveSession.tsx` | `<Square>` End button | Remove `fill="currentColor"` |

No new icon imports. The existing lucide set is sufficient.

---

## 4. Bottom Navigation Bar (AppShell)

Active tab indicator: a tonal pill (`bg-primary-container`) behind the icon, 40 × 24 px, `rounded-xl`. The icon on the active tab uses `text-on-primary-container`. Inactive tabs use `text-outline`.

```tsx
const navIconWrap = (isActive: boolean) =>
  `flex items-center justify-center w-10 h-6 rounded-xl transition-colors ${
    isActive ? 'bg-primary-container' : ''
  }`;
```

Label: active = `text-primary font-semibold`, inactive = `text-outline`.

Desktop top nav: same colour updates, no pill (horizontal layout doesn't need it).

---

## 5. Component Styling

### Cards / panels
- Border: `border-outline-variant` (replaces `border-slate-700`)
- Border radius: `rounded-2xl` for cards and main panels (up from `rounded-lg`)
- Background: `bg-panel` (white)
- Subtle shadow: `shadow-sm` (`0 1px 3px rgba(0,0,0,.07)`)

### Inputs (NumberField)
- Border: `border-outline` unfocused, `border-primary` focused
- Border radius: `rounded-xl`
- Background: `bg-bg`
- Text: `text-on-surface`
- Label: `text-on-surface-variant text-xs font-semibold`

### Primary CTA button
- Background: `bg-primary`
- Text: `text-on-primary font-semibold`
- Border radius: `rounded-full` (M3 filled button uses full pill radius)
- No border

### Tonal chip (Heparin Used / Not used)
- Active: `bg-primary-container text-on-primary-container`
- Inactive: `bg-outline-variant text-outline`
- Border radius: `rounded-full`

### Stat cells (Active session pre-values)
- Background: `bg-surface-container`
- Label: `text-primary text-xs font-bold`
- Value: `text-on-primary-container font-bold` (or semantic colour: `text-tertiary` for pulse, `text-primary` for UF)

### Error / warning / success colours
- Error border/text: `text-error` / `border-error`
- Warning: `text-warning` (timer overtime)
- Success: `text-tertiary` (saved badge, timer on-time, check icons)

---

## 6. Files Changed

| File | What changes |
|---|---|
| `tailwind.config.js` | Replace 3 tokens with 13 M3 tokens |
| `src/index.css` | Add `screen-enter`, `sheet-up`, `backdrop-in` keyframes + utility classes; update `body` bg/text |
| `src/components/AppShell.tsx` | Nav bar tonal pill, colour token updates |
| `src/routes/Treatment/screens/Home.tsx` | `screen-enter` class, colour tokens, strip Play fill |
| `src/routes/Treatment/screens/PreTreatment.tsx` | `screen-enter` class, colour tokens, strip Play fill |
| `src/routes/Treatment/screens/ActiveSession.tsx` | `screen-enter` class, colour tokens, strip Square fill, stat cell styling |
| `src/routes/Treatment/screens/PostTreatment.tsx` | `screen-enter` class, colour tokens |
| `src/routes/Treatment/components/AddReadingModal.tsx` | Bottom sheet layout + `sheet-enter` / `backdrop-enter` classes |
| `src/routes/Treatment/components/NumberField.tsx` | Input border/radius/colour tokens |
| `src/routes/Treatment/components/SaveButton.tsx` | Colour tokens |
| `src/routes/Treatment/components/SessionListItem.tsx` | Colour tokens |
| `src/routes/BloodTests/**` | Structural colour tokens only (bg, panel, borders, text) |
| `src/routes/Inventory/**` | Structural colour tokens only |
| `src/routes/KB/index.tsx` | Structural colour tokens only |
| `src/routes/Fitness/index.tsx` | Structural colour tokens only |
| `src/routes/Chat/index.tsx` | Structural colour tokens only |
| `src/auth/SetupWizard.tsx` | Structural colour tokens only |

"Structural colour tokens only" means: swap `bg-bg`, `bg-panel`, `border-slate-700` → `border-outline-variant`, `text-slate-100/200/300` → `text-on-surface`, `text-slate-400/500` → `text-on-surface-variant text-outline`, `text-accent` → `text-primary`. No layout changes.

---

## 7. Out of Scope

- Dark mode toggle — fully replaced, not toggled
- MUI component library — not installed
- Dynamic colour extraction from device wallpaper (M3 "dynamic colour") — not implemented
- Any changes to data models, API calls, or storage
