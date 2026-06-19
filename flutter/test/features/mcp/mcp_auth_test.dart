import 'package:flutter_test/flutter_test.dart';
import 'package:home_hd/features/mcp/mcp_auth.dart';

void main() {
  test('generateMcpKey returns 64 hex chars', () {
    final k = generateMcpKey();
    expect(k.length, 64);
    expect(RegExp(r'^[0-9a-f]+$').hasMatch(k), isTrue);
    expect(generateMcpKey(), isNot(k)); // random each call
  });

  test('checkBearer accepts exact Bearer header, rejects others', () {
    expect(checkBearer('Bearer abc', 'abc'), isTrue);
    expect(checkBearer('Bearer xyz', 'abc'), isFalse);
    expect(checkBearer('abc', 'abc'), isFalse); // missing scheme
    expect(checkBearer(null, 'abc'), isFalse);
  });
}
