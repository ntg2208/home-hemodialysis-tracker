import '../../api/rest_client.dart';
import 'models.dart';

/// GET /api/blood-tests with optional from/to. Port of BloodTests/api.ts.
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
}
