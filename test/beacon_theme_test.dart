import 'package:flutter_test/flutter_test.dart';
import 'package:why_did_i_unlock/beacon_theme.dart';

void main() {
  test('Beacon amber is #FFB300', () {
    expect(BeaconColors.amber.toARGB32(), 0xFFFFB300);
  });

  test('glass fill is black at 60% opacity', () {
    expect(BeaconColors.glassFill.toARGB32(), 0x99000000);
  });

  test('dark theme primary is amber', () {
    final theme = beaconDarkTheme();
    expect(theme.colorScheme.primary, BeaconColors.amber);
    expect(theme.floatingActionButtonTheme.backgroundColor, BeaconColors.amber);
  });
}
