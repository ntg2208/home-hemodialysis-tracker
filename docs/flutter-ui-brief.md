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

**Theme: dark, medical-utility.** Calm, high-contrast, readable at a glance during
dialysis. Not playful.

| Token | Value | Used for |
|---|---|---|
| `bg` | very dark slate (`#0F172A`-ish) | screen background |
| `panel` | dark slate (`#1E293B`) | cards, list rows, input fields |
| `accent` | cyan (`#22D3EE`) | primary buttons, active states, links |
| border | slate-700 (`#334155`) | card/input outlines, dividers |
| text primary | slate-100 | values, headings |
| text secondary | slate-400 | labels |
| text muted | slate-500 | hints, timestamps |

**Status colours (consistent everywhere):** emerald = good / in-range / saved ·
amber = warning / stale · red = error / out-of-range / critical · rose =
blood-pressure & heart metrics.

**Typography:** numeric values use a slightly larger, semibold weight. Timers,
session IDs, and reading values use a **monospace** font. Labels are small,
uppercase-tracked for section headers.

**Spacing:** generous — single-column mobile, max content width ~420px centred.
Cards have rounded corners (~12px), 1px border, subtle panel fill.

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

**Chat FAB (NEW):** a persistent `FloatingActionButton` in the **bottom-right
corner of every screen**, accent-coloured, chat-bubble icon. Tapping opens the
Chat panel (last section). Floats above all content; never part of the drawer.

---

## Screen 1 — Treatment

A 4-step flow: **Home → Pre → Active → Post**. State persists locally so a
force-quit mid-session restores exactly where you were (24h TTL).

### 1a. Home

- App bar: "Treatment", hamburger.
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

Placeholder for now: centred muted text "NxStage error codes — coming soon."
(Future: searchable error/alert database.)

---

## Screen 6 — Chat (FAB overlay — NEW, backend not built yet)

A RAG assistant over BP, blood tests, fitness, inventory, and the KB. **Backend
endpoint does not exist yet** — design the UI now; wire it when the API lands.

- Opens from the bottom-right FAB as a **bottom sheet sliding to ~85% screen
  height** (drag-down or X to dismiss).
- **Header:** "Assistant" title, "New chat" button (clears conversation), close X.
- **Message list** (scrollable, fills the sheet): assistant messages left-aligned
  in a panel bubble with markdown rendering (tables, lists, bold); user messages
  right-aligned in an accent-tinted bubble. Auto-scrolls to newest. A "thinking…"
  indicator (animated dots) while awaiting a response.
- **Input row** (pinned bottom, keyboard-aware — shifts up when the keyboard
  opens): multiline text field + send button (accent, disabled while empty or
  awaiting response).
- **Empty state:** brief prompt suggestions ("How's my blood pressure trending?",
  "When's my next delivery?", "Show my recent HRV").
- Conversation persists in local storage within a session.

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

---

## Setup / Settings

**Setup screen** (first launch, or after reset): single password field "Main API
key" (no autocomplete/autocorrect), "Save and continue" button that verifies the
key, then proceeds. Error shown inline.

**Settings** (from drawer): "Reset credentials" — clears stored key, returns to
Setup. Room to grow (theme, dried-weight default, notification prefs).

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
