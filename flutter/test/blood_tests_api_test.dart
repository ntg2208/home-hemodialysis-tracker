import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/api/rest_client.dart';
import 'package:home_hd/features/blood_tests/blood_tests_api.dart';
import 'package:home_hd/features/blood_tests/models.dart';

BloodTestRow _row() => const BloodTestRow(
      marker: 'creatinine',
      datetime: '2026-06-13T09:00:00.000Z',
      value: 1073.0,
      unit: 'umol/L',
      refLow: 64.0,
      refHigh: 104.0,
      timing: 'pre',
      note: '',
      source: 'manual',
      labId: '',
      phase: '',
      createdAt: '2026-06-13',
      qualitative: false,
    );

/// Returns a [RestClient] whose HTTP layer is replaced by [onRequest].
/// The interceptor resolves with a 200 `{"inserted":1}` response so the
/// method under test doesn't throw.
RestClient _fakeClient({
  required void Function(RequestOptions) onRequest,
}) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      onRequest(options);
      handler.resolve(Response(
        data: <String, dynamic>{'inserted': 1},
        requestOptions: options,
        statusCode: 200,
      ));
    },
  ));
  return RestClient(mainKey: () => 'test-key', dio: dio);
}

void main() {
  test('postRow sends POST /api/blood-tests with a rows array', () async {
    RequestOptions? captured;
    final api = BloodTestsApi(_fakeClient(onRequest: (o) => captured = o));

    await api.postRow(_row());

    expect(captured, isNotNull);
    expect(captured!.method, 'POST');
    expect(captured!.path, '/api/blood-tests');
    final body = captured!.data as Map<String, dynamic>;
    expect(body['rows'], isList);
    expect((body['rows'] as List).length, 1);
    expect((body['rows'] as List<dynamic>).first['marker'], 'creatinine');
    expect((body['rows'] as List<dynamic>).first['timing'], 'pre');
  });

  test('postRow includes Authorization header', () async {
    RequestOptions? captured;
    final api = BloodTestsApi(_fakeClient(onRequest: (o) => captured = o));

    await api.postRow(_row());

    expect(captured!.headers['Authorization'], 'Bearer test-key');
  });
}
