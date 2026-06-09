# Community Edition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `community` Flutter build flavor with fully local-first Hive storage, blood test CSV import + manual entry, on-device PDF export, and Firebase Hosting PWA distribution — enabling a handful of known other home HD patients to use the app with zero cloud configuration.

**Architecture:** Same Flutter codebase as the personal app; `kCommunity = String.fromEnvironment('FLAVOR') == 'community'` gates all behavior differences. Hive replaces Firestore/Cloud Run via the existing subclass-override pattern (same as `SyntheticTreatmentRepo extends TreatmentRepo`). Firebase init and the Setup gate are skipped in community; users land on Treatment immediately.

**Tech Stack:** Flutter 3.44, Hive 2.2, `pdf` package (on-device generation), `file_picker` (CSV import), `csv` package (parsing), Firebase Hosting second site (`homehd-community.web.app` on the existing `homehd-personal` GCP project).

---

### Task 1: Add dependencies to pubspec.yaml

**Files:**
- Modify: `flutter/pubspec.yaml`

- [ ] **Step 1: Add packages**

In `flutter/pubspec.yaml`, add under `dependencies:` (after `uuid: ^4.5.0`):

```yaml
  pdf: ^3.11.3
  printing: ^5.14.1
  file_picker: ^8.3.7
  csv: ^6.0.0
```

- [ ] **Step 2: Fetch packages**

```bash
cd flutter && flutter pub get
```

Expected: no errors; lock file updated.

- [ ] **Step 3: Commit**

```bash
git add flutter/pubspec.yaml flutter/pubspec.lock
git commit -m "chore: add pdf, file_picker, csv packages for community edition"
```

---

### Task 2: Flavor flag + community Hive box constants

**Files:**
- Create: `flutter/lib/flavor.dart`

- [ ] **Step 1: Write the failing test**

Create `flutter/test/flavor_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/flavor.dart';

void main() {
  test('kCommunity is false when FLAVOR env not set', () {
    expect(kCommunity, isFalse);
  });

  test('community box names are non-empty strings', () {
    expect(communitySessionsBox.isNotEmpty, isTrue);
    expect(communityReadingsBox.isNotEmpty, isTrue);
    expect(communityBtBox.isNotEmpty, isTrue);
    expect(communityInventoryBox.isNotEmpty, isTrue);
    expect(communityEventsBox.isNotEmpty, isTrue);
    expect(communityKbBox.isNotEmpty, isTrue);
    expect(communityChatBox.isNotEmpty, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd flutter && flutter test test/flavor_test.dart
```

Expected: FAIL — `flavor.dart` not found.

- [ ] **Step 3: Create `lib/flavor.dart`**

```dart
const bool kCommunity = String.fromEnvironment('FLAVOR') == 'community';

const communitySessionsBox  = 'community_sessions';
const communityReadingsBox  = 'community_readings';
const communityBtBox        = 'community_bt';
const communityInventoryBox = 'community_inventory';
const communityEventsBox    = 'community_events';
const communityKbBox        = 'community_kb';
const communityChatBox      = 'community_chat';
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd flutter && flutter test test/flavor_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter/lib/flavor.dart flutter/test/flavor_test.dart
git commit -m "feat(community): add kCommunity flavor flag and Hive box name constants"
```

---

### Task 3: Guard Firebase init and main() startup

**Files:**
- Modify: `flutter/lib/firebase/firebase_init.dart`
- Modify: `flutter/lib/main.dart`

- [ ] **Step 1: Guard `initFirebase()` in `firebase_init.dart`**

At the top of `initFirebase()`, before the existing `if (Firebase.apps.isNotEmpty) return;` line, add a community early-return. Open `flutter/lib/firebase/firebase_init.dart` and change:

```dart
Future<void> initFirebase() async {
  if (Firebase.apps.isNotEmpty) return;
```

to:

```dart
Future<void> initFirebase() async {
  if (kCommunity) return;
  if (Firebase.apps.isNotEmpty) return;
```

Add the import at the top:

```dart
import '../flavor.dart';
```

- [ ] **Step 2: Community startup path in `main.dart`**

In `flutter/lib/main.dart`, replace the `main()` body:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initFirebase()
        .timeout(const Duration(seconds: 15), onTimeout: () {
      throw Exception(
          'Firebase initialisation timed out. Check your internet connection and restart the app.');
    });
    await Hive.initFlutter();
    await Hive.openBox(treatmentBoxName);
    await Hive.openBox(cacheBoxName);

    final container = ProviderContainer();
    final auth = container.read(authControllerProvider);
    await auth.load().timeout(const Duration(seconds: 10), onTimeout: () {
      throw Exception(
          'Credential store timed out. Try restarting the app.');
    });

    // Load AI settings (non-fatal — chat just stays in disabled state on failure)
    try {
      await container.read(aiSettingsControllerProvider.notifier).load()
          .timeout(const Duration(seconds: 5), onTimeout: () {});
    } catch (_) {}

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: HomeHdApp(router: buildRouter(auth)),
      ),
    );
  } catch (e) {
    runApp(_StartupErrorApp(message: e.toString()));
  }
}
```

with:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (!kCommunity) {
      await initFirebase().timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception(
            'Firebase initialisation timed out. Check your internet connection and restart the app.');
      });
    }

    await Hive.initFlutter();
    await Hive.openBox(treatmentBoxName);
    await Hive.openBox(cacheBoxName);

    if (kCommunity) {
      await Future.wait([
        Hive.openBox(communitySessionsBox),
        Hive.openBox(communityReadingsBox),
        Hive.openBox(communityBtBox),
        Hive.openBox(communityInventoryBox),
        Hive.openBox(communityEventsBox),
        Hive.openBox(communityKbBox),
        Hive.openBox(communityChatBox),
      ]);
    }

    final container = ProviderContainer();

    if (!kCommunity) {
      final auth = container.read(authControllerProvider);
      await auth.load().timeout(const Duration(seconds: 10), onTimeout: () {
        throw Exception('Credential store timed out. Try restarting the app.');
      });
    }

    try {
      await container.read(aiSettingsControllerProvider.notifier).load()
          .timeout(const Duration(seconds: 5), onTimeout: () {});
    } catch (_) {}

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: HomeHdApp(router: buildRouter(container.read(authControllerProvider))),
      ),
    );
  } catch (e) {
    runApp(_StartupErrorApp(message: e.toString()));
  }
}
```

Add `import 'flavor.dart';` to `main.dart` — the box name constants are top-level so one import covers everything.

- [ ] **Step 3: Skip Setup gate in `router.dart`**

In `flutter/lib/app/router.dart`, add a community early-return at the top of the `redirect` callback:

```dart
redirect: (context, state) {
  if (kCommunity) return null;
  final atSetup = state.matchedLocation == '/setup';
  if (!auth.isAuthed) return atSetup ? null : '/setup';
  if (atSetup) return '/treatment';
  return null;
},
```

Add `import '../flavor.dart';` to router.dart.

- [ ] **Step 4: Verify app compiles**

```bash
cd flutter && flutter build web --dart-define=FLAVOR=community 2>&1 | tail -5
```

Expected: `✓ Built build/web` (or warnings only, no errors).

- [ ] **Step 5: Commit**

```bash
git add flutter/lib/firebase/firebase_init.dart flutter/lib/main.dart flutter/lib/app/router.dart
git commit -m "feat(community): skip Firebase init and Setup gate in community flavor"
```

---

### Task 4: Shell — hide Fitness destination, FAB guard

**Files:**
- Modify: `flutter/lib/app/shell.dart`

- [ ] **Step 1: Hide Fitness from the drawer in community**

In `flutter/lib/app/shell.dart`, add `import '../flavor.dart';` at the top.

In `_HdDrawer.build()`, the `NavigationDrawer` children list currently has 7 items (header + 5 destinations + divider + Settings). Wrap the Fitness destination with a community check. Replace the `const` list with a dynamic one:

```dart
children: [
  const Padding(
    padding: EdgeInsets.fromLTRB(28, 24, 16, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Home HD',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text('Dialysis tracker', style: TextStyle(fontSize: 13)),
      ],
    ),
  ),
  const NavigationDrawerDestination(
    icon: Icon(Icons.monitor_heart_outlined),
    label: Text('Treatment'),
  ),
  const NavigationDrawerDestination(
    icon: Icon(Icons.science_outlined),
    label: Text('Blood Tests'),
  ),
  const NavigationDrawerDestination(
    icon: Icon(Icons.inventory_2_outlined),
    label: Text('Inventory'),
  ),
  if (!kCommunity)
    const NavigationDrawerDestination(
      icon: Icon(Icons.fitness_center_outlined),
      label: Text('Fitness'),
    ),
  const NavigationDrawerDestination(
    icon: Icon(Icons.menu_book_outlined),
    label: Text('Knowledge Base'),
  ),
  const Divider(indent: 28, endIndent: 28),
  const NavigationDrawerDestination(
    icon: Icon(Icons.settings_outlined),
    label: Text('Settings'),
  ),
],
```

Also update `_destPaths` and `_branchIndex` to account for Fitness being absent in community:

```dart
List<String> get _destPaths => kCommunity
    ? ['/treatment', '/blood-tests', '/inventory', '/kb']
    : ['/treatment', '/blood-tests', '/inventory', '/fitness', '/kb'];
```

Change `_destPaths` from a `const` list to a getter. Update the `onDestinationSelected` callback:

```dart
onDestinationSelected: (index) {
  Navigator.of(context).pop();
  final paths = _destPaths;
  if (index < paths.length) {
    context.go(paths[index]);
  } else if (index == paths.length) {
    context.push('/settings');
  }
},
```

Update `_drawerIndex`:

```dart
int _drawerIndex(String location) {
  final paths = _destPaths;
  for (var i = 0; i < paths.length; i++) {
    if (location.startsWith(paths[i])) return i;
  }
  return -1;
}
```

And in `AppShell._branchIndex`:

```dart
static int _branchIndex(String route) {
  if (kCommunity) {
    return switch (route) {
      '/treatment'   => 0,
      '/blood-tests' => 1,
      '/inventory'   => 2,
      '/kb'          => 3,
      _              => 0,
    };
  }
  return switch (route) {
    '/treatment'   => 0,
    '/blood-tests' => 1,
    '/inventory'   => 2,
    '/fitness'     => 3,
    '/kb'          => 4,
    _              => 0,
  };
}
```

- [ ] **Step 2: Remove Fitness branch from router in community**

In `flutter/lib/app/router.dart`, wrap the Fitness branch:

```dart
if (!kCommunity)
  StatefulShellBranch(routes: [
    GoRoute(
        path: '/fitness', builder: (_, _) => const FitnessScreen()),
  ]),
```

The `StatefulShellRoute` branches list becomes:

```dart
branches: [
  StatefulShellBranch(routes: [GoRoute(path: '/treatment', builder: (_, _) => const TreatmentFlow())]),
  StatefulShellBranch(routes: [GoRoute(path: '/blood-tests', builder: (_, _) => const BloodTestsScreen())]),
  StatefulShellBranch(routes: [GoRoute(path: '/inventory', builder: (_, _) => const InventoryScreen())]),
  if (!kCommunity)
    StatefulShellBranch(routes: [GoRoute(path: '/fitness', builder: (_, _) => const FitnessScreen())]),
  StatefulShellBranch(routes: [GoRoute(path: '/kb', builder: (_, _) => const KbScreen())]),
],
```

- [ ] **Step 3: Guard Chat FAB in community**

In `HdScaffold.build()` in `shell.dart`, change the FAB line:

```dart
floatingActionButton:
    floatingActionButton ?? (showChatFab ? const ChatFab() : null),
```

to:

```dart
floatingActionButton: floatingActionButton ??
    (showChatFab && _shouldShowChatFab(ref) ? const ChatFab() : null),
```

Add the helper method to `HdScaffold` (it's a `ConsumerWidget` so `ref` is available in `build`):

```dart
bool _shouldShowChatFab(WidgetRef ref) {
  if (!kCommunity) return true;
  final ai = ref.watch(aiSettingsControllerProvider);
  return ai.ready;
}
```

- [ ] **Step 4: Verify community build compiles**

```bash
cd flutter && flutter build web --dart-define=FLAVOR=community 2>&1 | tail -5
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add flutter/lib/app/shell.dart flutter/lib/app/router.dart
git commit -m "feat(community): hide Fitness tab and gate Chat FAB on AI key in community flavor"
```

---

### Task 5: HiveTreatmentRepo

**Files:**
- Create: `flutter/lib/features/treatment/hive_treatment_repo.dart`
- Modify: `flutter/lib/features/treatment/providers.dart`

- [ ] **Step 1: Write the failing test**

Create `flutter/test/features/treatment/hive_treatment_repo_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:home_hd/features/treatment/hive_treatment_repo.dart';
import 'package:home_hd/features/treatment/models.dart';
import 'package:home_hd/flavor.dart';
import 'dart:io';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(communitySessionsBox);
    await Hive.openBox(communityReadingsBox);
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    Hive.box(communitySessionsBox).clear();
    Hive.box(communityReadingsBox).clear();
  });

  test('saveSession and getAll round-trips', () async {
    final repo = HiveTreatmentRepo();
    final s = Session(
      sessionId: 'test-1',
      date: '2026-06-01',
      preWeight: 62.0,
      postWeight: 59.5,
      ufGoal: 2.5,
      ufRate: 10.0,
      preBpSys: 140,
      preBpDia: 85,
      prePulse: 72,
      postBpSys: 128,
      postBpDia: 78,
      postPulse: 68,
      durationMin: 255,
      dialysateVolume: 30.0,
      totalUf: 2.4,
      bloodProcessed: null,
      comment: null,
    );
    await repo.saveSession(s);
    final result = await repo.getAll();
    expect(result.sessions.length, 1);
    expect(result.sessions.first.sessionId, 'test-1');
  });

  test('deleteSession removes session and its readings', () async {
    final repo = HiveTreatmentRepo();
    final s = Session(
      sessionId: 'del-1',
      date: '2026-06-01',
      preWeight: 62.0, postWeight: 59.5, ufGoal: 2.5, ufRate: 10.0,
      preBpSys: 140, preBpDia: 85, prePulse: 72,
      postBpSys: 128, postBpDia: 78, postPulse: 68,
      durationMin: 255, dialysateVolume: 30.0, totalUf: 2.4,
      bloodProcessed: null, comment: null,
    );
    await repo.saveSession(s);
    await repo.deleteSession('del-1');
    final result = await repo.getAll();
    expect(result.sessions.where((x) => x.sessionId == 'del-1'), isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd flutter && flutter test test/features/treatment/hive_treatment_repo_test.dart
```

Expected: FAIL — file not found.

- [ ] **Step 3: Create `hive_treatment_repo.dart`**

```dart
import 'package:hive/hive.dart';

import '../../flavor.dart';
import 'models.dart';
import 'treatment_repo.dart';

class HiveTreatmentRepo extends TreatmentRepo {
  Box get _sessions => Hive.box(communitySessionsBox);
  Box get _readings => Hive.box(communityReadingsBox);

  @override
  Future<void> saveSession(Session s) async =>
      _sessions.put(s.sessionId, s.toMap());

  @override
  Future<void> saveReading(Reading r) async =>
      _readings.put(r.readingId, r.toMap());

  @override
  Future<void> updateSession(String sessionId, Map<String, dynamic> patch) async {
    final existing = _sessions.get(sessionId);
    if (existing == null) return;
    final merged = Map<String, dynamic>.from(existing as Map)..addAll(patch);
    await _sessions.put(sessionId, merged);
  }

  @override
  Future<List<Reading>> getReadings(String sessionId) async {
    return _readings.values
        .map((v) => Reading.fromMap(Map<String, dynamic>.from(v as Map)))
        .where((r) => r.sessionId == sessionId)
        .toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    final toDelete = _readings.keys
        .where((k) {
          final v = _readings.get(k);
          if (v == null) return false;
          return (v as Map)['session_id'] == sessionId;
        })
        .toList();
    for (final k in toDelete) {
      await _readings.delete(k);
    }
    await _sessions.delete(sessionId);
  }

  @override
  Future<({List<Session> sessions, List<Reading> readings})> getAll() async {
    final sessions = _sessions.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .where((m) => (m['session_id'] as String?)?.isNotEmpty ?? false)
        .map(Session.fromMap)
        .toList();
    final readings = _readings.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .where((m) => (m['reading_id'] as String?)?.isNotEmpty ?? false)
        .map(Reading.fromMap)
        .toList();
    return (
      sessions: List<Session>.unmodifiable(sessions),
      readings: List<Reading>.unmodifiable(readings),
    );
  }
}
```

- [ ] **Step 4: Wire into providers**

In `flutter/lib/features/treatment/providers.dart`, add the import and community branch:

```dart
import '../../flavor.dart';
import 'hive_treatment_repo.dart';
```

Change `treatmentRepoProvider`:

```dart
final treatmentRepoProvider = Provider<TreatmentRepo>((ref) {
  if (kCommunity) return HiveTreatmentRepo();
  if (ref.watch(testModeProvider)) return SyntheticTreatmentRepo();
  return TreatmentRepo();
});
```

- [ ] **Step 5: Run tests**

```bash
cd flutter && flutter test test/features/treatment/hive_treatment_repo_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add flutter/lib/features/treatment/hive_treatment_repo.dart flutter/lib/features/treatment/providers.dart flutter/test/features/treatment/hive_treatment_repo_test.dart
git commit -m "feat(community): HiveTreatmentRepo — local Hive-backed session and reading storage"
```

---

### Task 6: HiveInventoryApi

**Files:**
- Create: `flutter/lib/api/hive_inventory_api.dart`
- Modify: `flutter/lib/features/treatment/providers.dart`

- [ ] **Step 1: Create `hive_inventory_api.dart`**

No unit test needed — all methods are straightforward Hive reads/writes following the same pattern as `SyntheticInventoryApi`.

```dart
import 'package:hive/hive.dart';

import '../api/inventory_api.dart';
import '../api/rest_client.dart';
import '../features/inventory/inventory_models.dart';
import '../flavor.dart';

class HiveInventoryApi extends InventoryApi {
  HiveInventoryApi() : super(RestClient(mainKey: () => ''));

  Box get _stock => Hive.box(communityInventoryBox);
  Box get _events => Hive.box(communityEventsBox);

  @override
  Future<InventoryResponse> fetchInventory() async {
    final stockRaw = _stock.get('stock') as Map? ?? {};
    final cycleRaw = _stock.get('cycle') as Map?;
    return InventoryResponse(
      stock: Map<String, int>.from(stockRaw.map((k, v) => MapEntry(k as String, (v as num).toInt()))),
      cycle: cycleRaw != null
          ? Cycle.fromJson(Map<String, dynamic>.from(cycleRaw))
          : null,
      pakInstalledAt: _stock.get('pak_installed_at') as String?,
      pakSessions: (_stock.get('pak_sessions') as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<Map<String, num>> fetchStock() async {
    final raw = _stock.get('stock') as Map? ?? {};
    return Map<String, num>.from(raw.map((k, v) => MapEntry(k as String, v as num)));
  }

  @override
  Future<void> logEvent(String type, Map<String, num> deltas, {String? note}) async {
    final stock = Map<String, num>.from(
        ((_stock.get('stock') as Map?) ?? {}).map((k, v) => MapEntry(k as String, v as num)));
    deltas.forEach((k, v) {
      stock[k] = (stock[k] ?? 0) + v;
    });
    await _stock.put('stock', stock);
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await _events.put(id, {
      'id': id,
      'type': type,
      'deltas': deltas.map((k, v) => MapEntry(k, v)),
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> rollbackSession(String sessionId) async {}

  @override
  Future<void> confirmOrder(String callDate, Map<String, int> order, {String? deliveryDate}) async {
    final cycleRaw = _stock.get('cycle') as Map? ?? {};
    final merged = Map<String, dynamic>.from(cycleRaw)
      ..['call_date'] = callDate
      ..['order'] = order
      ..['order_placed_at'] = DateTime.now().toIso8601String();
    if (deliveryDate != null) merged['delivery_date'] = deliveryDate;
    await _stock.put('cycle', merged);
  }

  @override
  Future<void> initCycle(String callDate, {String? deliveryDate}) async {
    await _stock.put('cycle', {
      'call_date': callDate,
      if (deliveryDate != null) 'delivery_date': deliveryDate,
    });
  }

  @override
  Future<void> updateCycleDates(String callDate, String deliveryDate) async {
    final cycleRaw = Map<String, dynamic>.from((_stock.get('cycle') as Map?) ?? {});
    cycleRaw['call_date'] = callDate;
    cycleRaw['delivery_date'] = deliveryDate;
    await _stock.put('cycle', cycleRaw);
  }

  @override
  Future<void> applyDelivery({Map<String, int>? adjustments}) async {
    final cycleRaw = Map<String, dynamic>.from((_stock.get('cycle') as Map?) ?? {});
    cycleRaw['delivery_applied_at'] = DateTime.now().toIso8601String();
    await _stock.put('cycle', cycleRaw);
  }

  @override
  Future<void> updateOrder(Map<String, int> order) async {
    final cycleRaw = Map<String, dynamic>.from((_stock.get('cycle') as Map?) ?? {});
    cycleRaw['order'] = order;
    await _stock.put('cycle', cycleRaw);
  }

  @override
  Future<void> setPakInstall(String installedAt) async =>
      _stock.put('pak_installed_at', installedAt);

  @override
  Future<List<DeliveryEvent>> fetchDeliveries() async => [];
}
```

- [ ] **Step 2: Wire into providers**

In `flutter/lib/features/treatment/providers.dart`, add:

```dart
import '../../api/hive_inventory_api.dart';
```

Change `inventoryApiProvider`:

```dart
final inventoryApiProvider = Provider<InventoryApi>((ref) {
  if (kCommunity) return HiveInventoryApi();
  if (ref.watch(testModeProvider)) return SyntheticInventoryApi();
  return InventoryApi(ref.read(restClientProvider));
});
```

- [ ] **Step 3: Verify build**

```bash
cd flutter && flutter build web --dart-define=FLAVOR=community 2>&1 | tail -5
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add flutter/lib/api/hive_inventory_api.dart flutter/lib/features/treatment/providers.dart
git commit -m "feat(community): HiveInventoryApi — Hive-backed inventory storage"
```

---

### Task 7: KbEntry JSON serialisation + HiveKbStore

**Files:**
- Modify: `flutter/lib/features/kb/kb_store.dart`
- Create: `flutter/lib/features/kb/hive_kb_store.dart`
- Modify: `flutter/lib/features/kb/kb_providers.dart`

- [ ] **Step 1: Write the failing test**

Create `flutter/test/features/kb/hive_kb_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/kb/kb_store.dart';

void main() {
  test('KbEntry toJson/fromJson roundtrip', () {
    final entry = KbEntry(
      id: 'kb-1',
      title: 'Dry Weight',
      content: '59 kg',
      source: 'user',
      createdAt: DateTime.utc(2026, 6, 1, 10),
      updatedAt: DateTime.utc(2026, 6, 2, 12),
    );
    final json = entry.toJson();
    expect(json['created_at'], isA<String>());
    final restored = KbEntry.fromJson(json);
    expect(restored.id, entry.id);
    expect(restored.title, entry.title);
    expect(restored.createdAt.millisecondsSinceEpoch,
        entry.createdAt.millisecondsSinceEpoch);
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd flutter && flutter test test/features/kb/hive_kb_store_test.dart
```

Expected: FAIL — `toJson`/`fromJson` not defined.

- [ ] **Step 3: Add `toJson`/`fromJson` to `KbEntry`**

In `flutter/lib/features/kb/kb_store.dart`, add these methods to the `KbEntry` class (after `fromMap`):

```dart
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'source': source,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory KbEntry.fromJson(Map<String, dynamic> m) => KbEntry(
        id: m['id'] as String,
        title: m['title'] as String,
        content: m['content'] as String,
        source: m['source'] as String? ?? 'user',
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );
```

- [ ] **Step 4: Run to verify pass**

```bash
cd flutter && flutter test test/features/kb/hive_kb_store_test.dart
```

Expected: PASS.

- [ ] **Step 5: Create `hive_kb_store.dart`**

```dart
import 'package:hive/hive.dart';

import '../../flavor.dart';
import 'kb_store.dart';

class HiveKbStore implements KbRepository {
  Box get _box => Hive.box(communityKbBox);

  @override
  Future<List<KbEntry>> getAll() async {
    return _box.values
        .map((v) => KbEntry.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<void> save(KbEntry e) async =>
      _box.put(e.id, e.toJson());

  @override
  Future<void> delete(String id) async =>
      _box.delete(id);
}
```

- [ ] **Step 6: Wire into `kb_providers.dart`**

In `flutter/lib/features/kb/kb_providers.dart`:

```dart
import '../../flavor.dart';
import 'hive_kb_store.dart';
```

Change `kbStoreProvider`:

```dart
final kbStoreProvider = Provider<KbRepository>((ref) {
  if (kCommunity) return HiveKbStore();
  if (ref.watch(testModeProvider)) return SyntheticKbStore();
  return KbStore(ref.read(treatmentAuthProvider));
});
```

- [ ] **Step 7: Commit**

```bash
git add flutter/lib/features/kb/kb_store.dart flutter/lib/features/kb/hive_kb_store.dart flutter/lib/features/kb/kb_providers.dart flutter/test/features/kb/hive_kb_store_test.dart
git commit -m "feat(community): KbEntry JSON serialisation + HiveKbStore for local KB storage"
```

---

### Task 8: ConversationRepository interface + HiveConversationStore

**Files:**
- Modify: `flutter/lib/features/chat/chat_conversation.dart`
- Create: `flutter/lib/features/chat/hive_conversation_store.dart`
- Modify: `flutter/lib/features/kb/kb_providers.dart`

- [ ] **Step 1: Write the failing test**

Create `flutter/test/features/chat/hive_conversation_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/chat/chat_conversation.dart';
import 'package:home_hd/features/chat/chat_controller.dart';

void main() {
  test('ChatConversation toJson/fromJson roundtrip', () {
    final conv = ChatConversation(
      id: 'conv-1',
      title: 'Test',
      messages: [ChatMessage(ChatRole.user, 'hello')],
      createdAt: DateTime.utc(2026, 6, 1),
      updatedAt: DateTime.utc(2026, 6, 1),
    );
    final json = conv.toJson();
    expect(json['created_at'], isA<String>());
    final restored = ChatConversation.fromJson(json);
    expect(restored.id, conv.id);
    expect(restored.messages.first.text, 'hello');
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd flutter && flutter test test/features/chat/hive_conversation_store_test.dart
```

Expected: FAIL — `toJson`/`fromJson` not defined.

- [ ] **Step 3: Add `ConversationRepository` interface, `toJson`/`fromJson` to `ChatConversation`**

In `flutter/lib/features/chat/chat_conversation.dart`:

1. Add an abstract interface (before `class ConversationStore`):

```dart
abstract class ConversationRepository {
  Future<List<ChatConversation>> getRecent({int limit = 50});
  Future<void> save(ChatConversation conv);
  Future<void> delete(String id);
  Future<void> deleteAll();
}
```

2. Make `ConversationStore` implement the interface:

```dart
class ConversationStore implements ConversationRepository {
```

3. Add `toJson`/`fromJson` to `ChatConversation` (after `fromMap`):

```dart
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages
            .where((m) => !m.thinking)
            .map((m) => {
                  'role': m.role == ChatRole.user ? 'user' : 'assistant',
                  'text': m.text,
                })
            .toList(),
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory ChatConversation.fromJson(Map<String, dynamic> m) {
    final rawMsgs = m['messages'] as List? ?? [];
    return ChatConversation(
      id: m['id'] as String,
      title: m['title'] as String? ?? '',
      messages: rawMsgs.map((e) {
        final map = e as Map;
        final role =
            map['role'] == 'user' ? ChatRole.user : ChatRole.assistant;
        return ChatMessage(role, map['text'] as String? ?? '');
      }).toList(),
      createdAt: DateTime.parse(m['created_at'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
    );
  }
```

- [ ] **Step 4: Run test to verify pass**

```bash
cd flutter && flutter test test/features/chat/hive_conversation_store_test.dart
```

Expected: PASS.

- [ ] **Step 5: Create `hive_conversation_store.dart`**

```dart
import 'package:hive/hive.dart';

import '../../flavor.dart';
import 'chat_conversation.dart';

class HiveConversationStore implements ConversationRepository {
  Box get _box => Hive.box(communityChatBox);

  @override
  Future<List<ChatConversation>> getRecent({int limit = 50}) async {
    final all = _box.values
        .map((v) => ChatConversation.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return all.take(limit).toList();
  }

  @override
  Future<void> save(ChatConversation conv) async =>
      _box.put(conv.id, conv.toJson());

  @override
  Future<void> delete(String id) async => _box.delete(id);

  @override
  Future<void> deleteAll() async => _box.clear();
}
```

- [ ] **Step 6: Wire into `kb_providers.dart`**

In `flutter/lib/features/kb/kb_providers.dart`, change `conversationStoreProvider` type from `ConversationStore` to the interface:

```dart
import '../chat/hive_conversation_store.dart';
```

```dart
final conversationStoreProvider = Provider<ConversationRepository>((ref) {
  if (kCommunity) return HiveConversationStore();
  return ConversationStore(ref.read(treatmentAuthProvider));
});
```

Update all consumers of `conversationStoreProvider` to use `ConversationRepository` as the type. Find them with:

```bash
cd flutter && grep -rn "conversationStoreProvider" lib/
```

For each consumer, change `ConversationStore` type annotation to `ConversationRepository`.

- [ ] **Step 7: Commit**

```bash
git add flutter/lib/features/chat/chat_conversation.dart flutter/lib/features/chat/hive_conversation_store.dart flutter/lib/features/kb/kb_providers.dart flutter/test/features/chat/hive_conversation_store_test.dart
git commit -m "feat(community): ConversationRepository interface + HiveConversationStore"
```

---

### Task 9: MarkerDefinitions static list

**Files:**
- Create: `flutter/lib/features/blood_tests/marker_definitions.dart`

- [ ] **Step 1: Write the failing test**

Create `flutter/test/features/blood_tests/marker_definitions_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/blood_tests/marker_definitions.dart';

void main() {
  test('marker list has at least 40 entries', () {
    expect(markerDefinitions.length, greaterThanOrEqualTo(40));
  });

  test('all markers have non-empty name and displayName', () {
    for (final m in markerDefinitions) {
      expect(m.name.isNotEmpty, isTrue, reason: 'name empty');
      expect(m.displayName.isNotEmpty, isTrue, reason: 'displayName empty for ${m.name}');
    }
  });

  test('creatinine entry has expected defaults', () {
    final cr = markerDefinitions.firstWhere((m) => m.name == 'creatinine');
    expect(cr.defaultUnit, 'umol/L');
    expect(cr.refLow, isNotNull);
    expect(cr.refHigh, isNotNull);
  });

  test('list is sorted A-Z by displayName', () {
    final names = markerDefinitions.map((m) => m.displayName.toLowerCase()).toList();
    final sorted = [...names]..sort();
    expect(names, sorted);
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd flutter && flutter test test/features/blood_tests/marker_definitions_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Create `marker_definitions.dart`**

```dart
class MarkerDefinition {
  const MarkerDefinition({
    required this.name,
    required this.displayName,
    required this.defaultUnit,
    this.refLow,
    this.refHigh,
  });
  final String name;
  final String displayName;
  final String defaultUnit;
  final double? refLow;
  final double? refHigh;
}

const markerDefinitions = [
  MarkerDefinition(name: 'albumin',             displayName: 'Albumin',                    defaultUnit: 'g/L',      refLow: 35,    refHigh: 50),
  MarkerDefinition(name: 'alkaline_phosphatase',displayName: 'Alkaline Phosphatase',        defaultUnit: 'U/L',      refLow: 30,    refHigh: 130),
  MarkerDefinition(name: 'alt',                 displayName: 'ALT',                         defaultUnit: 'U/L',      refLow: 7,     refHigh: 56),
  MarkerDefinition(name: 'ast',                 displayName: 'AST',                         defaultUnit: 'U/L',      refLow: 10,    refHigh: 40),
  MarkerDefinition(name: 'bicarbonate',         displayName: 'Bicarbonate',                 defaultUnit: 'mmol/L',   refLow: 22,    refHigh: 29),
  MarkerDefinition(name: 'bilirubin',           displayName: 'Bilirubin (Total)',            defaultUnit: 'umol/L',   refLow: 3,     refHigh: 21),
  MarkerDefinition(name: 'bone_alk_phosphatase',displayName: 'Bone Alkaline Phosphatase',   defaultUnit: 'ug/L',     refLow: null,  refHigh: 22),
  MarkerDefinition(name: 'calcium',             displayName: 'Calcium',                     defaultUnit: 'mmol/L',   refLow: 2.1,   refHigh: 2.6),
  MarkerDefinition(name: 'chloride',            displayName: 'Chloride',                    defaultUnit: 'mmol/L',   refLow: 98,    refHigh: 107),
  MarkerDefinition(name: 'cholesterol',         displayName: 'Cholesterol (Total)',          defaultUnit: 'mmol/L',   refLow: null,  refHigh: 5.0),
  MarkerDefinition(name: 'ck',                  displayName: 'CK',                          defaultUnit: 'U/L',      refLow: 38,    refHigh: 204),
  MarkerDefinition(name: 'creatinine',          displayName: 'Creatinine',                  defaultUnit: 'umol/L',   refLow: 64,    refHigh: 104),
  MarkerDefinition(name: 'crp',                 displayName: 'CRP',                         defaultUnit: 'mg/L',     refLow: null,  refHigh: 5),
  MarkerDefinition(name: 'egfr',                displayName: 'eGFR',                        defaultUnit: 'mL/min',   refLow: 60,    refHigh: null),
  MarkerDefinition(name: 'epo',                 displayName: 'Erythropoietin',              defaultUnit: 'mU/mL',    refLow: 2.6,   refHigh: 18.5),
  MarkerDefinition(name: 'ferritin',            displayName: 'Ferritin',                    defaultUnit: 'ug/L',     refLow: 20,    refHigh: 300),
  MarkerDefinition(name: 'folate',              displayName: 'Folate',                      defaultUnit: 'nmol/L',   refLow: 7,     refHigh: null),
  MarkerDefinition(name: 'fsh',                 displayName: 'FSH',                         defaultUnit: 'U/L',      refLow: null,  refHigh: null),
  MarkerDefinition(name: 'ggt',                 displayName: 'GGT',                         defaultUnit: 'U/L',      refLow: 10,    refHigh: 71),
  MarkerDefinition(name: 'glucose',             displayName: 'Glucose',                     defaultUnit: 'mmol/L',   refLow: 3.9,   refHigh: 5.6),
  MarkerDefinition(name: 'haematocrit',         displayName: 'Haematocrit',                 defaultUnit: 'L/L',      refLow: 0.36,  refHigh: 0.46),
  MarkerDefinition(name: 'haemoglobin',         displayName: 'Haemoglobin',                 defaultUnit: 'g/L',      refLow: 110,   refHigh: 130),
  MarkerDefinition(name: 'hdl',                 displayName: 'HDL Cholesterol',             defaultUnit: 'mmol/L',   refLow: 1.0,   refHigh: null),
  MarkerDefinition(name: 'intact_pth',          displayName: 'Intact PTH',                  defaultUnit: 'pmol/L',   refLow: null,  refHigh: null),
  MarkerDefinition(name: 'iron',                displayName: 'Iron',                        defaultUnit: 'umol/L',   refLow: 11,    refHigh: 30),
  MarkerDefinition(name: 'kt_v',               displayName: 'Kt/V',                        defaultUnit: '',         refLow: 1.2,   refHigh: null),
  MarkerDefinition(name: 'lactate',             displayName: 'Lactate',                     defaultUnit: 'mmol/L',   refLow: 0.5,   refHigh: 2.2),
  MarkerDefinition(name: 'ldh',                 displayName: 'LDH',                         defaultUnit: 'U/L',      refLow: 135,   refHigh: 225),
  MarkerDefinition(name: 'ldl',                 displayName: 'LDL Cholesterol',             defaultUnit: 'mmol/L',   refLow: null,  refHigh: 3.0),
  MarkerDefinition(name: 'lymphocytes',         displayName: 'Lymphocytes',                 defaultUnit: 'x10^9/L',  refLow: 1.0,   refHigh: 4.0),
  MarkerDefinition(name: 'magnesium',           displayName: 'Magnesium',                   defaultUnit: 'mmol/L',   refLow: 0.7,   refHigh: 1.0),
  MarkerDefinition(name: 'mch',                 displayName: 'MCH',                         defaultUnit: 'pg',       refLow: 27,    refHigh: 32),
  MarkerDefinition(name: 'mcv',                 displayName: 'MCV',                         defaultUnit: 'fL',       refLow: 80,    refHigh: 100),
  MarkerDefinition(name: 'neutrophils',         displayName: 'Neutrophils',                 defaultUnit: 'x10^9/L',  refLow: 1.8,   refHigh: 7.5),
  MarkerDefinition(name: 'parathyroid_hormone', displayName: 'Parathyroid Hormone',         defaultUnit: 'pmol/L',   refLow: 1.1,   refHigh: 6.8),
  MarkerDefinition(name: 'phosphate',           displayName: 'Phosphate',                   defaultUnit: 'mmol/L',   refLow: 0.8,   refHigh: 1.5),
  MarkerDefinition(name: 'platelets',           displayName: 'Platelets',                   defaultUnit: 'x10^9/L',  refLow: 150,   refHigh: 400),
  MarkerDefinition(name: 'potassium',           displayName: 'Potassium',                   defaultUnit: 'mmol/L',   refLow: 3.5,   refHigh: 5.1),
  MarkerDefinition(name: 'prealbumin',          displayName: 'Prealbumin',                  defaultUnit: 'g/L',      refLow: 0.2,   refHigh: 0.4),
  MarkerDefinition(name: 'protein_total',       displayName: 'Protein (Total)',              defaultUnit: 'g/L',      refLow: 60,    refHigh: 80),
  MarkerDefinition(name: 'rbc',                 displayName: 'RBC',                         defaultUnit: 'x10^12/L', refLow: 3.8,   refHigh: 5.8),
  MarkerDefinition(name: 'reticulocytes',       displayName: 'Reticulocytes',               defaultUnit: '%',        refLow: 0.5,   refHigh: 2.5),
  MarkerDefinition(name: 'sodium',              displayName: 'Sodium',                      defaultUnit: 'mmol/L',   refLow: 133,   refHigh: 146),
  MarkerDefinition(name: 'tibc',                displayName: 'TIBC',                        defaultUnit: 'umol/L',   refLow: 45,    refHigh: 72),
  MarkerDefinition(name: 'transferrin_sat',     displayName: 'Transferrin Saturation',      defaultUnit: '%',        refLow: 20,    refHigh: 50),
  MarkerDefinition(name: 'triglycerides',       displayName: 'Triglycerides',               defaultUnit: 'mmol/L',   refLow: null,  refHigh: 1.7),
  MarkerDefinition(name: 'tsh',                 displayName: 'TSH',                         defaultUnit: 'mU/L',     refLow: 0.4,   refHigh: 4.0),
  MarkerDefinition(name: 'urea',                displayName: 'Urea',                        defaultUnit: 'mmol/L',   refLow: 2.5,   refHigh: 7.8),
  MarkerDefinition(name: 'uric_acid',           displayName: 'Uric Acid',                   defaultUnit: 'umol/L',   refLow: 202,   refHigh: 416),
  MarkerDefinition(name: 'vitamin_b12',         displayName: 'Vitamin B12',                 defaultUnit: 'pmol/L',   refLow: 145,   refHigh: 637),
  MarkerDefinition(name: 'wbc',                 displayName: 'WBC',                         defaultUnit: 'x10^9/L',  refLow: 4.0,   refHigh: 11.0),
];
```

- [ ] **Step 4: Run tests**

```bash
cd flutter && flutter test test/features/blood_tests/marker_definitions_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter/lib/features/blood_tests/marker_definitions.dart flutter/test/features/blood_tests/marker_definitions_test.dart
git commit -m "feat(community): 51-marker MarkerDefinition list with default ref ranges"
```

---

### Task 10: HiveBtStore — community primary blood test store

**Files:**
- Create: `flutter/lib/features/blood_tests/hive_bt_store.dart`
- Modify: `flutter/lib/features/blood_tests/providers.dart`

- [ ] **Step 1: Write the failing test**

Create `flutter/test/features/blood_tests/hive_bt_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:home_hd/features/blood_tests/hive_bt_store.dart';
import 'package:home_hd/features/blood_tests/models.dart';
import 'package:home_hd/flavor.dart';
import 'dart:io';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_bt_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(communityBtBox);
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  setUp(() => Hive.box(communityBtBox).clear());

  test('empty store returns empty cache with null coveredFrom', () {
    final store = HiveBtStore(Hive.box(communityBtBox));
    final cache = store.readCache();
    expect(cache.rows, isEmpty);
    expect(cache.coveredFrom, isNull);
  });

  test('writeCache then readCache round-trips rows', () async {
    final store = HiveBtStore(Hive.box(communityBtBox));
    final row = BloodTestRow(
      marker: 'creatinine',
      datetime: '2026-06-01T09:00:00.000Z',
      value: 980,
      unit: 'umol/L',
      refLow: 64,
      refHigh: 104,
      timing: 'pre',
      note: '',
      source: 'manual',
      labId: '',
      phase: '',
      createdAt: '2026-06-01',
      qualitative: false,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.writeCache([row], '2026-01-01', now);
    final cache = store.readCache();
    expect(cache.rows.length, 1);
    expect(cache.rows.first.marker, 'creatinine');
    // lastSynced should be recent (within 1 second of now) — always "fresh"
    expect(cache.lastSynced, greaterThan(now - 1000));
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd flutter && flutter test test/features/blood_tests/hive_bt_store_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Create `hive_bt_store.dart`**

```dart
import 'package:hive/hive.dart';

import 'bt_store.dart';
import 'models.dart';

/// Community blood test store. Uses a dedicated Hive box as the primary store.
/// Always returns lastSynced = now so the screen never triggers a remote fetch.
class HiveBtStore extends BtStore {
  HiveBtStore(super.box);

  static const _rowsKey    = 'bt_rows';
  static const _coveredKey = 'bt_covered_from';

  @override
  BtCache readCache() {
    final raw = box.get(_rowsKey);
    final rows = raw is List
        ? raw
            .map((e) => BloodTestRow.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()
        : <BloodTestRow>[];
    return BtCache(
      rows,
      box.get(_coveredKey) as String?,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> writeCache(
      List<BloodTestRow> rows, String coveredFrom, int lastSynced) async {
    await box.put(_rowsKey, rows.map((r) => r.toJson()).toList());
    await box.put(_coveredKey, coveredFrom);
  }

  Future<void> upsertRow(BloodTestRow row) async {
    final key = '${row.datetime.substring(0, 10)}_${row.marker}';
    final existing = readCache();
    final updated = [
      ...existing.rows.where(
          (r) => '${r.datetime.substring(0, 10)}_${r.marker}' != key),
      row,
    ];
    await writeCache(updated, existing.coveredFrom ?? '', 0);
  }

  Future<void> deleteRow(String date, String marker) async {
    final key = '${date}_$marker';
    final existing = readCache();
    final updated = existing.rows
        .where((r) => '${r.datetime.substring(0, 10)}_${r.marker}' != key)
        .toList();
    await writeCache(updated, existing.coveredFrom ?? '', 0);
  }
}
```

Note: `BtStore._box` is private. Add the following getter to `BtStore` in `bt_store.dart` (after the `_box` field declaration):

```dart
Box get box => _box;
```

Add this to the `flutter/lib/features/blood_tests/bt_store.dart` git add in Step 6.

- [ ] **Step 4: Wire into providers**

In `flutter/lib/features/blood_tests/providers.dart`:

```dart
import '../../flavor.dart';
import 'hive_bt_store.dart';
```

```dart
final btStoreProvider = Provider<BtStore>((ref) {
  if (kCommunity) return HiveBtStore(Hive.box(communityBtBox));
  final box = Hive.box(cacheBoxName);
  if (ref.watch(testModeProvider)) return SyntheticBtStore(box);
  return BtStore(box);
});

final bloodTestsApiProvider = Provider<BloodTestsApi>((ref) {
  if (kCommunity) return _NoopBloodTestsApi();
  if (ref.watch(testModeProvider)) return SyntheticBloodTestsApi();
  return BloodTestsApi(ref.read(restClientProvider));
});
```

Add a no-op community API (community never fetches remotely):

```dart
class _NoopBloodTestsApi extends BloodTestsApi {
  _NoopBloodTestsApi() : super(RestClient(mainKey: () => ''));
  @override
  Future<List<BloodTestRow>> fetchRange({String? from, String? to}) async => [];
}
```

- [ ] **Step 5: Run tests**

```bash
cd flutter && flutter test test/features/blood_tests/hive_bt_store_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add flutter/lib/features/blood_tests/hive_bt_store.dart flutter/lib/features/blood_tests/providers.dart flutter/lib/features/blood_tests/bt_store.dart flutter/test/features/blood_tests/hive_bt_store_test.dart
git commit -m "feat(community): HiveBtStore — local Hive-backed blood test primary store"
```

---

### Task 11: Filter bar — hide phase pills in community

**Files:**
- Modify: `flutter/lib/features/blood_tests/widgets/filter_bar.dart`

- [ ] **Step 1: Add `kCommunity` guard to `FilterBar`**

In `flutter/lib/features/blood_tests/widgets/filter_bar.dart`, add import:

```dart
import '../../../flavor.dart';
```

In `FilterBar.build()`, wrap the Phase pills `Wrap` and the `SizedBox` spacer between phase and range pills:

```dart
if (!kCommunity) ...[
  Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final (value, label) in _phaseOptions)
        FilterPill(
          label: label,
          active: value == activePhase,
          onTap: () => onChange(filter.copyWith(
              phases: value.isEmpty ? const [] : [value])),
        ),
    ],
  ),
  const SizedBox(height: 12),
],
```

The range row remains unchanged.

Also change `FilterState` default for community — phases is irrelevant but harmless. No change needed; the community blood tests screen just won't set phases.

- [ ] **Step 2: Verify build**

```bash
cd flutter && flutter build web --dart-define=FLAVOR=community 2>&1 | tail -5
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add flutter/lib/features/blood_tests/widgets/filter_bar.dart
git commit -m "feat(community): remove phase filter pills from blood tests screen in community flavor"
```

---

### Task 12: CSV import — parser + preview sheet

**Files:**
- Create: `flutter/lib/features/blood_tests/csv_import.dart`
- Create: `flutter/lib/features/blood_tests/csv_import_sheet.dart`

- [ ] **Step 1: Write the failing test**

Create `flutter/test/features/blood_tests/csv_import_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/blood_tests/csv_import.dart';

void main() {
  const validCsv = '''date,marker,value,unit,ref_low,ref_high,timing,note
2026-06-01,creatinine,980,umol/L,64,104,pre,
2026-06-01,potassium,5.1,mmol/L,3.5,5.1,,fasting''';

  test('parses valid rows', () {
    final result = parseCsvImport(validCsv);
    expect(result.valid.length, 2);
    expect(result.errors, isEmpty);
    expect(result.valid.first.marker, 'creatinine');
    expect(result.valid.first.value, 980.0);
    expect(result.valid.first.timing, 'pre');
  });

  test('rejects row with non-numeric value', () {
    final csv = 'date,marker,value,unit,ref_low,ref_high,timing,note\n2026-06-01,creatinine,abc,umol/L,,,, ';
    final result = parseCsvImport(csv);
    expect(result.valid, isEmpty);
    expect(result.errors.first.reason, contains('numeric'));
  });

  test('rejects row with invalid date', () {
    final csv = 'date,marker,value,unit,ref_low,ref_high,timing,note\nnot-a-date,creatinine,980,umol/L,,,,';
    final result = parseCsvImport(csv);
    expect(result.errors.first.reason, contains('date'));
  });

  test('rejects row with empty marker', () {
    final csv = 'date,marker,value,unit,ref_low,ref_high,timing,note\n2026-06-01,,980,umol/L,,,,';
    final result = parseCsvImport(csv);
    expect(result.errors.first.reason, contains('marker'));
  });

  test('rejects row when ref_low >= ref_high', () {
    final csv = 'date,marker,value,unit,ref_low,ref_high,timing,note\n2026-06-01,creatinine,980,umol/L,104,64,,';
    final result = parseCsvImport(csv);
    expect(result.errors.first.reason, contains('ref_low'));
  });

  test('accepts row with missing optional fields', () {
    final csv = 'date,marker,value,unit,ref_low,ref_high,timing,note\n2026-06-01,myMarker,1.5,,,,,';
    final result = parseCsvImport(csv);
    expect(result.valid.length, 1);
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd flutter && flutter test test/features/blood_tests/csv_import_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Create `csv_import.dart`**

```dart
import 'package:csv/csv.dart';

import 'models.dart';

class CsvParseResult {
  const CsvParseResult({required this.valid, required this.errors});
  final List<BloodTestRow> valid;
  final List<CsvRowError> errors;
}

class CsvRowError {
  const CsvRowError({required this.rowIndex, required this.rawRow, required this.reason});
  final int rowIndex;
  final List<String> rawRow;
  final String reason;
}

CsvParseResult parseCsvImport(String csvText) {
  final lines = const CsvToListConverter(eol: '\n').convert(csvText);
  if (lines.isEmpty) return const CsvParseResult(valid: [], errors: []);

  final header = lines.first.map((c) => c.toString().trim().toLowerCase()).toList();
  final idx = {for (var i = 0; i < header.length; i++) header[i]: i};

  int col(String name) => idx[name] ?? -1;
  String cell(List row, String name) {
    final i = col(name);
    return i >= 0 && i < row.length ? row[i].toString().trim() : '';
  }

  final valid = <BloodTestRow>[];
  final errors = <CsvRowError>[];

  for (var i = 1; i < lines.length; i++) {
    final row = lines[i];
    final raw = row.map((c) => c.toString()).toList();

    final dateStr = cell(row, 'date');
    final marker  = cell(row, 'marker');
    final valStr  = cell(row, 'value');
    final unit    = cell(row, 'unit');
    final refLowStr  = cell(row, 'ref_low');
    final refHighStr = cell(row, 'ref_high');
    final timing  = cell(row, 'timing');
    final note    = cell(row, 'note');

    if (marker.isEmpty) {
      errors.add(CsvRowError(rowIndex: i, rawRow: raw, reason: 'marker name is required'));
      continue;
    }

    DateTime date;
    try {
      date = DateTime.parse(dateStr);
    } catch (_) {
      errors.add(CsvRowError(rowIndex: i, rawRow: raw, reason: 'invalid date "$dateStr" — use YYYY-MM-DD'));
      continue;
    }

    final value = double.tryParse(valStr);
    if (value == null) {
      errors.add(CsvRowError(rowIndex: i, rawRow: raw, reason: 'value must be numeric, got "$valStr"'));
      continue;
    }

    final refLow  = refLowStr.isEmpty  ? null : double.tryParse(refLowStr);
    final refHigh = refHighStr.isEmpty ? null : double.tryParse(refHighStr);

    if (refLow != null && refHigh != null && refLow >= refHigh) {
      errors.add(CsvRowError(rowIndex: i, rawRow: raw, reason: 'ref_low ($refLow) must be less than ref_high ($refHigh)'));
      continue;
    }

    valid.add(BloodTestRow(
      marker: marker,
      datetime: '${date.toIso8601String().substring(0, 10)}T09:00:00.000Z',
      value: value,
      unit: unit,
      refLow: refLow,
      refHigh: refHigh,
      timing: timing,
      note: note,
      source: 'csv_import',
      labId: '',
      phase: '',
      createdAt: DateTime.now().toIso8601String().substring(0, 10),
      qualitative: false,
    ));
  }

  return CsvParseResult(valid: valid, errors: errors);
}

const csvImportTemplate =
    'date,marker,value,unit,ref_low,ref_high,timing,note\n'
    '2026-06-01,creatinine,980,umol/L,64,104,pre,\n'
    '2026-06-01,urea,18.2,mmol/L,2.5,7.8,pre,\n'
    '2026-06-01,potassium,5.1,mmol/L,3.5,5.1,,\n';
```

- [ ] **Step 4: Run tests**

```bash
cd flutter && flutter test test/features/blood_tests/csv_import_test.dart
```

Expected: PASS.

- [ ] **Step 5: Create `csv_import_sheet.dart`**

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'csv_import.dart';
import 'hive_bt_store.dart';
import 'models.dart';
import 'providers.dart';

Future<void> showCsvImportSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const _CsvImportSheet(),
  );
}

class _CsvImportSheet extends ConsumerStatefulWidget {
  const _CsvImportSheet();
  @override
  ConsumerState<_CsvImportSheet> createState() => _CsvImportSheetState();
}

class _CsvImportSheetState extends ConsumerState<_CsvImportSheet> {
  CsvParseResult? _result;
  bool _importing = false;
  String? _importedCount;

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final bytes = picked.files.first.bytes;
    if (bytes == null) return;
    final text = String.fromCharCodes(bytes);
    setState(() => _result = parseCsvImport(text));
  }

  Future<void> _doImport() async {
    final result = _result;
    if (result == null || result.valid.isEmpty) return;
    setState(() => _importing = true);
    final store = ref.read(btStoreProvider) as HiveBtStore;
    for (final row in result.valid) {
      await store.upsertRow(row);
    }
    setState(() {
      _importing = false;
      _importedCount = '${result.valid.length}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;

    if (_importedCount != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: t.success),
            const SizedBox(height: 16),
            Text('Imported $_importedCount rows',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }

    final result = _result;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, controller) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Import CSV',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 12),
            if (result == null) ...[
              Text(
                'Select a CSV file with columns: date, marker, value, unit, ref_low, ref_high, timing, note',
                style: TextStyle(fontSize: 13, color: t.textMuted),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.upload_file),
                label: const Text('Choose file'),
              ),
            ] else ...[
              Text(
                '${result.valid.length} valid row(s), ${result.errors.length} error(s)',
                style: TextStyle(
                    color: result.errors.isEmpty ? t.success : t.warning,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: controller,
                  children: [
                    for (final row in result.valid)
                      _RowTile(marker: row.marker, date: row.datetime.substring(0, 10), ok: true),
                    for (final err in result.errors)
                      _RowTile(
                          marker: err.rawRow.length > 1 ? err.rawRow[1] : '?',
                          date: err.rawRow.isNotEmpty ? err.rawRow[0] : '?',
                          ok: false,
                          reason: err.reason),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                TextButton(
                    onPressed: () => setState(() => _result = null),
                    child: const Text('Choose different file')),
                const Spacer(),
                if (result.valid.isNotEmpty)
                  FilledButton(
                    onPressed: _importing ? null : _doImport,
                    child: _importing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Import ${result.valid.length} rows'),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.marker, required this.date, required this.ok, this.reason});
  final String marker;
  final String date;
  final bool ok;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 16, color: ok ? t.success : t.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            ok ? '$date  $marker' : '$date  $marker  —  $reason',
            style: TextStyle(
                fontSize: 12,
                color: ok ? t.textPrimary : t.danger),
          ),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 6: Commit**

```bash
git add flutter/lib/features/blood_tests/csv_import.dart flutter/lib/features/blood_tests/csv_import_sheet.dart flutter/test/features/blood_tests/csv_import_test.dart
git commit -m "feat(community): CSV import parser and preview sheet for blood tests"
```

---

### Task 13: Manual blood test entry sheet

**Files:**
- Create: `flutter/lib/features/blood_tests/entry_sheet.dart`

No unit test (pure UI). Manual test: Open sheet, search "crea", select Creatinine, verify unit/refs auto-fill.

- [ ] **Step 1: Create `entry_sheet.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'hive_bt_store.dart';
import 'marker_definitions.dart';
import 'models.dart';
import 'providers.dart';

Future<void> showEntrySheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => ProviderScope(
      parent: ProviderScope.containerOf(ctx),
      child: const _EntrySheet(),
    ),
  );
}

class _EntrySheet extends ConsumerStatefulWidget {
  const _EntrySheet();
  @override
  ConsumerState<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends ConsumerState<_EntrySheet> {
  DateTime _date = DateTime.now();
  MarkerDefinition? _marker;
  final _searchCtrl  = TextEditingController();
  final _valueCtrl   = TextEditingController();
  final _unitCtrl    = TextEditingController();
  final _refLowCtrl  = TextEditingController();
  final _refHighCtrl = TextEditingController();
  final _noteCtrl    = TextEditingController();
  String _timing = '';
  bool _saving = false;
  String? _error;

  List<MarkerDefinition> get _filtered {
    final q = _searchCtrl.text.toLowerCase();
    if (q.isEmpty) return markerDefinitions;
    return markerDefinitions
        .where((m) => m.displayName.toLowerCase().contains(q) ||
                      m.name.toLowerCase().contains(q))
        .toList();
  }

  void _selectMarker(MarkerDefinition m) {
    setState(() {
      _marker = m;
      _searchCtrl.text = m.displayName;
      if (_unitCtrl.text.isEmpty) _unitCtrl.text = m.defaultUnit;
      if (_refLowCtrl.text.isEmpty && m.refLow != null)
        _refLowCtrl.text = m.refLow!.toString();
      if (_refHighCtrl.text.isEmpty && m.refHigh != null)
        _refHighCtrl.text = m.refHigh!.toString();
    });
  }

  Future<void> _save({bool addAnother = false}) async {
    final markerName = _searchCtrl.text.trim();
    if (markerName.isEmpty) {
      setState(() => _error = 'Marker is required');
      return;
    }
    final value = double.tryParse(_valueCtrl.text.trim());
    if (value == null) {
      setState(() => _error = 'Value must be a number');
      return;
    }
    setState(() { _saving = true; _error = null; });

    final row = BloodTestRow(
      marker: markerName.toLowerCase().replaceAll(' ', '_'),
      datetime: '${_date.toIso8601String().substring(0, 10)}T09:00:00.000Z',
      value: value,
      unit: _unitCtrl.text.trim(),
      refLow: double.tryParse(_refLowCtrl.text),
      refHigh: double.tryParse(_refHighCtrl.text),
      timing: _timing,
      note: _noteCtrl.text.trim(),
      source: 'manual',
      labId: '',
      phase: '',
      createdAt: DateTime.now().toIso8601String().substring(0, 10),
      qualitative: false,
    );

    final store = ref.read(btStoreProvider) as HiveBtStore;
    await store.upsertRow(row);

    if (!mounted) return;
    if (addAnother) {
      setState(() {
        _saving = false;
        _marker = null;
        _searchCtrl.clear();
        _valueCtrl.clear();
        _unitCtrl.clear();
        _refLowCtrl.clear();
        _refHighCtrl.clear();
        _noteCtrl.clear();
        _timing = '';
      });
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _valueCtrl.dispose();
    _unitCtrl.dispose();
    _refLowCtrl.dispose();
    _refHighCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(child: Text('Add result',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 12),
            // Date
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _date = picked);
              },
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(_date.toIso8601String().substring(0, 10)),
            ),
            const SizedBox(height: 12),
            // Marker search
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'Marker',
                hintText: 'Search or type custom marker',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              onChanged: (_) => setState(() { _marker = null; }),
            ),
            if (_searchCtrl.text.isNotEmpty && _marker == null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView(
                  shrinkWrap: true,
                  children: _filtered.map((m) => ListTile(
                    dense: true,
                    title: Text(m.displayName, style: const TextStyle(fontSize: 13)),
                    onTap: () => _selectMarker(m),
                  )).toList(),
                ),
              ),
            const SizedBox(height: 8),
            // Value + Unit row
            Row(children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _valueCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Value'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _unitCtrl,
                  decoration: const InputDecoration(labelText: 'Unit'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            // Ref range row
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _refLowCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Ref low'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _refHighCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Ref high'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            // Timing
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pre',  label: Text('Pre')),
                ButtonSegment(value: 'post', label: Text('Post')),
                ButtonSegment(value: '',     label: Text('None')),
              ],
              selected: {_timing},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _timing = s.first),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: t.danger, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(addAnother: true),
                  child: const Text('Add another'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(),
                  child: const Text('Save'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add flutter/lib/features/blood_tests/entry_sheet.dart
git commit -m "feat(community): manual blood test entry sheet with searchable marker picker"
```

---

### Task 14: Blood Tests screen — Import / Export buttons

**Files:**
- Modify: `flutter/lib/features/blood_tests/blood_tests_screen.dart`

- [ ] **Step 1: Add Import and Export actions to `BloodTestsScreen`**

In `flutter/lib/features/blood_tests/blood_tests_screen.dart`, add imports:

```dart
import '../../flavor.dart';
import 'csv_import_sheet.dart';
import 'entry_sheet.dart';
```

In `_BloodTestsScreenState.build()`, find the `HdScaffold` call and add community actions. The scaffold currently has no `actions`. Add:

```dart
actions: kCommunity
    ? [
        IconButton(
          icon: const Icon(Icons.download_outlined),
          tooltip: 'Export CSV',
          onPressed: _exportCsv,
        ),
        IconButton(
          icon: const Icon(Icons.upload_file_outlined),
          tooltip: 'Import CSV',
          onPressed: () => showCsvImportSheet(context).then((_) => _bootstrap()),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Add result',
          onPressed: () => showEntrySheet(context).then((_) => _bootstrap()),
        ),
      ]
    : null,
```

Add the `_exportCsv` method to `_BloodTestsScreenState`:

```dart
Future<void> _exportCsv() async {
  final rows = _rows;
  if (rows.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data to export')));
    return;
  }
  final buf = StringBuffer();
  buf.writeln('date,marker,value,unit,ref_low,ref_high,timing,note');
  for (final r in rows) {
    buf.writeln(
        '${r.datetime.substring(0, 10)},${r.marker},${r.value},${r.unit},'
        '${r.refLow ?? ''},${r.refHigh ?? ''},${r.timing},${r.note}');
  }
  final bytes = buf.toString().codeUnits;
  // On web, trigger a browser download via dart:html or use the printing package.
  // On Android, use FilePicker saveFile or share via Share.shareXFiles.
  // Use the simplest universal approach: copy to clipboard with a message.
  // For a proper download, integrate the `share_plus` package in a follow-up.
  await Clipboard.setData(ClipboardData(text: buf.toString()));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV copied to clipboard')));
  }
}
```

Add `import 'package:flutter/services.dart' show Clipboard, ClipboardData;` to the screen file.

Note: Replace the clipboard fallback with proper file export once `share_plus` is added (it is a separate clean-up). The clipboard approach is correct for web; on Android it provides a functional path.

- [ ] **Step 2: Verify build**

```bash
cd flutter && flutter build web --dart-define=FLAVOR=community 2>&1 | tail -5
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add flutter/lib/features/blood_tests/blood_tests_screen.dart
git commit -m "feat(community): add Import CSV, Add result, and Export CSV actions to blood tests screen"
```

---

### Task 15: Community settings screen + dry weight guard

**Files:**
- Create: `flutter/lib/features/settings/community_settings_screen.dart`
- Modify: `flutter/lib/app/router.dart`
- Modify: `flutter/lib/features/treatment/store.dart`
- Modify: `flutter/lib/features/treatment/screens/pre.dart`

- [ ] **Step 1: Update `TreatmentStore.getDriedWeight()` default for community**

In `flutter/lib/features/treatment/store.dart`, add:

```dart
import '../../flavor.dart';
```

Change `getDriedWeight()`:

```dart
double getDriedWeight() {
  final v = _box.get(_driedKey);
  if (v is num && v.isFinite) return v.toDouble();
  return kCommunity ? 0.0 : driedWeightDefault;
}
```

Also expose a setter (may already exist; check, and add if not):

```dart
Future<void> setDriedWeight(double kg) => _box.put(_driedKey, kg);
```

- [ ] **Step 2: Add dry weight guard to `PreTreatment`**

In `flutter/lib/features/treatment/screens/pre.dart`, add:

```dart
import '../../../flavor.dart';
```

In `_PreTreatmentState.build()`, find the "Start session" / Save button widget. Wrap it with a community dry-weight guard. Locate the button by searching for `_saving` or `onSaved` in the build method, then:

If `kCommunity && _driedWeight <= 0`, show an info row above the button and disable it:

```dart
if (kCommunity && _driedWeight <= 0) ...[
  Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      'Set your dry weight in Settings before starting a session.',
      style: TextStyle(fontSize: 12, color: context.hd.warning),
      textAlign: TextAlign.center,
    ),
  ),
],
```

And in the button's `onPressed`:

```dart
onPressed: (_saving || (kCommunity && _driedWeight <= 0)) ? null : _submit,
```

- [ ] **Step 3: Create `community_settings_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../app/providers.dart'
    show aiSettingsControllerProvider, themeModeProvider;
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../app/providers.dart' show cacheBoxName;
import '../treatment/providers.dart' show treatmentStoreProvider;
import '../treatment/store.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../blood_tests/csv_import.dart' show csvImportTemplate;

// Stored in the cache box under a simple key.
const _patientNameKey = 'community_patient_name';

class CommunitySettingsScreen extends ConsumerStatefulWidget {
  const CommunitySettingsScreen({super.key});
  @override
  ConsumerState<CommunitySettingsScreen> createState() =>
      _CommunitySettingsScreenState();
}

class _CommunitySettingsScreenState
    extends ConsumerState<CommunitySettingsScreen> {
  final _nameCtrl     = TextEditingController();
  final _dryCtrl      = TextEditingController();
  final _aiKeyCtrl    = TextEditingController();
  bool _nameSaved     = false;
  bool _drySaved      = false;

  @override
  void initState() {
    super.initState();
    final box = Hive.box(cacheBoxName);
    _nameCtrl.text = box.get(_patientNameKey) as String? ?? '';
    final store = ref.read(treatmentStoreProvider);
    final dw = store.getDriedWeight();
    if (dw > 0) _dryCtrl.text = dw.toString();
    final ai = ref.read(aiSettingsControllerProvider);
    if (ai.apiKey != null) _aiKeyCtrl.text = ai.apiKey!;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dryCtrl.dispose();
    _aiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    await Hive.box(cacheBoxName).put(_patientNameKey, _nameCtrl.text.trim());
    setState(() => _nameSaved = true);
  }

  Future<void> _saveDryWeight() async {
    final v = double.tryParse(_dryCtrl.text.trim());
    if (v == null || v <= 0) return;
    await ref.read(treatmentStoreProvider).setDriedWeight(v);
    setState(() => _drySaved = true);
  }

  Future<void> _saveAiKey() async {
    final key = _aiKeyCtrl.text.trim();
    if (key.isEmpty) {
      await ref.read(aiSettingsControllerProvider.notifier).clearKey();
    } else {
      await ref.read(aiSettingsControllerProvider.notifier).setKey(key);
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('AI key saved')));
    }
  }

  Future<void> _downloadTemplate() async {
    await Clipboard.setData(const ClipboardData(text: csvImportTemplate));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV template copied to clipboard')));
    }
  }

  Future<void> _confirmClearAll() async {
    final t = context.hd;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all data'),
        content: const Text(
            'This will permanently delete all sessions, readings, blood tests, inventory, and chat history from this device. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: t.danger, foregroundColor: t.accentOn),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // Clear all community boxes
    for (final boxName in [
      'community_sessions',
      'community_readings',
      'community_bt',
      'community_inventory',
      'community_events',
      'community_kb',
      'community_chat',
    ]) {
      Hive.box(boxName).clear();
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('All data cleared')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final mode = ref.watch(themeModeProvider);

    return HdScaffold(
      title: 'Settings',
      showDrawer: false,
      showChatFab: false,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(t, 'PATIENT'),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Your name',
              hintText: 'Used in PDF export headers',
            ),
            onChanged: (_) => setState(() => _nameSaved = false),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed: _saveName,
              child: Text(_nameSaved ? 'Saved ✓' : 'Save name')),
          const SizedBox(height: 20),
          _section(t, 'DRY WEIGHT'),
          TextField(
            controller: _dryCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Dry weight (kg)',
              hintText: 'e.g. 68.5',
            ),
            onChanged: (_) => setState(() => _drySaved = false),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed: _saveDryWeight,
              child: Text(_drySaved ? 'Saved ✓' : 'Save dry weight')),
          const SizedBox(height: 20),
          _section(t, 'AI ASSISTANT (OPTIONAL)'),
          Text(
            'Enter an AI Studio key to enable the chat assistant. Leave blank to hide the chat button.',
            style: TextStyle(fontSize: 12, color: t.textMuted),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _aiKeyCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'AI Studio API key'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _saveAiKey, child: const Text('Save key')),
          const SizedBox(height: 20),
          _section(t, 'BLOOD TESTS'),
          OutlinedButton.icon(
            onPressed: _downloadTemplate,
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('Copy CSV template to clipboard'),
          ),
          const SizedBox(height: 20),
          _section(t, 'APPEARANCE'),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light,  label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark,   label: Text('Dark')),
            ],
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) =>
                ref.read(themeModeProvider.notifier).set(s.first),
          ),
          const SizedBox(height: 28),
          _section(t, 'DATA'),
          OutlinedButton.icon(
            onPressed: _confirmClearAll,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Clear all data'),
            style: OutlinedButton.styleFrom(
              foregroundColor: t.danger,
              side: BorderSide(color: t.danger),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(HdTokens t, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label,
            style: TextStyle(fontSize: 12, letterSpacing: 1, color: t.textMuted)),
      );
}
```

- [ ] **Step 4: Wire the community settings screen into the router**

In `flutter/lib/app/router.dart`:

```dart
import '../features/settings/community_settings_screen.dart';
```

Change the `/settings` route:

```dart
GoRoute(
  path: '/settings',
  builder: (_, _) => kCommunity
      ? const CommunitySettingsScreen()
      : const SettingsScreen(),
),
```

- [ ] **Step 5: Verify build**

```bash
cd flutter && flutter build web --dart-define=FLAVOR=community 2>&1 | tail -5
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add flutter/lib/features/settings/community_settings_screen.dart flutter/lib/app/router.dart flutter/lib/features/treatment/store.dart flutter/lib/features/treatment/screens/pre.dart
git commit -m "feat(community): community settings screen + dry weight guard on pre-treatment"
```

---

### Task 16: Session PDF export

**Files:**
- Create: `flutter/lib/pdf_export/session_pdf.dart`
- Modify: `flutter/lib/features/treatment/widgets/session_list_item.dart` (add share icon)

- [ ] **Step 1: Create `session_pdf.dart`**

```dart
import 'dart:typed_data';
import 'package:hive/hive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../app/providers.dart' show cacheBoxName;
import '../features/treatment/models.dart';

const _patientNameKey = 'community_patient_name';

String _patientName() =>
    Hive.box(cacheBoxName).get(_patientNameKey) as String? ?? 'Patient';

Future<Uint8List> buildSessionPdf(
    Session session, List<Reading> readings) async {
  final pdf = pw.Document();
  final name = _patientName();

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        // Header
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(name,
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text(session.date,
                style: const pw.TextStyle(fontSize: 12)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text('Session ${session.sessionId}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.Divider(),
        pw.SizedBox(height: 8),

        // Pre-treatment
        _sectionHeader('Pre-treatment'),
        _twoCol([
          ['Pre weight', '${session.preWeight ?? '-'} kg'],
          ['UF goal', '${session.ufGoal ?? '-'} L'],
          ['UF rate', '${session.ufRate ?? '-'} L/h'],
          ['BP', session.preBpSys != null ? '${session.preBpSys}/${session.preBpDia}' : '-'],
          ['Pulse', '${session.prePulse ?? '-'} bpm'],
        ]),
        pw.SizedBox(height: 12),

        // Readings table
        if (readings.isNotEmpty) ...[
          _sectionHeader('Readings'),
          pw.TableHelper.fromTextArray(
            headers: ['Time', 'BP', 'Pulse', 'BF (mL/min)', 'VP', 'AP', 'Note'],
            data: readings.map((r) => [
              r.time,
              r.bpSys != null ? '${r.bpSys}/${r.bpDia}' : '-',
              '${r.pulse ?? '-'}',
              '${r.bloodFlow ?? '-'}',
              '${r.venousPressure ?? '-'}',
              '${r.arterialPressure ?? '-'}',
              r.note ?? '',
            ]).toList(),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            border: pw.TableBorder.all(color: PdfColors.grey300),
            cellPadding: const pw.EdgeInsets.all(4),
          ),
          pw.SizedBox(height: 12),
        ],

        // Post-treatment
        _sectionHeader('Post-treatment'),
        _twoCol([
          ['Post weight', '${session.postWeight ?? '-'} kg'],
          ['BP', session.postBpSys != null ? '${session.postBpSys}/${session.postBpDia}' : '-'],
          ['Pulse', '${session.postPulse ?? '-'} bpm'],
          ['Duration', session.durationMin != null ? '${session.durationMin} min' : '-'],
          ['Dialysate vol', session.dialysateVolume != null ? '${session.dialysateVolume} L' : '-'],
          ['Total UF', session.totalUf != null ? '${session.totalUf} L' : '-'],
          ['Blood processed', session.bloodProcessed != null ? '${session.bloodProcessed} L' : '-'],
        ]),

        if (session.comment?.isNotEmpty ?? false) ...[
          pw.SizedBox(height: 12),
          _sectionHeader('Comment'),
          pw.Text(session.comment!, style: const pw.TextStyle(fontSize: 10)),
        ],

        // Footer
        pw.SizedBox(height: 24),
        pw.Center(
          child: pw.Text(
            'Generated ${DateTime.now().toIso8601String().substring(0, 10)} · Home HD Tracker',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
          ),
        ),
      ],
    ),
  );

  return pdf.save();
}

Future<Uint8List> buildSummaryPdf(
    List<Session> sessions, DateTime from, DateTime to) async {
  final pdf = pw.Document();
  final name = _patientName();

  final sorted = [...sessions]
    ..sort((a, b) => a.date.compareTo(b.date));
  final inRange = sorted.where((s) {
    final d = DateTime.tryParse(s.date);
    return d != null && !d.isBefore(from) && !d.isAfter(to);
  }).toList();

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        pw.Text('Home HD — Session Summary',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('$name  ·  ${from.toIso8601String().substring(0, 10)} to ${to.toIso8601String().substring(0, 10)}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.Divider(),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: ['Date', 'Duration', 'Pre BP', 'Post BP', 'UF goal', 'UF actual', 'Note'],
          data: inRange.map((s) => [
            s.date,
            s.durationMin != null ? '${s.durationMin} min' : '-',
            s.preBpSys != null ? '${s.preBpSys}/${s.preBpDia}' : '-',
            s.postBpSys != null ? '${s.postBpSys}/${s.postBpDia}' : '-',
            s.ufGoal != null ? '${s.ufGoal} L' : '-',
            s.totalUf != null ? '${s.totalUf} L' : '-',
            (s.comment ?? '').length > 30
                ? '${s.comment!.substring(0, 30)}…'
                : (s.comment ?? ''),
          ]).toList(),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          border: pw.TableBorder.all(color: PdfColors.grey300),
          cellPadding: const pw.EdgeInsets.all(3),
        ),
        pw.SizedBox(height: 24),
        pw.Center(
          child: pw.Text(
            'Generated ${DateTime.now().toIso8601String().substring(0, 10)} · Home HD Tracker',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
          ),
        ),
      ],
    ),
  );

  return pdf.save();
}

// PDF helpers

pw.Widget _sectionHeader(String title) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(title,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700)),
    );

pw.Widget _twoCol(List<List<String>> rows) {
  return pw.Wrap(
    spacing: 24,
    runSpacing: 4,
    children: rows
        .map((r) => pw.SizedBox(
              width: 200,
              child: pw.Row(children: [
                pw.SizedBox(
                  width: 100,
                  child: pw.Text(r[0],
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey600)),
                ),
                pw.Text(r[1], style: const pw.TextStyle(fontSize: 9)),
              ]),
            ))
        .toList(),
  );
}
```

**Reading fields verified against `models.dart`:** `r.time` (String HH:MM), `r.bpSys`, `r.bpDia`, `r.pulse`, `r.bloodFlow`, `r.venousPressure`, `r.arterialPressure`, `r.note`.

- [ ] **Step 2: Add share/export icon to `session_list_item.dart`**

In `flutter/lib/features/treatment/widgets/session_list_item.dart`, add import:

```dart
import '../../../flavor.dart';
import '../../../pdf_export/session_pdf.dart';
import 'package:printing/printing.dart';
```

In the `SessionListItem` build method, add a share icon button visible only in community. Find the trailing widget or actions area and add:

```dart
if (kCommunity)
  IconButton(
    icon: const Icon(Icons.share_outlined, size: 20),
    tooltip: 'Export PDF',
    onPressed: () async {
      final readings = await treatmentRepo.getReadings(session.sessionId);
      final bytes = await buildSessionPdf(session, readings);
      await Printing.sharePdf(bytes: bytes,
          filename: 'session_${session.sessionId.substring(0, 8)}.pdf');
    },
  ),
```

`treatmentRepo` must be available in this widget — pass it as a parameter or read from a `ConsumerWidget`. Convert `SessionListItem` to a `ConsumerWidget` if it isn't already, and use `ref.read(treatmentRepoProvider)`.

Also add a "Export range" action on the Treatment session list (in `session_detail.dart` or the home screen). In `flutter/lib/features/treatment/screens/home.dart`, add an export FAB or app bar action for monthly summary in community:

```dart
if (kCommunity)
  IconButton(
    icon: const Icon(Icons.picture_as_pdf_outlined),
    tooltip: 'Export summary PDF',
    onPressed: _exportSummary,
  ),
```

```dart
Future<void> _exportSummary() async {
  final result = await ref.read(treatmentRepoProvider).getAll();
  final to   = DateTime.now();
  final from = to.subtract(const Duration(days: 30));
  final bytes = await buildSummaryPdf(result.sessions, from, to);
  await Printing.sharePdf(bytes: bytes, filename: 'hd_summary.pdf');
}
```

- [ ] **Step 3: Verify build**

```bash
cd flutter && flutter build web --dart-define=FLAVOR=community 2>&1 | tail -5
```

Expected: no errors. If `Reading` field names are wrong, fix them now by checking `models.dart`.

- [ ] **Step 4: Commit**

```bash
git add flutter/lib/pdf_export/ flutter/lib/features/treatment/widgets/session_list_item.dart flutter/lib/features/treatment/screens/home.dart
git commit -m "feat(community): on-device PDF export for session detail and monthly summary"
```

---

### Task 17: Firebase Hosting second site + deploy scripts

**Files:**
- Modify: `firebase.json` (project root)
- Modify: `.firebaserc` (project root)

This task uses the Firebase CLI and does not change Flutter code.

- [ ] **Step 1: Create the second hosting site**

```bash
firebase hosting:sites:create homehd-community --project homehd-personal
```

Expected: `✔  Site homehd-community created.`

- [ ] **Step 2: Update `.firebaserc`**

Open `.firebaserc` at the project root. Add a `targets` section:

```json
{
  "projects": {
    "default": "homehd-personal"
  },
  "targets": {
    "homehd-personal": {
      "hosting": {
        "personal": ["homehd-personal"],
        "community": ["homehd-community"]
      }
    }
  }
}
```

- [ ] **Step 3: Update `firebase.json`**

Add a community hosting entry. The existing personal entry uses `public: "flutter/build/web"`. Add a second entry with a different `public` path:

```json
{
  "hosting": [
    {
      "target": "personal",
      "public": "flutter/build/web",
      "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
      "rewrites": [{ "source": "**", "destination": "/index.html" }],
      "headers": [
        {
          "source": "**/*.@(js|css|wasm)",
          "headers": [{ "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }]
        }
      ]
    },
    {
      "target": "community",
      "public": "flutter/build/community_web",
      "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
      "rewrites": [{ "source": "**", "destination": "/index.html" }],
      "headers": [
        {
          "source": "**/*.@(js|css|wasm)",
          "headers": [{ "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }]
        }
      ]
    }
  ]
}
```

- [ ] **Step 4: Build and deploy community**

```bash
cd flutter && flutter build web --dart-define=FLAVOR=community --output=build/community_web
firebase deploy --only hosting:community --project homehd-personal
```

Expected: `✔  Deploy complete!` with URL `https://homehd-community.web.app`.

- [ ] **Step 5: Verify community app loads**

Open `https://homehd-community.web.app` in a browser:
- App loads directly on Treatment (no Setup gate)
- Drawer shows Treatment, Blood Tests, Inventory, Knowledge Base, Settings — no Fitness
- Settings goes to the community settings screen
- Chat FAB is hidden (no AI key set yet)

- [ ] **Step 6: Commit firebase config**

```bash
git add firebase.json .firebaserc
git commit -m "feat(community): Firebase Hosting second site for community PWA distribution"
```

---

## Build Commands Reference

**Personal (unchanged):**
```bash
flutter build web
firebase deploy --only hosting:personal --project homehd-personal
```

**Community web (PWA):**
```bash
flutter build web --dart-define=FLAVOR=community --output=build/community_web
firebase deploy --only hosting:community --project homehd-personal
```

**Community APK (Android fallback):**
```bash
flutter build apk --dart-define=FLAVOR=community
# APK at build/app/outputs/flutter-apk/app-release.apk
```

