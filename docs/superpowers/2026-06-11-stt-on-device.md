# On-Device STT: Replace Gemini Audio with sherpa-onnx + Moonshine Small

**Date:** 2026-06-11  
**Status:** Ready to implement (post-Opus review)  
**Motivation:** Gemini audio transcription adds ~500–800ms latency (network round-trip). On-device
inference targets ~200–300ms — needs verification on low-end Android before treating as fact.

---

## Context

### Current flow (`chat_sheet.dart`)

```
record (PCM16, 16kHz, mono) → _audioChunks → _buildWav() → Gemini 2.5-flash-lite → text
```

The `record` package streams raw PCM16 chunks into `_audioChunks` before `_buildWav()` wraps them.
Gemini needs the WAV. sherpa-onnx needs `Float32List` samples. The interface design (see below)
exposes both so each backend gets what it actually needs without redundant encoding.

### Constraint: no Flutter web build for sherpa-onnx

`sherpa_onnx` depends on `dart:ffi` / `dart:io`, which do not exist on web. A `kIsWeb` **runtime**
guard is insufficient — the import alone breaks the web compilation unit. A **conditional import**
is required (see Task 4).

---

## Model

**Moonshine (sherpa-onnx variant — verify exact slug)**

The upstream model name is "Small" but the sherpa-onnx release slug may differ. Confirm the exact
archive name and the five model files against `OfflineMoonshineModelConfig`'s fields before
wiring task 4:

| Config field | File |
|---|---|
| `OfflineModelConfig.tokens` | `tokens.txt` |
| `OfflineMoonshineModelConfig.preprocessor` | `preprocess.onnx` |
| `OfflineMoonshineModelConfig.encoder` | `encode.int8.onnx` |
| `OfflineMoonshineModelConfig.uncachedDecoder` | `uncached_decode.int8.onnx` |
| `OfflineMoonshineModelConfig.cachedDecoder` | `cached_decode.int8.onnx` |

Approximate figures (unverified — measure on device in Task 7):

| | Estimate |
|---|---|
| WER (English) | ~7–8% |
| Disk | ~123 MB |
| Peak RAM during load | Unknown — measure; OOM risk on low-end Android |
| Inference latency | Unknown — measure on low-end target |

---

## sherpa-onnx API (verified against pub.dev)

### One-time startup: `initBindings()`

Must be called **exactly once** before any sherpa-onnx API is used, ideally in `main.dart` before
`runApp`. Omitting it causes every recognizer call to fail at runtime.

```dart
// main.dart
import 'package:sherpa_onnx/sherpa_onnx.dart';
...
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initBindings();            // ← required, exactly once
  ...
  runApp(const App());
}
```

### Inference flow (synchronous, CPU-bound)

```dart
// 1. Build config
final config = OfflineRecognizerConfig(
  model: OfflineModelConfig(
    tokens: tokensPath,
    moonshine: OfflineMoonshineModelConfig(
      preprocessor: preprocessorPath,
      encoder: encoderPath,
      uncachedDecoder: uncachedDecoderPath,
      cachedDecoder: cachedDecoderPath,
    ),
  ),
);

// 2. Create recognizer (one per app session — expensive to create)
final recognizer = OfflineRecognizer(config);

// 3. Per-utterance transcription
final stream = recognizer.createStream();
stream.acceptWaveform(samples: float32Samples, sampleRate: 16000);
recognizer.decode(stream);              // synchronous void — blocks calling isolate
final result = recognizer.getResult(stream);
final text = result.text;
stream.free();                          // free native memory

// 4. On app teardown
recognizer.free();
```

**Key points:**
- `acceptWaveform` takes `Float32List` normalized samples (`pcm16 / 32768.0`), not WAV bytes.
- `decode()` is synchronous and CPU-bound — must run on a background isolate to avoid UI jank.
- `recognizer.free()` and `stream.free()` release native memory — must be called explicitly.

### PCM16 → Float32List conversion

```dart
Float32List pcm16ToFloat32(Uint8List pcm16Bytes) {
  final samples = Float32List(pcm16Bytes.length ~/ 2);
  final byteData = pcm16Bytes.buffer.asByteData();
  for (var i = 0; i < samples.length; i++) {
    samples[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return samples;
}
```

The raw PCM bytes are available in `_audioChunks` before `_buildWav()` is called — pass those
to `SherpaTranscriber` directly. `_buildWav()` is still called for `GeminiTranscriber`.

---

## Architecture

### New files

```
lib/features/chat/
  voice_transcriber.dart              ← abstract interface
  sherpa_transcriber.dart             ← mobile implementation
  sherpa_transcriber_stub.dart        ← web stub (no sherpa imports)
  gemini_transcriber.dart             ← web/fallback implementation
```

### Interface

```dart
// voice_transcriber.dart
abstract interface class VoiceTranscriber {
  /// Initialise (download model if needed). Must be awaited before transcribe().
  Future<void> init();

  /// Transcribe raw PCM16 bytes (16kHz mono). Returns null on failure.
  /// Each backend converts to its own required format internally.
  Future<String?> transcribe(Uint8List pcm16Bytes);

  /// Download progress 0.0→1.0, null when model already on disk or not applicable.
  Stream<double>? get downloadProgress;

  /// True once ready to transcribe.
  bool get isReady;

  /// Release resources (native handles, streams).
  void dispose();
}
```

`GeminiTranscriber` also needs WAV bytes. It calls `_buildWav()` internally — the interface
passes raw PCM16 to both, each converts as needed.

### Conditional import (required for web build)

```dart
// chat_sheet.dart
import 'voice_transcriber.dart';
import 'gemini_transcriber.dart';
import 'sherpa_transcriber_stub.dart'     // no-op stub
    if (dart.library.io) 'sherpa_transcriber.dart';
```

`sherpa_transcriber_stub.dart` re-exports a class with the same name as `SherpaTranscriber` but
contains no `sherpa_onnx` imports — it throws `UnsupportedError` from `init()`. Web always
uses `GeminiTranscriber` so the stub is never actually called.

### Platform selection in `chat_sheet.dart`

```dart
late VoiceTranscriber _transcriber;

@override
void initState() {
  super.initState();
  _transcriber = kIsWeb ? GeminiTranscriber(ref) : SherpaTranscriber();
  _transcriber.init().then((_) { if (mounted) setState(() {}); });
  // listen to downloadProgress for progress UI
  _transcriber.downloadProgress?.listen(
    (p) { if (mounted) setState(() => _downloadProgress = p); },
    onDone: () { if (mounted) setState(() => _downloadProgress = null); },
  );
  ...
}

@override
void dispose() {
  _transcriber.dispose();
  ...
  super.dispose();
}
```

---

## `SherpaTranscriber` design

### Model download: atomic, verified

1. Check for completion marker file (`$docsDir/moonshine_small/.complete`).
2. If absent: download archive with `dio` (already a dep) → write to temp path →
   extract via `archive` package → verify all 5 expected files exist → write `.complete` →
   emit completion on `downloadProgress` stream.
3. If `.complete` present: skip download.
4. Load `OfflineRecognizer` from extracted files.
5. Set `isReady = true`.

**Failure handling:**
- Download error or extraction failure → delete partial temp dir → `isReady` stays false →
  caller sees `isReady == false` and falls back to `GeminiTranscriber` if key present, else
  shows "Voice unavailable" snackbar.
- Disk full: catch `FileSystemException`, clean up, report failure.

### Inference on background isolate

`recognizer.decode()` is synchronous CPU work. Run via `Isolate.run()`:

```dart
@override
Future<String?> transcribe(Uint8List pcm16Bytes) async {
  if (!isReady) return null;
  try {
    final float32 = pcm16ToFloat32(pcm16Bytes);
    // Run inference off the main isolate to avoid UI jank.
    // Note: OfflineRecognizer cannot be passed across isolate boundaries (native handle).
    // The recognizer must live on the isolate that does the work, OR use a dedicated
    // long-lived worker isolate. See task 4 notes.
    return await compute(_inferOnIsolate, _InferArgs(_modelDir, float32));
  } catch (_) {
    return null;
  }
}
```

**Isolate note:** Native handles (`OfflineRecognizer`) are not sendable across isolate boundaries.
Options: (a) create a new recognizer per `compute()` call — simple but adds load latency per
utterance; (b) long-lived worker isolate with message passing — better latency, more complexity.
Pick (a) for initial implementation and revisit if load latency is measurable.

### Download-progress UI edge cases

- Sheet closed mid-download: `dispose()` cancels progress subscription; download continues
  in background (acceptable — small file, completes quickly). Next sheet open finds `.complete`.
- User taps mic before `isReady`: mic button disabled (spinner shown), tap is no-op.
- No API key + `isReady == false`: mic button hidden entirely (same as today's behaviour when
  no key is set — voice is only shown when chat is available).

---

## `GeminiTranscriber` design

Extract `_transcribeAudio()` from `chat_sheet.dart` verbatim, adapted to accept raw PCM16:

```dart
class GeminiTranscriber implements VoiceTranscriber {
  GeminiTranscriber(this._ref);
  final WidgetRef _ref;

  @override Future<void> init() async {}         // no-op — always ready
  @override Stream<double>? get downloadProgress => null;
  @override bool get isReady => true;
  @override void dispose() {}

  @override
  Future<String?> transcribe(Uint8List pcm16Bytes) async {
    final wavBytes = _buildWav(pcm16Bytes);      // converts PCM → WAV internally
    // ... existing Gemini call ...
  }
}
```

`_buildWav` moves here (or to a shared utility) since only `GeminiTranscriber` needs it.

---

## `pubspec.yaml` changes

```yaml
# Add:
sherpa_onnx: ^1.12.0
path_provider: ^2.1.0
archive: ^3.6.1          # for tar.bz2 extraction

# Use existing dio for download — do NOT add http package.
# google_generative_ai stays — used for chat, not just STT.
```

---

## Implementation tasks

### Task 1 — Startup wiring + packages
- Add `sherpa_onnx`, `path_provider`, `archive` to `pubspec.yaml`; `flutter pub get`
- Add `initBindings()` call in `main.dart` (guarded by `!kIsWeb`)
- `flutter analyze` clean

### Task 2 — `VoiceTranscriber` interface
- Create `lib/features/chat/voice_transcriber.dart`
- Interface: `init()`, `transcribe(Uint8List pcm16Bytes)`, `downloadProgress`, `isReady`, `dispose()`

### Task 3 — `GeminiTranscriber`
- Create `lib/features/chat/gemini_transcriber.dart`
- Extract `_transcribeAudio()` logic; move `_buildWav()` here (or to `chat_utils.dart`)
- `init()` no-op, `isReady` always true, `dispose()` no-op

### Task 4 — `SherpaTranscriber` + web stub
- Verify exact sherpa-onnx model archive URL and filename for Moonshine; confirm the 5 config
  field → filename mapping against `OfflineMoonshineModelConfig` on pub.dev
- Create `lib/features/chat/sherpa_transcriber_stub.dart` (no sherpa imports, throws on `init()`)
- Create `lib/features/chat/sherpa_transcriber.dart`:
  - `init()`: atomic download (dio) → extract (archive) → verify files → `.complete` marker
  - `transcribe()`: `pcm16ToFloat32()` → `compute(_inferOnIsolate, ...)` (new recognizer per call)
  - `dispose()`: cancel stream, free recognizer if loaded
- All error paths: download fail → `isReady = false`; inference throw → return null

### Task 5 — `chat_sheet.dart` wiring
- Conditional import: `sherpa_transcriber_stub.dart` / `sherpa_transcriber.dart`
- `late VoiceTranscriber _transcriber`; construct via `kIsWeb` in `initState`
- `await _transcriber.init()` → `setState` when ready
- Subscribe to `downloadProgress` → drive `_downloadProgress` state for UI
- Replace `_transcribeAudio(wav)` call with `_transcriber.transcribe(rawPcm16)`
- Pass raw `_audioChunks` bytes (not WAV) to `transcribe()`
- Mic button: spinner + no-op when `!_transcriber.isReady`
- `dispose()`: `_transcriber.dispose()`

### Task 6 — Tests
- `sherpa_transcriber_test.dart`: mock `dio` download + `archive` extraction; mock
  `OfflineRecognizer`; verify init → ready transition; verify download-failure → isReady false;
  verify transcribe returns null on error
- `gemini_transcriber_test.dart`: verify WAV is built and passed correctly; no behaviour
  change vs current code

### Task 7 — Device validation (measure, don't assume)
- Build community APK and install on a low-end Android target (not just the development device)
- Measure peak RSS during recognizer load (confirm no OOM risk)
- Measure end-to-end latency: mic release → text in input field (target: <400ms)
- Compare against current Gemini path on same device
- If RAM is tight: evaluate switching to `tiny` variant instead of `small`
- If per-call recognizer-create latency is noticeable: implement long-lived worker isolate

---

## Review findings addressed

| Finding | Severity | Resolution |
|---|---|---|
| `decode(wavBytes)` API fabricated | Critical | Rewritten with correct sherpa-onnx API |
| Input must be Float32List not WAV | Critical | Interface takes PCM16; each backend converts |
| `initBindings()` missing | Critical | Task 1 adds it to `main.dart` |
| `kIsWeb` runtime switch breaks web build | Critical | Conditional import in Task 4/5 |
| `archive` dep missing | Important | Added to pubspec changes |
| No `dispose()`/`init()` on interface | Important | Both added to `VoiceTranscriber` |
| `decode()` blocks main isolate | Important | `compute()` / background isolate in Task 4 |
| Download integrity / atomicity | Important | Temp dir + file verification + `.complete` marker |
| Model slug / config field names unverified | Minor | Verify step in Task 4 |
| RAM / latency claims unverified | Minor | Task 7 measures on low-end device |
| Download UI edge cases | Minor | Defined in SherpaTranscriber design section |
