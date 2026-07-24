import 'package:flutter_test/flutter_test.dart';
import 'package:why_did_i_unlock/brand.dart';

void main() {
  test('Play title fits the 30-character Console limit', () {
    expect(playStoreTitle.length, lessThanOrEqualTo(30));
    expect(playStoreTitle, 'Beacon: Mindful Phone Use');
  });

  test('on-device display name is the short Beacon label', () {
    expect(appDisplayName, 'Beacon');
  });

  test('support email is wired (no TODO_CONTACT placeholder)', () {
    expect(feedbackEmail, 'hi@dineshkaliki.com');
    expect(feedbackEmail.contains('TODO_'), isFalse);
  });

  test('privacy URL is the live Beacon policy page', () {
    expect(privacyPolicyUrl, 'https://dineshkaliki.com/beacon/privacy/');
  });

  test('Play listing URL stays grep-able until the Console listing exists', () {
    expect(playListingUrl, contains('TODO_PLAY_LISTING_URL_UNRESOLVED'));
  });
}
