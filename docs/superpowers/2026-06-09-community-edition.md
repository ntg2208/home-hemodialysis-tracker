# Community Edition — Local-First Flutter Flavor

**Date:** 2026-06-09  
**Status:** Design approved, implementation plan pending  
**Scope:** A distributable `community` build flavor of the home HD app for a handful of known other home HD patients, with fully local-first storage (no GCP dependency) and on-demand PDF/CSV export for clinical sharing.

---

## Background

The personal app (`homehd.web.app`) is single-tenant: one GCP project, one Firestore database, blood tests baked into the Docker image, fitness tied to a personal Google Health OAuth token. Distributing it to other patients requires either a per-user cloud setup (too much friction) or a local-first approach where all data lives on-device.

A multi-tenant shared-backend model (users sign up, developer hosts Firestore for everyone, clinical team gets live read access) was also considered and noted as a future option to discuss with the clinical team — see `Home HD Knowledge Base and Tracking System.md` § 2026-06-09. Deferred for now; local-first is the chosen path.

---

## Goals

- Any home HD patient can install the APK and start logging sessions with zero cloud configuration
- Blood test results can be imported from a CSV or entered manually
- Session data and blood test data can be exported as PDF/CSV for clinical team sharing
- The personal app is completely unaffected

---

## Build Flavor

One codebase, two APKs, controlled by a compile-time flag:

```dart
const bool kCommunity = String.fromEnvironment('FLAVOR') == 'community';
```

Community build command:
```bash
flutter build apk --dart-define=FLAVOR=community
```

Personal build is unchanged (no flag set, `kCommunity == false`).

Feature differences:

| Feature | Personal | Community |
|---|---|---|
| Storage | Firestore + Cloud Run API | Hive (on-device only) |
| Treatment auth | Firebase custom token | None |
| Blood tests | Static JSON + Firestore overlay | Hive + CSV import + manual entry |
| Fitness | Google Health API (OAuth) | **Excluded** |
| Inventory | Firestore | Hive |
| KB / Chat history | Firestore | Hive |
| Chat FAB | Always visible | Hidden unless AI Studio key is set |
| Setup wizard | mainKey entry | None (no wizard) |
| Settings | Theme + clear credentials | Theme + patient name + dry weight + AI Studio key + CSV template download |

---

## Storage Layer

Hive is already used for `ActiveState` (in-progress session) and last-session cache. Community flavor extends Hive to cover all persistent data.

### New Hive boxes

| Box name | Replaces | Primary key |
|---|---|---|
| `sessions` | Firestore `treatment_sessions` | `session_id` |
| `readings` | Firestore `treatment_readings` | `reading_id` |
| `blood_tests` | Static JSON + Firestore overlay | `{date}_{marker}` |
| `inventory_stock` | Firestore `inventory` | item code |
| `inventory_events` | Firestore `inventory_events` | event id |
| `inventory_config` | Firestore `inventory_config` | key |
| `kb_entries` | Firestore `kb_entries` | entry id |
| `chat_conversations` | Firestore `chat_conversations` | convo id |

### Repository interface pattern

Every screen talks to an abstract repository interface. Riverpod providers return the right implementation based on `kCommunity`:

```dart
abstract class SessionRepository {
  Future<List<Session>> getSessions();
  Future<void> saveSession(Session s);
  Future<void> updateSession(String id, Map<String, dynamic> fields);
  Future<void> deleteSession(String id);
}

class HiveSessionRepository implements SessionRepository { ... }
class FirestoreSessionRepository implements SessionRepository { ... }
```

Same pattern for `BloodTestRepository`, `InventoryRepository`, `KbRepository`, `ChatRepository`.

No screen code changes — all screens talk to the interface. The Riverpod provider switches implementation:

```dart
final sessionRepoProvider = Provider<SessionRepository>((ref) =>
  kCommunity ? HiveSessionRepository() : FirestoreSessionRepository());
```

### Firebase / Firestore init

Community flavor skips Firebase entirely. In `firebase_init.dart`, `Firebase.initializeApp()` is guarded by `if (!kCommunity)` — it simply returns without initialising on community builds. `TreatmentAuth.ensure()` becomes a no-op. All Firestore/Auth calls are behind Hive repository paths that are never reached. `cloud_firestore` and `firebase_auth` may remain in `pubspec.yaml` as unused dependencies (tree-shaken at compile time) to avoid splitting the dependency graph.

---

## Blood Test Entry

Two paths, both write to the Hive `blood_tests` box.

### CSV import (fast path)

"Import CSV" button (on the Blood Tests screen) opens the system file picker. Expected format — a template the user downloads from Settings:

```csv
date,marker,value,unit,ref_low,ref_high,timing,note
2026-06-01,creatinine,1043,umol/L,64,104,pre,
2026-06-01,urea,18.2,mmol/L,2.5,7.8,pre,
2026-06-01,potassium,5.1,mmol/L,3.5,5.1,,
```

Parser runs entirely on-device:
1. Reads file, splits rows
2. Validates: non-empty marker name, numeric value, valid ISO date, ref_low < ref_high where both are present
3. Shows a preview table — valid rows in green, error rows in red with reason
4. "Import N rows" confirm button; skips rows with errors (or user can cancel and fix the file)
5. Writes to Hive; existing rows with matching `{date}_{marker}` key are overwritten (re-import is idempotent)

Marker names are not validated against the canonical list — any non-empty string is accepted. This allows data from hospitals using different naming conventions. The canonical 51-marker list is only used for auto-filling defaults in manual entry.

### Manual entry (fallback)

"Add result" button → a bottom sheet:

- **Date picker** — defaults to today
- **Marker picker** — searchable list, sorted A–Z. Type to filter. Tapping a marker auto-fills unit, ref_low, and ref_high from the marker definition (standard clinical reference ranges baked into the app). All three fields remain editable.
- **Value** — numeric input
- **Unit** — pre-filled from marker definition, editable (text field)
- **Ref low / Ref high** — pre-filled from marker definition, editable
- **Timing** — segmented control: Pre · Post · None
- **Note** — optional text field
- **"Add another" button** — saves current row and resets to a blank form for the same date (for batch entry of a full blood draw without closing the sheet)

### Blood Test view (community)

The phase filter (admission / in-center-hd / home-hd) and the "All phases" button are both removed from the community flavor — the phase model is derived from a specific clinical history that other patients don't share. The filter bar shows time range only (e.g. last 3 months / last 6 months / last year / all time). Scorecard and Trend chart behaviour is otherwise unchanged.

### Marker definitions

A static `const List<MarkerDefinition>` in the app, covering the 51 canonical markers with their standard ranges:

```dart
class MarkerDefinition {
  final String name;        // canonical key, e.g. 'creatinine'
  final String displayName; // e.g. 'Creatinine'
  final String defaultUnit;
  final double? refLow;
  final double? refHigh;
}
```

Ranges are a starting point — each patient's lab may differ, which is why every entry remains editable. The app does not enforce the default ranges.

---

## PDF Export

Generated entirely on-device using the `pdf` package. No server involved.

### Session detail PDF

Accessible from the session list — share icon on each row (or long-press).

Contents:
- **Header:** patient name (from Settings), date, session ID
- **Pre-treatment:** weight, UF goal, UF rate, BP sys/dia, pulse, heparin flag, EPO flag
- **Readings table:** time · BP sys/dia · pulse · blood flow · VP · AP · note
- **Post-treatment:** weight, BP sys/dia, pulse, duration, dialysate vol, total UF, blood processed
- **Session comment** (if present)
- **Footer:** "Generated {date} · Home HD Tracker"

### Monthly summary PDF

A date-range export of multiple sessions. "Export range" option alongside single-session share.

- Default range: last 30 days
- One row per session: date · duration · pre BP · post BP · UF goal · UF actual · UF% · comment snippet
- Designed to be handed to the clinical team at a review appointment

### Blood test CSV export

Blood test data exports as CSV in the same format as the import template — useful for clinical teams who want to load it into their own systems. Accessible from the Blood Tests screen (export button in the app bar).

---

## Settings (Community Flavor)

Replaces the mainKey Setup Wizard. A simple settings screen with:

| Setting | Purpose |
|---|---|
| Patient name | Used in PDF export headers |
| Dry weight (kg) | Drives UF goal auto-calculation (`weight − dry_weight`) on the Pre-treatment form. Currently hardcoded to 59 kg in personal build. Defaults to 0 (unset). Pre-treatment form prompts "Set your dry weight in Settings first" and disables the Start Session button until a value > 0 is saved. |
| AI Studio key | Optional. Enables Chat. Stored in `flutter_secure_storage`. If blank, Chat FAB is hidden. |
| Download CSV template | Saves the blood test import template to the device Downloads folder |
| Theme | System / Light / Dark (same as personal) |
| Clear all data | Wipes all Hive boxes. Confirmation dialog. |

---

## Chat FAB

In the community flavor, `kCommunity == true` causes the Chat FAB to render only when an AI Studio key is present in `flutter_secure_storage`. The Settings screen is the discovery point — no "configure in Settings" nudge in the UI, just the key field in Settings.

The Chat feature itself is unchanged: same `ChatResponder` interface, same Gemini streaming, KB entries stored in Hive instead of Firestore.

---

## Distribution

### Primary: PWA via Firebase Hosting (second site)

A second Firebase Hosting site on the existing `homehd-personal` project:

```bash
firebase hosting:sites:create homehd-community --project homehd-personal
# → homehd-community.web.app
```

The community Flutter web build deploys there:

```bash
flutter build web --dart-define=FLAVOR=community
firebase deploy --only hosting:homehd-community --project homehd-personal
```

Patients open `homehd-community.web.app` in Chrome (Android) or Safari (iOS) and tap "Add to Home Screen" — installs as a PWA with no sideloading required. Updates are automatic: redeploy once, everyone gets it on next open.

The community app does not use Firebase at runtime (`kCommunity` skips `initFirebase()`). Firebase Hosting serves the Flutter web files as static assets only.

**PDF on web:** the `pdf` package triggers a browser download instead of the Android share sheet. Same package, different output call.

**Storage on web:** `flutter_secure_storage` falls back to `localStorage` on web (weaker than Android Keystore). Only affects the optional AI Studio key. Health data sits in IndexedDB via Hive.

### Fallback: Android APK

For patients who prefer native Android or have trouble with PWA install:

```bash
flutter build apk --dart-define=FLAVOR=community
```

Share the APK via WhatsApp / email. Requires enabling "Install from unknown sources" in Android settings once. Updates require resharing the APK.

### Version number

Visible in Settings so patients can confirm they have the latest build.

---

## What Is Not Changing

- Personal app at `homehd.web.app`: completely unaffected. Same Firestore, same Cloud Run, same GCP project.
- The repository interface abstraction is an additive refactor — existing Firestore repositories remain the personal-flavor implementations.
- Fitness tab: excluded from community flavor entirely. No Google Health API OAuth flow for community users.

---

## Open Questions (Not Blocking)

- **Shared-backend model** (future): a multi-tenant Firebase project where the developer acts as provider — users sign up with email, clinical team gets live read access from the ward. Flagged for discussion with clinical team. See `Home HD Knowledge Base and Tracking System.md` § 2026-06-09.
- **Marker list completeness**: the 51-marker vocabulary covers Imperial PKB + London North West PKB data. Other hospitals may use different marker names — the manual entry path handles unknowns, but the searchable list won't include them. Consider a free-text "other marker" escape hatch.
- **PDF library**: `pdf` (pub.dev) is the standard Flutter choice. Confirm it handles the readings table layout at variable row counts without overflow.
