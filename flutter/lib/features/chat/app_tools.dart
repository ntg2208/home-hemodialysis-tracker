import 'command_dispatch.dart';

/// Transport-agnostic description of one app *command* tool. Consumed by both
/// the in-app Gemini function-calling path and the embedded MCP server, so it
/// must stay free of any MCP-, Gemini-, or HTTP-specific types — only the tool
/// name, description, and JSON-schema, plus the pure arg→[AppCommand] parse.
///
/// Retriever tools (get_blood_markers/get_sessions/get_out_of_range_markers)
/// are NOT here — they return data, not commands, and live in gemini_client.
class AppToolSpec {
  const AppToolSpec({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;

  /// JSON Schema object: { 'type': 'object', 'properties': {...}, ['required': [...]] }
  final Map<String, dynamic> inputSchema;
}

/// The seven command tools, schemas copied verbatim from gemini_client's
/// `_oaiTools` (the source of truth — keep byte-identical).
const List<AppToolSpec> appToolSpecs = [
  AppToolSpec(
    name: 'navigate_to',
    description: 'Navigate to a main screen.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'route': {
          'type': 'string',
          'description':
              'One of: /treatment, /blood-tests, /inventory, /fitness, /kb',
        },
      },
      'required': ['route'],
    },
  ),
  AppToolSpec(
    name: 'filter_blood_tests',
    description:
        'Navigate to blood tests and apply a filter. All parameters are optional.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'marker': {
          'type': 'string',
          'description':
              'Canonical marker name, e.g. haemoglobin, ferritin, potassium',
        },
        'phase': {
          'type': 'string',
          'description': 'home-hd, in-center-hd, or admission',
        },
        'months': {
          'type': 'integer',
          'description': 'Number of months back from today',
        },
        'tab': {'type': 'string', 'description': 'scorecard or trend'},
      },
    },
  ),
  AppToolSpec(
    name: 'filter_fitness',
    description: 'Navigate to fitness and filter by type and/or time window.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'type': {
          'type': 'string',
          'description': 'steps, sleep, heart-rate, or hrv',
        },
        'days': {
          'type': 'integer',
          'description': 'Number of days back from today',
        },
      },
    },
  ),
  AppToolSpec(
    name: 'prefill_pre_treatment',
    description:
        'Pre-fill the pre-treatment form and open it. Only valid when no session is active.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'weight': {'type': 'number', 'description': 'Pre-treatment weight in kg'},
        'bp_sys': {'type': 'integer', 'description': 'Systolic BP'},
        'bp_dia': {'type': 'integer', 'description': 'Diastolic BP'},
        'pulse': {'type': 'integer', 'description': 'Pulse rate'},
        'uf_goal': {'type': 'number', 'description': 'UF goal in litres'},
        'uf_rate': {'type': 'number', 'description': 'UF rate in mL/h'},
      },
    },
  ),
  AppToolSpec(
    name: 'prefill_reading',
    description:
        'Pre-fill the Add Reading form. Only valid when a session is active.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'bp_sys': {'type': 'integer'},
        'bp_dia': {'type': 'integer'},
        'pulse': {'type': 'integer'},
        'blood_flow': {
          'type': 'integer',
          'description': 'Blood flow in mL/min',
        },
        'vp': {'type': 'integer', 'description': 'Venous pressure'},
        'ap': {'type': 'integer', 'description': 'Arterial pressure'},
      },
    },
  ),
  AppToolSpec(
    name: 'prefill_post_treatment',
    description:
        'Pre-fill the post-treatment form. Only valid when the session has been ended.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'weight': {
          'type': 'number',
          'description': 'Post-treatment weight in kg',
        },
        'bp_sys': {'type': 'integer'},
        'bp_dia': {'type': 'integer'},
        'pulse': {'type': 'integer'},
        'total_uf': {
          'type': 'number',
          'description': 'Total UF removed in litres',
        },
      },
    },
  ),
  AppToolSpec(
    name: 'end_session',
    description:
        'End the active dialysis session and open the post-treatment form. '
        'Optionally pre-fill post-treatment fields in the same call. '
        'Only valid when a session is active (treatment state = ACTIVE).',
    inputSchema: {
      'type': 'object',
      'properties': {
        'weight': {
          'type': 'number',
          'description': 'Post-treatment weight in kg',
        },
        'bp_sys': {
          'type': 'integer',
          'description': 'Post-treatment systolic BP',
        },
        'bp_dia': {
          'type': 'integer',
          'description': 'Post-treatment diastolic BP',
        },
        'pulse': {
          'type': 'integer',
          'description': 'Post-treatment pulse rate',
        },
        'total_uf': {
          'type': 'number',
          'description': 'Total UF removed in litres',
        },
      },
    },
  ),
];

/// Maps a command tool call to an [AppCommand]. Returns null for an unknown
/// tool (including retriever tools, which are handled separately). Moved
/// verbatim from gemini_client's `_parseCommand`.
AppCommand? parseAppCommand(String name, Map<String, dynamic> a) =>
    switch (name) {
      'navigate_to' => NavigateTo(a['route'] as String? ?? '/treatment'),
      'filter_blood_tests' => FilterBloodTests(
          marker: a['marker'] as String?,
          phase: a['phase'] as String?,
          months: (a['months'] as num?)?.toInt(),
          tab: a['tab'] as String?,
        ),
      'filter_fitness' => FilterFitness(
          type: a['type'] as String?,
          days: (a['days'] as num?)?.toInt(),
        ),
      'prefill_pre_treatment' => PrefillPreTreatment(
          weight: (a['weight'] as num?)?.toDouble(),
          bpSys: (a['bp_sys'] as num?)?.toInt(),
          bpDia: (a['bp_dia'] as num?)?.toInt(),
          pulse: (a['pulse'] as num?)?.toInt(),
          ufGoal: (a['uf_goal'] as num?)?.toDouble(),
          ufRate: (a['uf_rate'] as num?)?.toDouble(),
        ),
      'prefill_reading' => PrefillReading(
          bpSys: (a['bp_sys'] as num?)?.toInt(),
          bpDia: (a['bp_dia'] as num?)?.toInt(),
          pulse: (a['pulse'] as num?)?.toInt(),
          bloodFlow: (a['blood_flow'] as num?)?.toInt(),
          vp: (a['vp'] as num?)?.toInt(),
          ap: (a['ap'] as num?)?.toInt(),
        ),
      'prefill_post_treatment' => PrefillPostTreatment(
          weight: (a['weight'] as num?)?.toDouble(),
          bpSys: (a['bp_sys'] as num?)?.toInt(),
          bpDia: (a['bp_dia'] as num?)?.toInt(),
          pulse: (a['pulse'] as num?)?.toInt(),
          totalUf: (a['total_uf'] as num?)?.toDouble(),
        ),
      'end_session' => EndSession(
          weight: (a['weight'] as num?)?.toDouble(),
          bpSys: (a['bp_sys'] as num?)?.toInt(),
          bpDia: (a['bp_dia'] as num?)?.toInt(),
          pulse: (a['pulse'] as num?)?.toInt(),
          totalUf: (a['total_uf'] as num?)?.toDouble(),
        ),
      _ => null,
    };
