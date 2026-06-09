// Tests for GeminiChatResponder streaming and command dispatch behaviour.
// Uses GeminiChatResponder.forTest() + injected GeminiBackend to avoid
// Firebase/Hive dependencies.
import 'package:flutter_test/flutter_test.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:home_hd/features/chat/chat_controller.dart';
import 'package:home_hd/features/chat/command_dispatch.dart';
import 'package:home_hd/features/chat/gemini_client.dart';
import 'package:home_hd/features/chat/screen_context.dart';

// ---------------------------------------------------------------------------
// Helpers to construct SDK response objects in tests
// ---------------------------------------------------------------------------

GenerateContentResponse _textResponse(String text) {
  return GenerateContentResponse(
    [Candidate(Content('model', [TextPart(text)]), null, null, null, null)],
    null,
  );
}

GenerateContentResponse _toolResponse(String toolName, Map<String, Object?> args) {
  return GenerateContentResponse(
    [Candidate(Content('model', [FunctionCall(toolName, args)]), null, null, null, null)],
    null,
  );
}

GenerateContentResponse _emptyResponse() {
  return GenerateContentResponse([], null);
}

// ---------------------------------------------------------------------------
// Fake backend
// ---------------------------------------------------------------------------

class _FakeBackend implements GeminiBackend {
  /// [streamResponses]: responses emitted by [stream] in order.
  /// Convenience: pass [streamChunks] to get text-only stream responses.
  /// [generateResponses]: responses returned by successive [generate] calls.
  _FakeBackend({
    List<GenerateContentResponse>? streamResponses,
    List<String>? streamChunks,
    List<GenerateContentResponse>? generateResponses,
  })  : _streamResponses = streamResponses ??
            (streamChunks?.map(_textResponse).toList() ?? []),
        _generateResponses = generateResponses ?? [];

  final List<GenerateContentResponse> _streamResponses;
  final List<GenerateContentResponse> _generateResponses;
  int _generateCalls = 0;

  @override
  Stream<GenerateContentResponse> stream(Iterable<Content> contents) async* {
    for (final r in _streamResponses) {
      yield r;
    }
  }

  @override
  Future<GenerateContentResponse> generate(Iterable<Content> contents) async {
    if (_generateCalls < _generateResponses.length) {
      return _generateResponses[_generateCalls++];
    }
    return _emptyResponse();
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

GeminiChatResponder _makeResponder({
  required GeminiBackend backend,
  List<AppCommand>? dispatched,
  AppScreenContext screenContext = const AppScreenContext(),
}) {
  final commands = dispatched ?? [];
  return GeminiChatResponder.forTest(
    onCommand: commands.add,
    screenContext: screenContext,
    testBackend: backend,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('GeminiChatResponder streaming', () {
    test('pure-chat path emits chunks incrementally', () async {
      final backend = _FakeBackend(streamChunks: ['Hello ', 'world', '!']);
      final responder = _makeResponder(backend: backend);

      final chunks = <String>[];
      await for (final c in responder.reply('hi', [])) {
        chunks.add(c);
      }

      expect(chunks.length, 3,
          reason: 'Each chunk from the stream should be yielded separately');
      expect(chunks.join(), 'Hello world!');
    });

    test('pure-chat path with single chunk still emits it', () async {
      final backend = _FakeBackend(streamChunks: ['Answer']);
      final responder = _makeResponder(backend: backend);
      final chunks = await responder.reply('hi', []).toList();
      expect(chunks, ['Answer']);
    });

    test('empty stream response yields nothing', () async {
      final backend = _FakeBackend(streamChunks: []);
      final responder = _makeResponder(backend: backend);
      final chunks = await responder.reply('hi', []).toList();
      expect(chunks, isEmpty);
    });
  });

  group('GeminiChatResponder tool dispatch', () {
    test('tool call dispatches command and yields narration', () async {
      final dispatched = <AppCommand>[];
      final backend = _FakeBackend(
        // Tool call comes via stream on the first turn
        streamResponses: [
          _toolResponse('navigate_to', {'route': '/blood-tests'}),
        ],
        // Narration comes from the buffered generate() after tool processing
        generateResponses: [
          _textResponse('Navigated to Blood Tests.'),
        ],
      );
      final responder = _makeResponder(backend: backend, dispatched: dispatched);

      final chunks = await responder.reply('go to blood tests', []).toList();

      expect(dispatched, hasLength(1));
      expect(dispatched.first, isA<NavigateTo>());
      expect((dispatched.first as NavigateTo).route, '/blood-tests');
      expect(chunks.join(), contains('Navigated'));
    });

    test('tool call blocked by state machine returns error to model, no dispatch', () async {
      final dispatched = <AppCommand>[];
      // PrefillReading is invalid in idle state
      final backend = _FakeBackend(
        streamResponses: [
          _toolResponse('prefill_reading', {'bp_sys': 130}),
        ],
        generateResponses: [
          _textResponse('Cannot add a reading right now.'),
        ],
      );
      final responder = _makeResponder(
        backend: backend,
        dispatched: dispatched,
        screenContext: const AppScreenContext(treatmentState: TreatmentState.idle),
      );

      await responder.reply('add reading', []).toList();

      expect(dispatched, isEmpty, reason: 'Blocked command must not be dispatched');
    });

    test('tool call with out-of-range value blocks dispatch and returns error', () async {
      final dispatched = <AppCommand>[];
      final backend = _FakeBackend(
        streamResponses: [
          _toolResponse('prefill_pre_treatment', {'weight': 500.0, 'bp_sys': 140}),
        ],
        generateResponses: [
          _textResponse('Please confirm the weight value.'),
        ],
      );
      final responder = _makeResponder(
        backend: backend,
        dispatched: dispatched,
        screenContext: const AppScreenContext(treatmentState: TreatmentState.idle),
      );

      await responder.reply('start session weight 500', []).toList();

      expect(dispatched, isEmpty, reason: 'Out-of-range value must not be dispatched');
    });
  });

  group('GeminiChatResponder silent outcome', () {
    test('commands ran but model returns empty text yields fallback bubble', () async {
      final dispatched = <AppCommand>[];
      final backend = _FakeBackend(
        streamResponses: [
          _toolResponse('navigate_to', {'route': '/treatment'}),
        ],
        generateResponses: [
          _emptyResponse(), // model returns nothing after tool call
        ],
      );
      final responder = _makeResponder(backend: backend, dispatched: dispatched);

      final chunks = await responder.reply('go to treatment', []).toList();

      expect(dispatched, hasLength(1));
      expect(chunks, isNotEmpty,
          reason: 'A fallback bubble should be emitted when commands ran but model text is empty');
    });
  });
}
