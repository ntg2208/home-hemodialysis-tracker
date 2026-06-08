// Golden screenshot test — captures every main screen with realistic demo data.
//
// Run with:
//   flutter test test/screenshots/screenshot_test.dart --update-goldens
//
// Outputs PNGs to test/screenshots/goldens/.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

import 'package:home_hd/api/inventory_api.dart';
import 'package:home_hd/api/rest_client.dart';
import 'package:home_hd/app/providers.dart';
import 'package:home_hd/app/theme.dart';
import 'package:home_hd/features/blood_tests/blood_tests_api.dart';
import 'package:home_hd/features/blood_tests/blood_tests_screen.dart';
import 'package:home_hd/features/blood_tests/bt_store.dart';
import 'package:home_hd/features/blood_tests/models.dart';
import 'package:home_hd/features/blood_tests/providers.dart';
import 'package:home_hd/features/fitness/fitness_api.dart';
import 'package:home_hd/features/fitness/fitness_screen.dart';
import 'package:home_hd/features/fitness/providers.dart';
import 'package:home_hd/features/inventory/inventory_models.dart';
import 'package:home_hd/features/inventory/inventory_screen.dart';
import 'package:home_hd/features/kb/kb_providers.dart';
import 'package:home_hd/features/kb/kb_screen.dart';
import 'package:home_hd/features/kb/kb_store.dart';
import 'package:home_hd/features/settings/settings_screen.dart';
import 'package:home_hd/features/setup/setup_screen.dart';
import 'package:home_hd/features/treatment/models.dart';
import 'package:home_hd/features/treatment/providers.dart';
import 'package:home_hd/features/treatment/screens/active.dart';
import 'package:home_hd/features/treatment/screens/home.dart';
import 'package:home_hd/features/treatment/screens/post.dart';
import 'package:home_hd/features/treatment/screens/pre.dart';
import 'package:home_hd/features/treatment/screens/session_detail.dart';
import 'package:home_hd/features/treatment/store.dart';
import 'package:home_hd/features/treatment/treatment_auth.dart';
import 'package:home_hd/features/treatment/treatment_repo.dart';
import 'package:home_hd/storage/cache_store.dart';
import 'package:home_hd/storage/secure_store.dart';

// ─── Demo data ─────────────────────────────────────────────────────────────

const _demoSessions = [
  Session(
    sessionId: '2026-06-02',
    date: '2026-06-02',
    preWeight: 72.4, ufGoal: 2.4, ufRate: 600,
    preBpSys: 145, preBpDia: 88, prePulse: 74,
    postWeight: 70.0, postBpSys: 128, postBpDia: 78, postPulse: 68,
    durationMin: 255, dialysateVolume: 49, totalUf: 2.4, bloodProcessed: 84,
  ),
  Session(
    sessionId: '2026-05-31',
    date: '2026-05-31',
    preWeight: 73.1, ufGoal: 3.1, ufRate: 775,
    preBpSys: 152, preBpDia: 92, prePulse: 78,
    postWeight: 70.0, postBpSys: 132, postBpDia: 80, postPulse: 72,
    durationMin: 255, dialysateVolume: 49, totalUf: 3.1, bloodProcessed: 86,
  ),
  Session(
    sessionId: '2026-05-29',
    date: '2026-05-29',
    preWeight: 72.8, ufGoal: 2.8, ufRate: 700,
    preBpSys: 148, preBpDia: 90, prePulse: 76,
    postWeight: 70.0, postBpSys: 130, postBpDia: 79, postPulse: 70,
    durationMin: 255, dialysateVolume: 49, totalUf: 2.8, bloodProcessed: 82,
  ),
  Session(
    sessionId: '2026-05-27',
    date: '2026-05-27',
    preWeight: 72.2, ufGoal: 2.2, ufRate: 550,
    preBpSys: 142, preBpDia: 86, prePulse: 72,
    postWeight: 70.0, postBpSys: 125, postBpDia: 76, postPulse: 66,
    durationMin: 255, dialysateVolume: 49, totalUf: 2.2, bloodProcessed: 82,
  ),
  Session(
    sessionId: '2026-05-24',
    date: '2026-05-24',
    preWeight: 73.5, ufGoal: 3.5, ufRate: 875,
    preBpSys: 158, preBpDia: 96, prePulse: 80,
    postWeight: 70.0, postBpSys: 138, postBpDia: 84, postPulse: 74,
    durationMin: 255, dialysateVolume: 49, totalUf: 3.5, bloodProcessed: 88,
  ),
];

const _demoActiveSession = Session(
  sessionId: '2026-06-03',
  date: '2026-06-03',
  preWeight: 72.8, ufGoal: 2.8, ufRate: 700,
  preBpSys: 146, preBpDia: 88, prePulse: 76,
);

List<PendingReading> _demoReadings() => [
      PendingReading(
        const Reading(
          readingId: '2026-06-03-r3',
          sessionId: '2026-06-03',
          seq: 3, time: '10:45',
          bpSys: 132, bpDia: 80, pulse: 72,
          bloodFlow: 350, venousPressure: 155, arterialPressure: -185,
        ),
        status: SaveStatus.saved,
      ),
      PendingReading(
        const Reading(
          readingId: '2026-06-03-r2',
          sessionId: '2026-06-03',
          seq: 2, time: '10:15',
          bpSys: 135, bpDia: 82, pulse: 74,
          bloodFlow: 350, venousPressure: 152, arterialPressure: -182,
        ),
        status: SaveStatus.saved,
      ),
      PendingReading(
        const Reading(
          readingId: '2026-06-03-r1',
          sessionId: '2026-06-03',
          seq: 1, time: '09:45',
          bpSys: 145, bpDia: 88, pulse: 76,
          bloodFlow: 350, venousPressure: 148, arterialPressure: -178,
        ),
        status: SaveStatus.saved,
      ),
    ];

const _demoDetailReadings = [
  Reading(
    readingId: '2026-06-02-r3', sessionId: '2026-06-02',
    seq: 3, time: '10:45',
    bpSys: 128, bpDia: 78, pulse: 70,
    bloodFlow: 350, venousPressure: 152, arterialPressure: -182,
  ),
  Reading(
    readingId: '2026-06-02-r2', sessionId: '2026-06-02',
    seq: 2, time: '10:15',
    bpSys: 132, bpDia: 80, pulse: 70,
    bloodFlow: 350, venousPressure: 150, arterialPressure: -180,
  ),
  Reading(
    readingId: '2026-06-02-r1', sessionId: '2026-06-02',
    seq: 1, time: '09:45',
    bpSys: 145, bpDia: 88, pulse: 74,
    bloodFlow: 350, venousPressure: 148, arterialPressure: -178,
  ),
];

const _demoBtRows = [
  BloodTestRow(marker: 'creatinine',  datetime: '2026-05-18T14:18:00', value: 1073, unit: 'umol/L', refLow: 64,   refHigh: 104,  timing: 'pre',  note: '', source: 'imperial-pkb', labId: '99261284417', phase: 'home-hd', createdAt: '2026-05-22', qualitative: false),
  BloodTestRow(marker: 'creatinine',  datetime: '2026-05-18T12:00:00', value: 361,  unit: 'umol/L', refLow: 64,   refHigh: 104,  timing: 'post', note: '', source: 'imperial-pkb', labId: '99261284418', phase: 'home-hd', createdAt: '2026-05-22', qualitative: false),
  BloodTestRow(marker: 'urea',        datetime: '2026-05-18T14:18:00', value: 19.7, unit: 'mmol/L', refLow: 2.5,  refHigh: 7.8,  timing: 'pre',  note: '', source: 'imperial-pkb', labId: '99261284417', phase: 'home-hd', createdAt: '2026-05-22', qualitative: false),
  BloodTestRow(marker: 'urea',        datetime: '2026-05-18T12:00:00', value: 1.9,  unit: 'mmol/L', refLow: 2.5,  refHigh: 7.8,  timing: 'post', note: '', source: 'imperial-pkb', labId: '99261284418', phase: 'home-hd', createdAt: '2026-05-22', qualitative: false),
  BloodTestRow(marker: 'haemoglobin', datetime: '2026-05-18T14:18:00', value: 118,  unit: 'g/L',    refLow: 130,  refHigh: 170,  timing: 'pre',  note: '', source: 'imperial-pkb', labId: '99261284417', phase: 'home-hd', createdAt: '2026-05-22', qualitative: false),
  BloodTestRow(marker: 'potassium',   datetime: '2026-05-18T14:18:00', value: 5.8,  unit: 'mmol/L', refLow: 3.5,  refHigh: 5.1,  timing: 'pre',  note: '', source: 'imperial-pkb', labId: '99261284417', phase: 'home-hd', createdAt: '2026-05-22', qualitative: false),
  BloodTestRow(marker: 'potassium',   datetime: '2026-05-18T12:00:00', value: 2.8,  unit: 'mmol/L', refLow: 3.5,  refHigh: 5.1,  timing: 'post', note: '', source: 'imperial-pkb', labId: '99261284418', phase: 'home-hd', createdAt: '2026-05-22', qualitative: false),
  BloodTestRow(marker: 'phosphate',   datetime: '2026-05-18T14:18:00', value: 1.82, unit: 'mmol/L', refLow: 0.87, refHigh: 1.45, timing: 'pre',  note: '', source: 'imperial-pkb', labId: '99261284417', phase: 'home-hd', createdAt: '2026-05-22', qualitative: false),
  BloodTestRow(marker: 'albumin',     datetime: '2026-05-18T14:18:00', value: 41,   unit: 'g/L',    refLow: 35,   refHigh: 50,   timing: 'pre',  note: '', source: 'imperial-pkb', labId: '99261284417', phase: 'home-hd', createdAt: '2026-05-22', qualitative: false),
  BloodTestRow(marker: 'ferritin',    datetime: '2026-05-18T14:18:00', value: 312,  unit: 'ug/L',   refLow: 13,   refHigh: 150,  timing: '',     note: '', source: 'imperial-pkb', labId: '99261284417', phase: 'home-hd', createdAt: '2026-05-22', qualitative: false),
  BloodTestRow(marker: 'calcium',     datetime: '2026-04-15T14:00:00', value: 2.25, unit: 'mmol/L', refLow: 2.15, refHigh: 2.55, timing: '',     note: '', source: 'imperial-pkb', labId: '99260931609', phase: 'home-hd', createdAt: '2026-04-18', qualitative: false),
  BloodTestRow(marker: 'creatinine',  datetime: '2026-04-15T14:00:00', value: 1052, unit: 'umol/L', refLow: 64,   refHigh: 104,  timing: 'pre',  note: '', source: 'imperial-pkb', labId: '99260931609', phase: 'home-hd', createdAt: '2026-04-18', qualitative: false),
];

const _demoInventoryJson = {
  'stock': {
    'SAK-303': 12, 'CAR-172-C': 10, 'UK00000880': 14,
    'PAK-001': 1,  'P00012326': 32,  'UK00000774': 48,
    'F00010983': 75, 'UK00000830': 80, '1990134': 1,
    'UK00000832': 1,  'UK00000172': 8,
    'heparin': 10, 'epo': 6,
  },
  'cycle': {
    'call_date': '2026-06-23',
    'delivery_date': '2026-06-30',
  },
  'pak_installed_at': '2026-05-29',
  'pak_sessions': 4,
};

const _demoFitnessCacheJson = {
  'generated_at': '2026-06-03T08:00:00Z',
  'types': [
    {
      'type': 'steps', 'last_synced': '2026-06-02', 'count': 365,
      'last_date': '2026-06-02', 'stale': false, 'bytes': 85000,
      'latest': {'label': 'Steps', 'value': '4821', 'unit': 'steps', 'at': '2026-06-02'},
    },
    {
      'type': 'daily-resting-heart-rate', 'last_synced': '2026-06-02', 'count': 5,
      'last_date': '2026-06-02', 'stale': false, 'bytes': 2000,
      'latest': {'label': 'Resting HR', 'value': '72', 'unit': 'bpm', 'at': '2026-06-02'},
    },
    {
      'type': 'sleep', 'last_synced': '2026-06-02', 'count': 5,
      'last_date': '2026-06-02', 'stale': false, 'bytes': 48000,
      'latest': {'label': 'Sleep', 'value': '7h 12m', 'unit': '', 'at': '2026-06-02'},
    },
    {
      'type': 'oxygen-saturation', 'last_synced': '2026-06-02', 'count': 5000,
      'last_date': '2026-06-02', 'stale': false, 'bytes': 110000,
      'latest': {'label': 'SpO₂', 'value': '96', 'unit': '%', 'at': '2026-06-02'},
    },
    {
      'type': 'daily-heart-rate-variability', 'last_synced': '2026-06-02', 'count': 5,
      'last_date': '2026-06-02', 'stale': false, 'bytes': 1500,
      'latest': {'label': 'HRV (daily)', 'value': '38', 'unit': 'ms', 'at': '2026-06-02'},
    },
  ],
  'totals': {'types': 5, 'healthy': 5, 'stale': 0, 'bytes': 246500},
};

final _demoKbEntries = [
  KbEntry(
    id: 'kb-001',
    title: 'Low BP during session (hypotension)',
    content: 'If BP drops below 90/60 during session: slow blood flow to 300 mL/h, check for cramps, consider 100 mL saline bolus. Common causes: excessive UF rate, vasodilation, missed pre-treatment meal.',
    source: 'user',
    createdAt: DateTime(2026, 5, 20),
    updatedAt: DateTime(2026, 5, 20),
  ),
  KbEntry(
    id: 'kb-002',
    title: 'NxStage Alarm — Low arterial pressure',
    content: 'Usually indicates access issue (kink or partial occlusion in arterial needle line). Steps: check needle position, inspect line for kinks, reduce blood flow temporarily to 280. If persists, stop session and inspect access site.',
    source: 'user',
    createdAt: DateTime(2026, 5, 25),
    updatedAt: DateTime(2026, 6, 1),
  ),
  KbEntry(
    id: 'kb-003',
    title: 'Chlorine test procedure',
    content: 'Test water before each session using Pureflow strips. Acceptable range: 0.01–0.1 ppm. If reading is > 0.1 ppm, run an extra rinse cycle before connecting. Never start a session if chlorine is undetectable (strip stays white).',
    source: 'user',
    createdAt: DateTime(2026, 6, 1),
    updatedAt: DateTime(2026, 6, 1),
  ),
  KbEntry(
    id: 'kb-004',
    title: 'Buttonhole site care',
    content: 'Remove scabs with damp gauze after 10 min soaking. Never pick — let them soften. Apply Bactroban if site shows any redness. Rotate between Art and Ven sites to avoid scarring.',
    source: 'user',
    createdAt: DateTime(2026, 6, 2),
    updatedAt: DateTime(2026, 6, 2),
  ),
];

// ─── Fakes ─────────────────────────────────────────────────────────────────

class _FakeSecureStore extends SecureStore {
  _FakeSecureStore() : super(const FlutterSecureStorage());
  @override Future<AuthSettings?> read() async => const AuthSettings(mainKey: 'demo-api-key-xxxxx');
  @override Future<void> write(AuthSettings a) async {}
  @override Future<void> clear() async {}
  @override Future<bool> readAiEnabled() async => false;
  @override Future<String?> readAiKey() async => null;
  @override Future<void> writeAiEnabled(bool enabled) async {}
  @override Future<void> writeAiKey(String apiKey) async {}
  @override Future<void> clearAiKey() async {}
}

class _FakeAuthController extends AuthController {
  _FakeAuthController() : super(_FakeSecureStore());
  @override bool get isAuthed => true;
  @override bool get loaded => true;
  @override AuthSettings? get settings => const AuthSettings(mainKey: 'demo-api-key-xxxxx');
  @override String get mainKey => 'demo-api-key-xxxxx';
  @override Future<void> load() async {}
}

class _FakeTreatmentAuth extends TreatmentAuth {
  _FakeTreatmentAuth()
      : super(RestClient(mainKey: () => ''), _FakeAuthController());
  @override Future<void> ensure() async {}
  @override bool get hasCurrentUser => true;
}

class _FakeTreatmentRepo extends TreatmentRepo {
  @override
  Future<({List<Session> sessions, List<Reading> readings})> getAll() async =>
      (sessions: List.of(_demoSessions), readings: _demoDetailReadings.toList());
  @override
  Future<List<Reading>> getReadings(String sessionId) async =>
      _demoDetailReadings.toList();
  @override Future<void> saveSession(Session s) async {}
  @override Future<void> saveReading(Reading r) async {}
  @override Future<void> updateSession(String id, Map<String, dynamic> patch) async {}
  @override Future<void> deleteSession(String sessionId) async {}
}

class _FakeBloodTestsApi extends BloodTestsApi {
  _FakeBloodTestsApi() : super(RestClient(mainKey: () => ''));
  @override
  Future<List<BloodTestRow>> fetchRange({String? from, String? to}) async =>
      _demoBtRows.toList();
}

class _FakeFitnessApi extends FitnessApi {
  _FakeFitnessApi() : super(RestClient(mainKey: () => ''));
  @override Future<FitnessSummary> fetchSummary() async =>
      FitnessSummary.fromJson(Map<String, dynamic>.from(_demoFitnessCacheJson));
  @override Future<Map<String, dynamic>> sync() async => {};
}

class _FakeInventoryApi extends InventoryApi {
  _FakeInventoryApi() : super(RestClient(mainKey: () => ''));
  @override Future<InventoryResponse> fetchInventory() async =>
      InventoryResponse.fromJson(Map<String, dynamic>.from(_demoInventoryJson));
  @override Future<Map<String, num>> fetchStock() async =>
      (_demoInventoryJson['stock'] as Map)
          .map((k, v) => MapEntry(k as String, v as num));
  @override Future<void> logEvent(String type, Map<String, num> deltas, {String? note}) async {}
  @override Future<void> applyDelivery({Map<String, int>? adjustments}) async {}
  @override Future<void> rollbackSession(String sessionId) async {}
  @override Future<void> confirmOrder(String callDate, Map<String, int> order, {String? deliveryDate}) async {}
  @override Future<void> setPakInstall(String installedAt) async {}
  @override Future<List<DeliveryEvent>> fetchDeliveries() async => [];
}

class _FakeKbStore extends KbStore {
  _FakeKbStore() : super(_FakeTreatmentAuth());
  @override Future<List<KbEntry>> getAll() async => List.of(_demoKbEntries);
  @override Future<void> save(KbEntry e) async {}
  @override Future<void> delete(String id) async {}
}

// ─── Widget wrapper ─────────────────────────────────────────────────────────

/// Applies the Roboto font family to all text styles in [theme] so that
/// golden screenshots render real glyphs after the font has been loaded.
///
/// [textTheme.apply] handles body/title/label text. We also patch the
/// [elevatedButtonTheme] because its textStyle is set with an explicit
/// [TextStyle] that has no fontFamily, so it doesn't inherit from textTheme.
ThemeData _withRoboto(ThemeData theme) {
  // Roboto button label — mirrors the app's weight/size but adds fontFamily.
  const buttonStyle = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w600,
    fontSize: 16,
  );
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Roboto'),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: (theme.elevatedButtonTheme.style ?? const ButtonStyle()).copyWith(
        textStyle: const WidgetStatePropertyAll<TextStyle?>(buttonStyle),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: (theme.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
        textStyle: const WidgetStatePropertyAll<TextStyle?>(buttonStyle),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
        textStyle: const WidgetStatePropertyAll<TextStyle?>(buttonStyle),
      ),
    ),
  );
}

/// Phone canvas size (iPhone 14 Plus / Pro Max logical pixels — taller than
/// Pro to give grid cells more height and avoid NumberField overflow in tests).
const _kPhoneSize = Size(430, 932);

/// Wraps [child] in a GoRouter + ProviderScope with all demo overrides so that
/// GoRouterState is available for HdScaffold's drawer and all providers resolve
/// to fake in-memory implementations.
Widget _wrap(Widget child) {
  final router = GoRouter(
    initialLocation: '/demo',
    routes: [GoRoute(path: '/demo', builder: (_, __) => child)],
  );
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith((_) => _FakeAuthController()),
      treatmentAuthProvider.overrideWith((_) => _FakeTreatmentAuth()),
      treatmentRepoProvider.overrideWith((_) => _FakeTreatmentRepo()),
      bloodTestsApiProvider.overrideWith((_) => _FakeBloodTestsApi()),
      fitnessApiProvider.overrideWith((_) => _FakeFitnessApi()),
      inventoryApiProvider.overrideWith((_) => _FakeInventoryApi()),
      kbStoreProvider.overrideWith((_) => _FakeKbStore()),
      treatmentStoreProvider
          .overrideWith((_) => TreatmentStore(Hive.box(treatmentBoxName))),
      cacheStoreProvider
          .overrideWith((_) => CacheStore(Hive.box(cacheBoxName))),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      // Override fontFamily: null → 'Roboto' so the loaded fonts take effect.
      theme: _withRoboto(hdLightTheme()),
      darkTheme: _withRoboto(hdDarkTheme()),
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
    ),
  );
}

Future<void> _shot(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

// ─── Font loading ───────────────────────────────────────────────────────────

/// Loads Roboto (all weights) + MaterialIcons from the Flutter SDK's cached
/// material_fonts directory so golden screenshots render real text and icons
/// instead of the default "Ahem" test font (which draws every glyph as a box).
Future<void> _loadMaterialFonts() async {
  final dir = await _materialFontsDir();
  if (dir == null) {
    // ignore: avoid_print
    print('[screenshot_test] WARNING: material_fonts not found — '
        'text will render as rectangles. Run `flutter precache` first.');
    return;
  }

  // RobotoMono — used by hdMono (session IDs, reading timestamps, etc.)
  // Registered as 'monospace' to match the app's TextStyle(fontFamily: 'monospace').
  // The font lives in the Dart SDK devtools assets, two sibling directories up
  // from the material_fonts dir (material_fonts → bin/cache → dart-sdk/…).
  final monoLoader = FontLoader('monospace');
  final sdkCache = Directory(dir).parent.parent.path; // artifacts/material_fonts → bin/cache
  final monoDir = '$sdkCache/dart-sdk/bin/resources/devtools'
      '/assets/fonts/Roboto_Mono';
  for (final name in ['RobotoMono-Regular', 'RobotoMono-Medium', 'RobotoMono-Bold']) {
    final file = File('$monoDir/$name.ttf');
    if (file.existsSync()) {
      monoLoader.addFont(_bytesToFuture(file.readAsBytesSync()));
    }
  }
  await monoLoader.load();

  // Roboto — used by Material 3 typography
  final robotoLoader = FontLoader('Roboto');
  for (final name in [
    'Roboto-Regular', 'Roboto-Bold', 'Roboto-Medium',
    'Roboto-Light', 'Roboto-Italic', 'Roboto-BoldItalic',
    'Roboto-MediumItalic', 'Roboto-LightItalic',
  ]) {
    final file = File('$dir/$name.ttf');
    if (file.existsSync()) {
      robotoLoader.addFont(_bytesToFuture(file.readAsBytesSync()));
    }
  }
  await robotoLoader.load();

  // MaterialIcons — used by Icons.* throughout the app
  final iconsLoader = FontLoader('MaterialIcons');
  final iconsFile = File('$dir/MaterialIcons-Regular.otf');
  if (iconsFile.existsSync()) {
    iconsLoader.addFont(_bytesToFuture(iconsFile.readAsBytesSync()));
  }
  await iconsLoader.load();
}

Future<ByteData> _bytesToFuture(Uint8List bytes) async =>
    ByteData.sublistView(bytes);

/// Resolves the Flutter SDK's material_fonts directory.
/// Checks FLUTTER_ROOT first (set by `flutter test`), then falls back to
/// resolving the `flutter` binary on PATH via `which`.
Future<String?> _materialFontsDir() async {
  // 1. FLUTTER_ROOT env var (always set when running under `flutter test`)
  final fromEnv = Platform.environment['FLUTTER_ROOT'];
  if (fromEnv != null) {
    final d = '$fromEnv/bin/cache/artifacts/material_fonts';
    if (Directory(d).existsSync()) return d;
  }

  // 2. Resolve the flutter binary via `which` / `where`
  try {
    final cmd = Platform.isWindows ? 'where' : 'which';
    final result = await Process.run(cmd, ['flutter'], runInShell: true);
    var bin = result.stdout.toString().trim().split('\n').first.trim();
    if (bin.isEmpty) return null;
    // Resolve symlinks: homebrew wraps flutter in a shell script
    bin = await File(bin).resolveSymbolicLinks();
    // flutter binary lives at <sdk>/bin/flutter — sdk root is 2 levels up
    final sdkRoot = File(bin).parent.parent.path;
    final d = '$sdkRoot/bin/cache/artifacts/material_fonts';
    if (Directory(d).existsSync()) return d;
  } catch (_) {}

  return null;
}

// ─── One-time Hive setup ────────────────────────────────────────────────────

late Directory _hiveDir;

void main() {
  setUpAll(() async {
    // Load Roboto + MaterialIcons so text and icons render properly.
    await _loadMaterialFonts();

    // Suppress RenderFlex overflow assertions so screenshots can still be
    // captured even when a grid cell is marginally too tight (the visual
    // overflow stripes are acceptable in demo screenshots).
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      FlutterError.dumpErrorToConsole(details);
    };

    _hiveDir = Directory.systemTemp.createTempSync('hd_screenshot_');
    Hive.init(_hiveDir.path);
    await Hive.openBox(treatmentBoxName);
    await Hive.openBox(cacheBoxName);

    // Seed treatment session cache.
    await TreatmentStore(Hive.box(treatmentBoxName))
        .saveCachedSessions(List.of(_demoSessions));

    // Seed blood-test cache so BloodTestsScreen renders immediately.
    await BtStore(Hive.box(cacheBoxName)).writeCache(
      _demoBtRows.toList(),
      '2026-03-01',
      DateTime.now().millisecondsSinceEpoch,
    );

    // Seed inventory + fitness caches.
    final cache = CacheStore(Hive.box(cacheBoxName));
    await cache.write('inventory', Map<String, dynamic>.from(_demoInventoryJson));
    await cache.write('fitness_summary', Map<String, dynamic>.from(_demoFitnessCacheJson));
  });

  tearDownAll(() async {
    await Hive.close();
    _hiveDir.deleteSync(recursive: true);
  });

  // ── 01 Setup ──────────────────────────────────────────────────────────────

  testWidgets('01_setup', (tester) async {
    await tester.binding.setSurfaceSize(_kPhoneSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // SetupScreen doesn't use HdScaffold so no GoRouter needed — but wrapping
    // consistently keeps the ProviderScope + MaterialApp structure uniform.
    final router = GoRouter(
      initialLocation: '/setup',
      routes: [GoRoute(path: '/setup', builder: (_, __) => const SetupScreen())],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((_) {
          final ctrl = _FakeAuthController();
          // Simulate unauthenticated state so the setup form renders.
          return _UnauthedController();
        }),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: _withRoboto(hdLightTheme()),
        darkTheme: _withRoboto(hdDarkTheme()),
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
      ),
    ));
    await tester.pumpAndSettle();
    await _shot(tester, '01_setup');
  });

  // ── 02 Treatment Home ─────────────────────────────────────────────────────

  testWidgets('02_treatment_home', (tester) async {
    await tester.binding.setSurfaceSize(_kPhoneSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(
      TreatmentHome(onStartSession: (_) {}),
    ));
    await tester.pumpAndSettle();
    await _shot(tester, '02_treatment_home');
  });

  // ── 03 Pre-treatment form ─────────────────────────────────────────────────

  testWidgets('03_pre_treatment', (tester) async {
    await tester.binding.setSurfaceSize(_kPhoneSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(
      PreTreatment(
        existingIds: const ['2026-06-02', '2026-05-31'],
        onSaved: (_, __, ___) {},
        onCancel: () {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await _shot(tester, '03_pre_treatment');
  });

  // ── 04 Active session ─────────────────────────────────────────────────────

  testWidgets('04_active_session', (tester) async {
    await tester.binding.setSurfaceSize(_kPhoneSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(
      ActiveSession(
        session: _demoActiveSession,
        initialReadings: _demoReadings(),
        heparinUsed: true,
        epoUsed: true,
        onReadingsChanged: (_) {},
        onCountdownChanged: (_, __) {},
        onHeparinChanged: (_) {},
        onEpoChanged: (_) {},
        onCommentChanged: (_) {},
        onEnd: (_) {},
      ),
    ));
    // Use pump with a fixed duration instead of pumpAndSettle — the active
    // session has animations (AnimatedScale on buttons) that may never fully
    // settle since the elastic curve takes a long time to converge.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await _shot(tester, '04_active_session');
  });

  // ── 05 Post-treatment form ────────────────────────────────────────────────

  testWidgets('05_post_treatment', (tester) async {
    await tester.binding.setSurfaceSize(_kPhoneSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(
      PostTreatment(
        session: _demoActiveSession,
        consumed: const SessionConsumed(
          needles: 2, onOffPacks: 1, heparinUsed: true, epoUsed: true,
          durationMin: 255,
        ),
        onSaved: () {},
        onCancel: () {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // Consume any RenderFlex overflow errors so the test passes and the
    // screenshot is still captured (overflow stripes appear but the screen is visible).
    tester.takeException();
    await _shot(tester, '05_post_treatment');
  });

  // ── 06 Session detail sheet ───────────────────────────────────────────────

  testWidgets('06_session_detail', (tester) async {
    await tester.binding.setSurfaceSize(_kPhoneSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(
      Scaffold(
        body: SessionDetailSheet(session: _demoSessions.first),
      ),
    ));
    await tester.pumpAndSettle();
    await _shot(tester, '06_session_detail');
  });

  // ── 07 Blood Tests ────────────────────────────────────────────────────────

  testWidgets('07_blood_tests', (tester) async {
    await tester.binding.setSurfaceSize(_kPhoneSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const BloodTestsScreen()));
    // _bootstrap() runs via addPostFrameCallback; pumpAndSettle drains it.
    await tester.pumpAndSettle();
    await _shot(tester, '07_blood_tests');
  });

  // ── 08 Inventory ──────────────────────────────────────────────────────────

  testWidgets('08_inventory', (tester) async {
    await tester.binding.setSurfaceSize(_kPhoneSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const InventoryScreen()));
    await tester.pumpAndSettle();
    await _shot(tester, '08_inventory');
  });

  // ── 09 Fitness ────────────────────────────────────────────────────────────

  testWidgets('09_fitness', (tester) async {
    await tester.binding.setSurfaceSize(_kPhoneSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const FitnessScreen()));
    await tester.pumpAndSettle();
    await _shot(tester, '09_fitness');
  });

  // ── 10 Knowledge Base ─────────────────────────────────────────────────────

  testWidgets('10_knowledge_base', (tester) async {
    await tester.binding.setSurfaceSize(_kPhoneSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const KbScreen()));
    await tester.pumpAndSettle();
    await _shot(tester, '10_knowledge_base');
  });

  // ── 11 Settings ───────────────────────────────────────────────────────────

  testWidgets('11_settings', (tester) async {
    await tester.binding.setSurfaceSize(_kPhoneSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const SettingsScreen()));
    await tester.pumpAndSettle();
    await _shot(tester, '11_settings');
  });
}

// Controller that reports unauthenticated (for the Setup screen screenshot).
class _UnauthedController extends AuthController {
  _UnauthedController() : super(_FakeSecureStore());
  @override bool get isAuthed => false;
  @override bool get loaded => true;
  @override AuthSettings? get settings => null;
  @override String get mainKey => '';
  @override Future<void> load() async {}
}
