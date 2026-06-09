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
