# Flutter migration: Home HD on web + mobile (single codebase)

Combined spec + implementation plan. Ports the existing React PWA frontend to a single
Flutter/Dart codebase that targets **both web and mobile** from one source. The new UI follows
`docs/flutter-ui-brief.md` (side drawer replaces bottom tabs; persistent Chat FAB added).
Backend is unchanged — this is a pure client port. Approved in design session 2026-06-02.

## Goal

Replace the React PWA (`frontend/`) with a Flutter app that:
- **Runs on web and mobile from one codebase** — Flutter web served from `homehd.web.app`
  (same origin as the API) plus a native Android/iOS build from the same source.
- **Adopts the new UI** in `docs/flutter-ui-brief.md` — left side drawer instead of bottom
  tabs, persistent Chat FAB, light + dark themes via a single token set.
- **Reuses the existing backend untouched** — same Cloud Run REST contract
  (`docs/api-reference.md`) and the same client-side Firestore + custom-token model for
  Treatment.
- **Gains native capability on mobile** — local notifications + vibration for the
  Active-session timer alerts (a real upgrade over the web-only "notify when open").

## What changes / what stays the same

**Changes:**
- New `flutter/` directory in the repo, alongside `api/` and `frontend/`.
- New client implementation in Dart: REST client, Firestore/auth layer, secure-storage and
  cache layers, all screens.
- New navigation shape (drawer + Chat FAB) per the brief — a deliberate UX change from the
  React app's bottom tabs.
- Firebase Hosting serves the Flutter web build (coexists with React during transition; React
  retired at the end).

**Unchanged (do not touch):**
- `api/` — every Cloud Run endpoint and its contract.
- Firestore collections, document IDs, field names, and security rules.
- `GET /api/treatment/token` custom-token flow and the `treatment_*` Firestore model.
- The Google Sheet weekly sync (clinical team workflow).
- `MAIN_API_KEY` as the single user-managed credential.
- The React `frontend/` — stays live and deployable until Flutter reaches parity.

## Architecture

```
                         ┌──────────────────────────────────────────────┐
                         │  Flutter app (one codebase)                   │
                         │  targets: web (homehd.web.app) + Android/iOS  │
                         └──────────────────────────────────────────────┘
                              │                              │
   Bearer <MAIN_API_KEY>      │                              │  Firebase custom token
   (dio, 401→Setup)           │                              │  (signInWithCustomToken)
                              ▼                              ▼
   Cloud Run REST  ◀── /api/blood-tests           Firestore (client SDK)
   (unchanged)         /api/inventory/*            treatment_sessions/{id}
                       /api/fitness/*              treatment_readings/{id}
                       /api/treatment/token        (rules: uid == 'homehd-treatment')
                       /api/chat (placeholder)
```

Layered Dart structure mirrors the React module boundaries (`frontend/src`):

```
flutter/
  lib/
    main.dart                 app entry, ProviderScope, theme, router
    app/
      router.dart             go_router: Setup gate + drawer destinations + pushed sub-routes
      shell.dart              Scaffold with drawer, app bar, shared Chat FAB
      theme.dart              light + dark ColorScheme from the brief's token table
    api/
      rest_client.dart        dio instance: Bearer interceptor, 401→Setup interceptor
      blood_tests_api.dart    GET/POST /api/blood-tests
      inventory_api.dart      GET + POST/PUT/PATCH /api/inventory/*
      fitness_api.dart        GET /api/fitness, /summary; POST /sync
    firebase/
      firebase_init.dart      Firebase.initializeApp (web + mobile options)
      treatment_auth.dart     token fetch + signInWithCustomToken + authStateReady race fix
    storage/
      secure_store.dart       flutter_secure_storage — MAIN_API_KEY
      cache.dart              hive boxes — stale-while-revalidate caches per screen
    models/                   Dart models + JSON (de)serialization, one per domain
    features/
      treatment/              home, pre, active, post + local active-session state
      blood_tests/            scorecard + trend tabs (fl_chart)
      inventory/              stock list + bottom-sheet flows
      fitness/                summary + pipeline table
      kb/                     placeholder
      chat/                   UI only (mock responses; backend not built)
      settings/               clear credentials, theme toggle
  web/                        index.html, manifest, Firebase web config
  pubspec.yaml
```

### State management & routing
- **Riverpod** for state (providers per feature; `AsyncNotifier` for cache-first
  load→revalidate). **go_router** for navigation (declarative Setup gate redirect on missing
  key / 401; drawer destinations as top-level routes; Pre/Active/Post pushed sub-routes).

### Design system
Single token set → two `ColorScheme`s (light + dark) from the brief's table; `ThemeMode.system`
default, manual override persisted in Settings. `StadiumBorder` pill buttons app-wide; cards /
sheets / inputs keep 12–16px corners. Monospace for timers/IDs/readings. `fl_chart` for the
Blood Tests trend chart (closest equivalent to the React Recharts setup).

## Package mapping (React → Flutter)

| Concern | React (today) | Flutter |
|---|---|---|
| REST calls | `fetch` (`text/plain` CORS workaround) | `dio` (same-origin → no preflight) |
| Treatment auth | Firebase JS SDK | `firebase_auth` + `signInWithCustomToken` |
| Treatment data | Firebase JS Firestore | `cloud_firestore` |
| API key storage | IndexedDB `homehd-auth` | `flutter_secure_storage` |
| Local caches | localStorage / IndexedDB | `hive` |
| Charts | Recharts | `fl_chart` |
| Validation | zod | model `fromJson` + manual guards (port `stripEmptyRows` defense) |
| Notifications | Web Notifications (open-only) | `flutter_local_notifications` + `vibration` (mobile) |
| Icons | lucide-react | `lucide_icons` (or Material equivalents) |

## Per-platform behavior (explicit — the brief's "maps cleanly" table hides these)

| Concern | Mobile (Android/iOS) | Web |
|---|---|---|
| Active-session timer alerts (2h/1h/5m) | local notification + vibration even when backgrounded | **in-app banner only** — web cannot notify a closed tab. Documented limitation, not a bug. |
| `flutter_secure_storage` | Keystore / Keychain | weaker browser-backed store (acceptable for single-user; noted) |
| REST CORS | n/a (native client) | **must serve Flutter web same-origin from `homehd.web.app`** or REST calls hit preflight (the note documents a prior CORS saga). No Cloud Run CORS change if same-origin. |
| Firestore / custom-token auth | FlutterFire native | FlutterFire web — supported; the `authStateReady()` race fix applies to both |
| App-state restore on force-quit | OS-level | tab close = process end; rely on cache + active-state restore |

## Hosting / coexistence with React

- During transition, Firebase Hosting serves the Flutter web build at a **preview/secondary
  path or channel** while `homehd.web.app` root still serves React, so REST stays same-origin
  for both. `/api/**` rewrites to Cloud Run are untouched.
- At parity cutover, point the `homehd.web.app` production hosting target at the Flutter
  `build/web` output and stop deploying React. `firebase.json` rewrite changes only the static
  asset source, never the `/api/**` rule.
- Mobile distribution: Android APK/AAB (sideload first, Play Store later); iOS optional via the
  same codebase.

---

## Implementation tasks

Build order is by **risk**, not by screen number. Each task is independently verifiable.

### Phase 0 — Scaffold & shell
1. **Project init.** `flutter create flutter/` in the repo (web + Android + iOS platforms).
   Add deps: `flutter_riverpod`, `go_router`, `dio`, `firebase_core`, `firebase_auth`,
   `cloud_firestore`, `flutter_secure_storage`, `hive`/`hive_flutter`, `fl_chart`,
   `flutter_local_notifications`, `vibration`, `lucide_icons`.
   *Verify:* `flutter run -d chrome` shows the default app; `flutter build apk --debug` succeeds.
2. **Theme tokens.** `app/theme.dart` — light + dark `ColorScheme` from the brief's token table;
   `StadiumBorder` button themes; monospace text style for values.
   *Verify:* a throwaway screen with one pill button and one card renders correctly in both
   `ThemeMode.light` and `.dark` (toggle in a test harness).
3. **FlutterFire init.** `flutterfire configure` against project `homehd-personal`; commit
   `firebase_options.dart`. `firebase_init.dart` initializes for web + mobile.
   *Verify:* `Firebase.initializeApp()` completes without error on `-d chrome` and on device.
4. **App shell + router + Setup gate.** `shell.dart` (drawer with the 6 destinations + divider +
   Settings, top app bar, shared Chat FAB rendered once at scaffold level); `router.dart`
   (go_router with a redirect to Setup when no key is stored). Chat FAB opens an empty bottom
   sheet placeholder for now.
   *Verify:* drawer navigates between empty placeholder screens; with no stored key the app
   lands on Setup; FAB is pixel-identical on every authenticated screen.
5. **Setup + secure storage + REST client.** Setup screen (single password field "Main API
   key", verify against API before save) → `secure_store.dart`; `rest_client.dart` dio instance
   with Bearer interceptor + a 401 interceptor that clears the key and redirects to Setup.
   *Verify:* entering the real key (from Keychain `homehd-main-key`) passes verification and
   lands on Treatment Home; entering a wrong key shows the inline error; a forced 401 routes
   back to Setup.

### Phase 1 — Treatment (riskiest: client Firestore + custom-token auth)
6. **Treatment auth layer.** `treatment_auth.dart` — `GET /api/treatment/token` →
   `signInWithCustomToken`; **`await firebaseAuth.authStateReady()` before reading
   `currentUser`** and a **20s `Future` timeout** around sign-in (port the fix at vault note
   2026-06-01). Token cached in secure storage, refreshed within 10 min of expiry.
   *Verify:* cold open signs in and reaches Home in <100ms when a cached user exists; with auth
   forced to hang, the screen shows a Retry within 20s instead of stalling.
7. **Treatment models + Firestore repo.** Dart models for session/reading (numbers as numbers);
   `cloud_firestore` reads/writes to `treatment_sessions` / `treatment_readings`; port the
   empty-row guard (`stripEmptyRows` equivalent).
   *Verify:* reads the existing 11 sessions / 33 readings back with correct types; a test write
   to a scratch doc round-trips.
8. **Home.** Start-session CTA (disabled+spinner until sessions load), dried-weight inline edit
   (default 59, persisted locally), recent-5 sessions (date, pre→post BP, total UF, duration),
   cache-first render. Empty + error states with Retry.
   *Verify:* shows cached sessions instantly then revalidates; empty and error states render.
9. **Pre form.** 2-col decimal grid; UF goal auto = `weight − dried_weight`, UF rate auto =
   `uf_goal ÷ 0.004`, both editable & revert-on-clear (port the `*Touched` pattern). EPO +
   Heparin toggles. Creates the session record → Active.
   *Verify:* auto-fill + manual-override + clear-reverts behaves exactly as the React form;
   submit writes the session.
10. **Active session.** Pre-values reference card; countdown timer (target default 255 min,
    editable, starts on first reading, emerald→amber→red colour shifts, overtime `+H:MM:SS`);
    Add-reading bottom sheet (time=now, blood_flow defaults to last reading); readings list
    newest-first with per-row optimistic save status (spinner→check / error+Retry);
    "Consumed this session" card (needles 2, on/off packs 1); sticky Heparin toggle; End→Post.
    *Verify:* timer counts down and shifts colour; readings save optimistically and recover on
    error; force-quit restores to Active with in-flight reading marked interrupted + Retry.
11. **Active timer alerts (per-platform).** 2h/1h/5m: in-app banner on all platforms;
    `flutter_local_notifications` + `vibration` additionally on mobile.
    *Verify:* on device, a backgrounded app fires the notification + vibration; on web only the
    in-app banner shows (and this is documented as expected).
12. **Post form + consume-on-end.** Numeric fields (duration default 255, dialysate 49, total UF
    auto = `pre_weight − post_weight`), EPO/Heparin shown from earlier (single source of truth
    per session), Finish → writes post values, fires the inventory `session` deduction event,
    clears active-state cache, returns to Home.
    *Verify:* finishing writes post values, posts the inventory event, and clears the local
    active-session state.

### Phase 2 — Read-heavy screens
13. **Blood Tests data + Scorecard.** `blood_tests_api.dart` (`GET /api/blood-tests` with
    marker/phase/from/to); cache-first with 6-month default window; Scorecard tiles (latest
    value, delta arrow, in/out-of-range badge, ref range), favourites pinned + persisted.
    *Verify:* tiles render from cache then revalidate; favourites persist; out-of-range badges
    correct against `ref_low`/`ref_high`.
14. **Blood Tests Trend.** `fl_chart` line chart, stepped reference-range band, pre/post by
    colour, phase-boundary lines, out-of-range points highlighted; results table below; tile→
    Trend and Android-back→Scorecard.
    *Verify:* tapping a tile opens its trend; chart matches the React chart for a sample marker;
    back returns to Scorecard.
15. **Fitness.** `fitness_api.dart` (`GET /api/fitness/summary`); health line (N/9 healthy),
    latest-readings grid, pipeline status table, GCS-bytes footer, "Sync now" → `POST
    /api/fitness/sync` (spins). 12h cache.
    *Verify:* summary renders from cache then refreshes; Sync now triggers a sync and updates
    counts; status-only types (heart-rate, HRV) render without a latest value.

### Phase 3 — Write-heavy
16. **Inventory list.** `inventory_api.dart` (`GET /api/inventory`); two stock sections (NxStage
    / Hospital), per-row count + correct unit + low-stock colour vs par, −/+ optimistic ±1
    (`POST /api/inventory/event` manual), PAK special row, urgency sort, delivery-cycle banner.
    *Verify:* stock renders; ±1 updates optimistically and persists; PAK row shows N/10 with the
    right colour; cycle banner reflects current cycle state.
17. **Inventory bottom sheets.** Log event (session/manual/stock-count/PAK install), Place order
    (count→calc→adjust→confirm via `confirm-order`/`PATCH order`), Apply delivery
    (`apply-delivery`, auto-apply when delivery date passed), View order, Delivery history
    (`GET /deliveries`), Set/edit cycle dates (`update-cycle-dates`, delivery auto +7d).
    *Verify:* each sheet round-trips against the live API; confirm/apply mutate stock and cycle
    as the React app does.

### Phase 4 — KB, Chat, Settings
18. **Knowledge Base.** Placeholder screen ("NxStage error codes — coming soon").
    *Verify:* renders as a drawer destination.
19. **Chat UI (no backend).** Bottom sheet to ~85% height, assistant avatar (chat-bubble+ECG
    glyph), anchored-corner bubbles (assistant left/panel, user right/accent-tinted), markdown
    rendering for assistant, thinking-dots indicator, keyboard-aware input + send pill, empty
    state with suggestion chips. **Mock response source** behind an interface so the real
    `/api/chat` drops in later.
    *Verify:* sending shows a user bubble + thinking dots + a mock assistant reply with markdown;
    "New chat" clears; sheet drag-dismisses and restores the underlying screen.
20. **Settings.** Clear credentials (destructive pill + confirm dialog → wipes secure storage →
    Setup); theme segmented toggle (System/Light/Dark) persisted; placeholder section for
    dried-weight default + notification prefs.
    *Verify:* Clear credentials wipes the key and routes to Setup; theme toggle switches and
    persists across restart.

### Phase 5 — Web hosting & cutover
21. **Flutter web on a Firebase Hosting channel.** Build `flutter build web`; serve from a
    secondary hosting target/channel under `homehd.web.app` so REST stays same-origin; verify no
    CORS preflight failures and Firestore auth works in the browser.
    *Verify:* the deployed web build loads, Setup→Treatment works end-to-end, REST + Firestore
    both succeed with no CORS errors in the console.
22. **Parity sign-off + cutover.** After real-session use on mobile + web, repoint the
    production hosting target to `build/web` and stop deploying React. Keep `frontend/` in the
    repo until confident.
    *Verify:* `homehd.web.app` serves Flutter; a full real dialysis session is recorded through
    the Flutter app end-to-end.

## Testing strategy

- **Unit:** Dart model (de)serialization, the auto-fill `*Touched` derivation logic, session-id
  collision logic, the timer colour-threshold logic, empty-row guard. Mirror the React unit
  tests that already exist.
- **Integration:** REST client against a mock dio adapter (200/401/500 paths); Firestore repo
  against the emulator or a scratch collection.
- **Manual / device:** the per-task verify steps above; the cutover gate is a full real session
  on both a phone and the web build.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Firebase custom-token auth race on web (the bug just fixed in React) | Port `authStateReady()` + 20s timeout as Task 6, before any Treatment UI |
| CORS reappearing on Flutter web | Same-origin hosting on `homehd.web.app` (Task 21); never call Cloud Run cross-origin |
| `fl_chart` not matching Recharts (stepped band, phase lines) | Visual parity check vs React in Task 14 on a sample marker before moving on |
| Native notification scope creep | Mobile-only; web degrades to in-app banner by design (Task 11) |
| Two frontends drift during transition | Backend frozen; React stays deploy-as-is, no new features land there during the port |

## Out of scope
- Any backend / API / Firestore-rules change.
- Building the `/api/chat` endpoint (Chat is UI + mock only this round).
- iOS Play-equivalent distribution setup (codebase supports it; provisioning deferred).
- Retiring the React `frontend/` directory (kept until post-cutover confidence).
