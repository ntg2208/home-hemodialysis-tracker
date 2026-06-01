# Home HD App — Flutter UI Design Brief

> Purpose: a complete, grounded description of every screen in the Home HD app,
> written to be handed to a UI-generation tool (e.g. Google AI) to produce
> Flutter/Dart code. Every field, default, and behaviour below is taken from the
> current React/PWA implementation in this repo (`frontend/src`).
>
> **Two intentional design changes from the current app:**
> 1. Replace the bottom tab bar with a left **side drawer (hamburger menu)**.
> 2. Add a persistent **Chat FAB** (bottom-right corner) opening a chat panel.
>
> **Note on Chat:** the Chat backend does not exist yet (`api/src/handlers/chat.ts`
> is a placeholder). The Chat UI is new design, not a port — generate it now; the
> endpoint gets built and wired later.

---

## Global design system

**Medical-utility, calm, high-contrast, readable at a glance during dialysis.** Not
playful. **Ships with both light and dark themes** — define a single token set with
two value columns and let `ThemeMode.system` pick automatically (with a manual
override later in Settings). Every colour reference in this brief is a **token**, so
each screen renders correctly in both modes without per-screen logic.

### Colour tokens — light + dark

| Token | Dark value | Light value | Used for |
|---|---|---|---|
| `bg` | very dark slate `#0F172A` | near-white `#F8FAFC` | screen background |
| `panel` | dark slate `#1E293B` | white `#FFFFFF` | cards, list rows, input fields |
| `accent` | cyan `#22D3EE` | cyan-600 `#0891B2` | primary buttons, active states, links |
| `accent-on` | slate-900 `#0F172A` | white `#FFFFFF` | text/icon *on top of* an accent fill |
| `border` | slate-700 `#334155` | slate-200 `#E2E8F0` | card/input outlines, dividers |
| `text-primary` | slate-100 `#F1F5F9` | slate-900 `#0F172A` | values, headings |
| `text-secondary` | slate-400 `#94A3B8` | slate-500 `#64748B` | labels |
| `text-muted` | slate-500 `#64748B` | slate-400 `#94A3B8` | hints, timestamps |

**Status colours (both modes — pick the shade that holds contrast on that mode's
background):** emerald = good / in-range / saved · amber = warning / stale · red =
error / out-of-range / critical · rose = blood-pressure & heart metrics. Use the
**-400/-500** shades on dark `bg`, the **-600/-700** shades on light `bg`, so flags
stay legible in both. Status *fills* (badges) pair the colour with `accent-on`-style
contrasting text.

**Accent contrast note:** the dark-mode cyan (`#22D3EE`) is too light to sit under
white text, so in light mode `accent` darkens to cyan-600 — buttons keep white text
in both modes via `accent-on`.

### Shape language — **all buttons are pill-shaped**

- **Every button is a full pill** (`StadiumBorder` / fully-rounded, radius = half
  the height). This applies to: primary CTAs, secondary/outline buttons, the FAB
  (circular is a pill at 1:1), suggestion chips, segmented toggles, the send button,
  − / + steppers (circular), and dialog action buttons. **No square or
  small-radius buttons anywhere.**
- Button sizes: primary CTA full-width pill, comfortable height (~52px) for
  in-treatment tapping; secondary actions shorter pills; icon-only buttons are
  circular (44px min touch target).
- **Cards / sheets / inputs** are *not* pills — they keep ~12–16px rounded corners.
  Pill shape is for **tappable buttons only**. (Chat message bubbles keep their
  anchored-corner shape described in the Chat section.)

**Typography:** numeric values use a slightly larger, semibold weight. Timers,
session IDs, and reading values use a **monospace** font. Labels are small,
uppercase-tracked for section headers.

**Spacing:** generous — single-column mobile, max content width ~420px centred.
Cards have rounded corners (~12px), 1px border, subtle panel fill.

### Animation & motion

Motion is **subtle, fast, and purposeful** — confirm actions and smooth
transitions, never decorative. Standard durations: **150ms** for taps/toggles,
**250–300ms** for screen/sheet transitions, all with an ease-out (decelerate)
curve. Respect the OS "reduce motion" setting (fall back to instant/cross-fade).

| Element | Animation |
|---|---|
| Button press | quick scale-down to ~0.96 + ripple on tap, springs back on release (150ms) |
| Theme switch (light⇄dark) | cross-fade colours over ~250ms, not an instant flip |
| Screen push (Pre→Active→Post, drawer destinations) | slide-in from right + fade (250–300ms); back reverses it |
| Drawer | standard slide-in from left with a scrim fade |
| Chat bottom sheet | slide up from bottom (~300ms ease-out); drag-to-dismiss tracks the finger, flings closed |
| Chat FAB ⇄ sheet | FAB scales/fades out as the sheet opens; scales back in on close (container-transform feel) |
| Message send | new bubble fades + slides up ~8px into place; list auto-scrolls smoothly to it |
| Thinking indicator | three dots bounce in a staggered loop |
| Save status (readings, writes) | spinner → green check **cross-fades** (no abrupt swap); error shakes the row once (~300ms) |
| Countdown colour shifts | colour transitions over ~400ms when crossing a threshold (emerald→amber→red), not a hard cut |
| Timer alerts (2h/1h/5m) | in-app banner slides down from top + fades; auto-pulses once |
| Tab switch (Scorecard⇄Trend) | underline indicator slides between tabs; content cross-fades |
| Stepper ± / stock adjust | the number ticks with a quick count animation + the row briefly highlights |
| List load (cache→fresh) | new/changed rows fade in; never a full-list flash |
| Pull-to-refresh / Sync | icon spins while in flight |

---

## Navigation (NEW design)

**Left side drawer (hamburger), replacing the bottom tab bar.**

- Every screen has a top app bar: hamburger icon (left) → opens `Drawer`; screen
  title; optional screen-specific action (right, e.g. Sync).
- Drawer contents (vertical list, icon + label):
  1. Treatment — activity/pulse icon
  2. Blood Tests — flask icon
  3. Inventory — box icon
  4. Fitness — dumbbell icon
  5. Knowledge Base — book icon
  6. — divider —
  7. Settings — gear icon
- Drawer header: "Home HD" title, small subtitle (patient context or app version).
- Active route highlighted in accent (cyan text + subtle panel highlight).

**Chat FAB (NEW) — identical on every screen.** A single, **shared** Chat FAB
component is rendered once at the app-shell level (e.g. in the `Scaffold` that wraps
all drawer destinations), **not re-declared per screen** — this guarantees it is
pixel-identical everywhere. Specification, fixed across all screens:

- **Position:** bottom-right corner, same inset on every screen (clear of the
  Android nav bar / safe-area). Standard `FloatingActionButtonLocation.endFloat`.
- **Icon:** **always the same** — the assistant glyph (chat-bubble-with-ECG-pulse,
  matching the assistant avatar in the Chat section). Never swaps per screen.
- **Colour:** `accent` fill with `accent-on` icon (correct in both light and dark).
- **Shape:** circular pill (1:1), with the standard FAB elevation/shadow.
- **Behaviour:** tapping opens the Chat bottom sheet (overlay, last section). The
  FAB scales/fades out while the sheet is open and scales back in on close.
- **Visibility:** present and identical on **every screen once authenticated** —
  all drawer destinations *and* the Treatment sub-screens (Pre / Active / Post). The
  only screen without it is the pre-auth **Setup** gate (it lives outside the app
  shell, before any chat context exists). On the Active session screen, place the
  FAB so it never overlaps the "Add reading" button (FAB bottom-right, "Add reading"
  full-width above the readings list — they don't collide).
- Floats above all content; never part of the drawer.

### Navigation map

Top-level routes are reached **only via the drawer** (no bottom tabs). Each
top-level screen is a drawer destination; sub-screens are pushed on top and use
the back arrow / Android back gesture to return.

```
Setup ──(valid key)──▶ Treatment Home  ◀── default landing route
                          │
Drawer (hamburger, every screen):
  ├─ Treatment ──▶ Treatment Home
  ├─ Blood Tests ─▶ Blood Tests (Scorecard ⇄ Trend tabs)
  ├─ Inventory ──▶ Inventory
  ├─ Fitness ───▶ Fitness
  ├─ Knowledge Base ─▶ KB
  └─ Settings ──▶ Settings ──(Clear credentials)──▶ Setup

Chat FAB (every screen) ──▶ Chat bottom sheet (overlay, not a route)
```

**Rules:**
- The hamburger opens the drawer on **every** top-level screen. Sub-screens
  (Pre/Active/Post, modals, Chat) show a **back arrow or close (X)** instead of the
  hamburger, since they're pushed/overlaid.
- Selecting a drawer item closes the drawer and replaces the current top-level
  route (does not stack drawer destinations).
- On any **401 / rejected key**, any screen routes to **Setup** with a message.
- Default landing route after Setup is **Treatment Home**.

---

## Screen 1 — Treatment

A 4-step flow: **Home → Pre → Active → Post**. State persists locally so a
force-quit mid-session restores exactly where you were (24h TTL).

**Navigation within Treatment:** Home is the drawer destination (shows hamburger).
Pre / Active / Post are pushed in sequence and show a back-arrow or close (X), not
the hamburger. On relaunch, if a session is in progress the app restores straight
to the correct sub-screen (Pre / Active / Post) instead of Home.

### 1a. Home

- App bar: "Treatment", hamburger.
- **Navigation:** drawer destination. "Start session" → pushes Pre. Drawer reachable
  here.
- **Large primary button:** "Start session" (accent, full-width, play icon).
  Disabled with a spinner until the recent-sessions list has loaded.
- **Dried weight card:** row showing "Dried weight" label + current value
  (e.g. "59 kg") with a small pencil edit icon. Tapping reveals an inline numeric
  field + check/cancel; default 59, persisted locally.
- **Recent sessions section:** header "Recent sessions" with a small "refreshing…"
  spinner when revalidating in background. Shows last 5 sessions (newest first).
  Each row: date, pre→post BP, total UF removed, duration. Empty: "No sessions
  yet." Error: red banner with inline Retry.
- **Data behaviour:** show cached sessions instantly, then refresh from Firestore
  in the background (stale-while-revalidate).

### 1b. Pre-treatment form

- App bar: "Pre-treatment", Cancel (X) returns to Home.
- **Navigation:** pushed from Home. "Start session" → replaces with Active.
  Cancel (X) → back to Home. No drawer here.
- **2-column grid of numeric fields** (all decimal keypad):
  1. Weight (kg)
  2. UF goal (L) — **auto-calculated** `weight − dried_weight`; editable; reverts
     to auto if cleared.
  3. UF rate (mL/h) — **auto-calculated** `uf_goal ÷ 0.004`; editable; reverts to
     auto if cleared.
  4. BP systolic
  5. BP diastolic
  6. Pulse
- **EPO toggle** (yes/no) — flagged here, carried to Post.
- **Heparin toggle** (yes/no) — set here, carried into Active and Post.
- *Auto-fill rule:* a field shows the derived value until the user types; a manual
  edit sticks; clearing brings the derived value back. Submit uses the displayed
  value.
- **"Start session" button** (accent, full-width) → creates the session record,
  advances to Active.

### 1c. Active session

The most-used, most time-pressured screen. Hands-on during the 4+ hour treatment.

- App bar: "Session `<id>`" (id monospace) + "End" button (right, square icon).
- **Navigation:** replaces Pre. "End session" → replaces with Post. No back arrow
  to Pre (the session has started); leaving is via "End". No drawer here.
- **Pre-values reference card** (2×2 grid, read-only): Weight (scale), UF goal
  (droplet, cyan), BP (heart, rose), Pulse (activity, emerald).
- **Countdown timer card:**
  - Large monospace timer showing **time remaining** toward target (default
    4h 15m = 255 min). Editable target via inline hours/minutes + pencil.
  - Starts automatically when the **first reading** is added (before that:
    "Waiting for first reading").
  - Colour shifts: emerald (>10 min left) → amber (≤10 min) → red (≤5 min or
    overtime). Overtime shows `+H:MM:SS`.
  - **Alerts at 2h / 1h / 5min remaining:** in-app banner (top, dismissible) +
    device vibration + local notification. (Flutter: `flutter_local_notifications`
    + `vibration` — upgrade over the web version which could only notify when open.)
- **"Add reading" button** (accent, full-width, plus icon) → Add-reading bottom
  sheet.
- **Add-reading bottom sheet fields:** Time (defaults to now, editable), BP sys,
  BP dia, Pulse, Blood flow (defaults to most-recent reading's value), Venous
  pressure, Arterial pressure, Note. Save + Cancel.
- **"Consumed this session" card:** Needles used (default 2), On/Off packs
  (default 1). Feeds inventory deduction at session end.
- **Heparin toggle** (sticky — reflects Pre's value, editable here since heparin
  is actioned during the session).
- **Readings list** (newest first): each row shows time (monospace), per-row save
  status (spinner "saving…" / green check / red "error" + inline Retry), detail
  line `BP s/d · pulse · BF · VP · AP`, plus the note in italics if present.
- **Per-reading optimistic save:** appears immediately as "pending", writes to
  Firestore, flips to "saved" or "error+Retry". A force-quit demotes any in-flight
  reading to "interrupted" with a Retry on restore.
- **"End session"** → advances to Post, passing consumed counts + heparin +
  computed duration.

### 1d. Post-treatment form

- App bar: "Post-treatment".
- **Navigation:** replaces Active. "Finish" → returns to Treatment Home (clears the
  active-session stack and local active-state cache). No drawer here.
- **Numeric fields:** Weight, BP sys, BP dia, Pulse, Duration min (default 255),
  Dialysate volume L (default 49), Total UF (auto `pre_weight − post_weight`),
  Blood processed.
- **EPO toggle** — shows the value set in Pre, editable.
- **Heparin toggle** — shows the value set in Active, editable.
- *Both meds use a single shared source of truth per session — set once,
  shown/editable on both Pre and Post.*
- **"Finish" button** (accent, check icon) → writes post values, returns to Home,
  clears the active-state cache.

---

## Screen 2 — Blood Tests

Read-heavy analytics. ~2,400 historical lab rows; cache-first with a 6-month
default window.

- App bar: "Blood Tests", hamburger.
- **Navigation:** drawer destination. Scorecard ⇄ Trend are tabs within the same
  screen (not separate routes); tapping a scorecard tile switches to the Trend tab,
  and Android back returns Trend → Scorecard before leaving the screen.
- **Filter bar** (sticky, top): Phase multi-select (`home-hd` default /
  `in-center-hd` / `admission` / all), date range (from/to as month or year
  pickers — older ranges trigger a backfill fetch), marker selector.
- **Sync row:** left = sync status ("Synced 3m ago" / "Syncing…" / "Offline —
  showing cached"); right = "Sync" button (re-fetches current range, merges new
  rows + in-place edits).
- **Two tabs: Scorecard | Trend** (underline-style tab indicator in cyan).

**Scorecard tab:** grid of marker tiles. Each tile: marker name, latest value +
unit, delta arrow vs previous reading, in-range/out-of-range badge (emerald/red),
reference range small. A favourites mechanism pins chosen markers to the top
(persisted locally). Tapping a tile → jumps to Trend for that marker.

**Trend tab:**
- Line chart: value over time. **Stepped reference-range band** shaded behind the
  line (ranges drift over years → visible as steps). Pre vs post draws by colour.
  Phase-boundary vertical lines. Out-of-range points highlighted.
- **Results table** below: Date, Value+unit, Range, Flag (in/out, colour-coded),
  Timing (pre/post), Note.
- Back gesture returns to Scorecard.

*Charting in Flutter: `fl_chart` is the closest equivalent to the current Recharts
setup.*

---

## Screen 3 — Inventory

Stock tracking + delivery-cycle management for dialysis consumables.

- App bar: "Inventory", hamburger.
- **Navigation:** drawer destination. All actions (log event, order, delivery,
  history, cycle dates) open as **bottom sheets** over this screen — none are
  separate routes. Dismiss a sheet via drag-down or X to return.
- **Delivery cycle banner** (top): next call-date countdown → delivery-date
  countdown. State-dependent buttons: "Set cycle dates" (if none), "Place order" /
  "Apply delivery" (depending on cycle stage), "View order" (between call and
  delivery dates), edit-dates pencil.
- **Action row:** "Log event" + "Deliveries" (history) buttons.
- **Two stock sections**, each a bordered card with divided rows:
  1. **NxStage Supplies**
  2. **Hospital Prescriptions**
- **Each stock row:** item name, current count + unit (bags / cartridges / boxes /
  pieces — correct per item, never generic "box"), colour-coded low-stock
  indicator (emerald / amber / red against par level), − / + buttons for manual
  ±1 adjustment.
- **PAK-001 special row:** "Installed `DD MMM` · `N`/10 sessions" with colour
  (green <8, amber 8–9, red ≥10).
- Rows sorted by urgency (lowest-stock-relative-to-par first).

**Modals (all bottom sheets in Flutter):**
- **Log event** — tabbed: *Session log* (deducts standard per-session consumables,
  previews before confirm) · *Manual adjust* (per-item ±) · *Stock count* (set
  actual counts) · *PAK install* (set date, resets counter).
- **Place order** — stock-count step → calculated order quantities → per-item
  − / + adjust → confirm.
- **Apply delivery** — expected items with per-item − / + adjust → confirm
  receipt. Auto-applies on load if delivery date has passed.
- **View order** — read-only summary of the placed order, quantities in boxes,
  expected delivery date, optional "Early delivery" action.
- **Delivery history** — list of past deliveries (date + items in boxes).
- **Set / edit cycle dates** — two date pickers (call date auto-suggests
  delivery = +7 days).

---

## Screen 4 — Fitness

Pipeline-verification + latest readings from Google Health (Fitbit) data. 9 types.

- App bar: "Fitness", hamburger, **"Sync now"** action (right, refresh icon, spins
  while syncing).
- **Navigation:** drawer destination. No sub-screens — everything renders inline.
- **Health line:** check/warning icon + "Last sync `X` ago · `N`/9 types healthy".
- **Latest readings card:** 2-column grid of metric tiles, each: icon + value +
  unit + small label. Metrics: Steps (footprints), Resting HR (heart), Sleep (moon
  — total + deep minutes), SpO₂ (droplet — labelled "latest sample"), HRV daily
  (activity), Respiratory rate (wind), Skin temp (thermometer).
- **Pipeline status table:** one row per type — icon + name, data-point count, last
  date, status indicator (emerald check / amber warning / red error). Heart-rate
  (raw) and HRV (raw) are status-only rows.
- **Footer:** "`X` MB stored in GCS".
- **Data behaviour:** 12h local cache, show cached instantly, refresh in background.

---

## Screen 5 — Knowledge Base

- App bar: "Knowledge Base", hamburger.
- **Navigation:** drawer destination. No sub-screens yet.
- Placeholder for now: centred muted text "NxStage error codes — coming soon."
  (Future: searchable error/alert database.)

---

## Screen 6 — Chat (FAB overlay — NEW, backend not built yet)

A RAG assistant over BP, blood tests, fitness, inventory, and the KB. **Backend
endpoint does not exist yet** — design the UI now; wire it when the API lands.

### Entry & container
- **Navigation:** opens from the bottom-right Chat FAB as a **bottom sheet sliding
  to ~85% screen height** (drag-down handle at top, or close X). It's an **overlay,
  not a route** — it floats over whatever screen is underneath, and dismissing it
  returns to that exact screen. The FAB is hidden while the sheet is open.
- A short grab-handle bar (rounded, slate-600) sits centred at the very top of the
  sheet for the drag-to-dismiss affordance.

### Header
- Left: **assistant avatar** (small, ~28px) + "Assistant" title.
- Right: "New chat" text button (clears the conversation) + close **X**.

### Assistant icon / avatar
- A **circular avatar**, ~28px in the header and ~32px beside each assistant
  message. Filled with `accent` (or a cyan→teal gradient), glyph in `accent-on` —
  correct in both light and dark modes.
- **Glyph:** a friendly medical-assistant mark — a **rounded chat bubble with a
  small pulse/heartbeat line (ECG zigzag) inside it**, echoing the app's droplet+ECG
  brand icon. This visually ties the assistant to the HD domain (heartbeat) and to
  "chat" (bubble) at once. Single-colour line glyph, no detail noise.
- Alternative if a simpler mark is wanted: a `Sparkles`/`Bot`-style glyph in the
  same cyan circle. Keep it consistent everywhere the assistant appears.
- The **user** has no avatar (their bubble alignment is enough).

### Message bubbles (shape matters)
- **Assistant messages — left-aligned.** Bubble fill = `panel`, text =
  `text-primary`. Shape: rounded corners **~16px on three corners, but the
  bottom-left corner is small/squared (~4px)** so the bubble appears "anchored" to
  the avatar on its left (a subtle tail effect without drawing an actual tail).
  Avatar sits to the **left**, vertically aligned to the bubble's top. Full
  **markdown rendering** inside (tables, bullet lists, bold, inline code).
- **User messages — right-aligned.** Bubble fill = **accent-tinted** (`accent` at
  low opacity, e.g. `accent/15`) with a subtle `accent` border; text =
  `text-primary`. Shape: rounded **~16px on three corners, bottom-right corner
  small/squared (~4px)** so it anchors to the right edge — mirror image of the
  assistant bubble. Plain text (no markdown needed).
- Comfortable max bubble width ~80% of sheet width; consecutive messages from the
  same side stack with small vertical gaps.
- **Auto-scroll** to the newest message on send and on response.

### Thinking indicator
- While awaiting a response: an assistant-side bubble containing **three animated
  bouncing dots** (typing-indicator style), same panel fill and avatar as a normal
  assistant message.

### Input row
- Pinned to the bottom of the sheet, **keyboard-aware** (rises with the keyboard).
- A rounded multiline text field (`panel` fill, `border` outline) + a circular
  pill **send button** (`accent` fill, `accent-on` paper-plane/`Send` icon). Send is
  disabled while the field is empty or a response is in flight.

### Empty state
- Centred assistant avatar + a one-line greeting, then **2–3 tappable suggestion
  chips** that pre-fill and send: "How's my blood pressure trending?",
  "When's my next delivery?", "Show my recent HRV".

- Conversation persists in local storage within a session; "New chat" wipes it.

---

## Cross-cutting behaviours (every data screen)

1. **Cache-first rendering** — show local cached data instantly, then refresh in
   the background. Never block render on the network (Cloud Run cold-starts make
   blocking painful).
2. **Three states per screen:** loading (only on truly empty cache), ready, error
   (with Retry). Background-refresh failures keep showing cached data — never
   blank the screen.
3. **Auth:** a single API key entered once on Setup. On any 401, route back to
   Setup with a message.
4. **Optimistic writes** with per-item status + retry (most important on Active
   session readings and inventory adjustments).
5. **Theme-agnostic:** every screen uses the colour *tokens* only (never a literal
   light/dark colour), so light and dark both render correctly with no per-screen
   branching. Follows `ThemeMode.system` by default.
6. **Pill buttons everywhere:** all tappable buttons are fully-rounded pills (see
   Shape language); cards, sheets, and inputs keep their soft-rounded corners.
7. **Motion:** transitions and feedback follow the Animation & motion table —
   subtle, fast, ease-out, and honouring "reduce motion".

---

## Setup / Settings

### Setup screen
- **Navigation:** the app's gate. Shown on first launch and whenever no valid key
  is stored (or after a 401, or after Clear credentials). Not a drawer destination
  and has **no hamburger** — it's the pre-auth screen. On success it **replaces**
  itself with Treatment Home.
- App bar: "Setup" (no hamburger).
- Single **password field** "Main API key" (no autocomplete / autocorrect /
  autocapitalise), "Save and continue" button that verifies the key against the API
  then proceeds. Error shown inline (red text).

### Settings screen
- **Navigation:** drawer destination (shows hamburger). Reached from the drawer's
  Settings item.
- App bar: "Settings", hamburger.
- **"Clear credentials" button** — the primary control. **Pill-shaped, destructive
  style** (red outline + red text, red fill on press) — uses the red status token at
  the mode-appropriate shade so it reads as danger in both light and dark. Tapping
  shows a **confirmation dialog** ("Clear all saved credentials on this device?" —
  Cancel / Clear, both pill buttons). On confirm: wipes the stored API key + any
  Firebase/treatment tokens from secure storage, then routes to **Setup**.
- **Theme control:** a segmented pill toggle for **System / Light / Dark** (defaults
  to System) so the user can override `ThemeMode.system`.
- Room to grow below it (dried-weight default, notification prefs) — leave a section
  placeholder.

---

## Backend wiring reference (for when Flutter code returns)

The backend is unchanged and language-agnostic. Flutter packages map cleanly:

| Layer | Flutter package | Backend it talks to |
|---|---|---|
| Firebase auth | `firebase_auth` + `signInWithCustomToken` | custom token from `GET /api/treatment/token` |
| Treatment reads/writes | `cloud_firestore` | `treatment_sessions` / `treatment_readings` collections |
| Blood Tests / Inventory / Fitness | `dio` or `http` + `Authorization: Bearer <key>` | `/api/blood-tests`, `/api/inventory`, `/api/fitness/*` |
| API key storage | `flutter_secure_storage` | replaces IndexedDB `homehd-auth` store |
| Local cache | `shared_preferences` or `hive` | replaces localStorage caches |

The Flutter app is a native Android APK, not a PWA — distribution is sideload/Play
Store, and the Blood Tests dashboard on desktop still needs the web app (or run
both in parallel during transition).
