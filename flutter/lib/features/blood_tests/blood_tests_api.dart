import '../../api/rest_client.dart';
import 'models.dart';

/// GET/POST /api/blood-tests. Port of BloodTests/api.ts.
class BloodTestsApi {
  BloodTestsApi(this._rest);
  final RestClient _rest;

  Future<List<BloodTestRow>> fetchRange({String? from, String? to}) async {
    final data = await _rest.get('/api/blood-tests', query: {
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
    });
    final rows = data['rows'];
    if (rows is! List) {
      throw CloudRunError(
          CloudErrorCode.badData, 'Response did not match the expected shape.');
    }
    return rows
        .map((e) => BloodTestRow.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// POST a single manually-entered row to Firestore via Cloud Run.
  Future<void> postRow(BloodTestRow row) async {
    await _rest.send('POST', '/api/blood-tests', body: {
      'rows': [row.toJson()],
    }, retry: false);
  }
}
