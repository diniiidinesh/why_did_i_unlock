import 'package:flutter_test/flutter_test.dart';
import 'package:why_did_i_unlock/oem_autostart_copy.dart';

void main() {
  group('matchOemGuidance', () {
    test('matches Xiaomi family', () {
      expect(matchOemGuidance('Xiaomi')?.vendor, contains('Xiaomi'));
      expect(matchOemGuidance('REDMI')?.vendor, contains('Xiaomi'));
      expect(matchOemGuidance('POCO')?.vendor, contains('Xiaomi'));
    });

    test('matches Oppo / Realme / OnePlus', () {
      expect(matchOemGuidance('oppo')?.vendor, contains('Oppo'));
      expect(matchOemGuidance('realme')?.vendor, contains('Oppo'));
      expect(matchOemGuidance('OnePlus')?.vendor, contains('Oppo'));
    });

    test('matches Vivo / iQOO', () {
      expect(matchOemGuidance('vivo')?.vendor, contains('Vivo'));
      expect(matchOemGuidance('iQOO')?.vendor, contains('Vivo'));
    });

    test('matches Samsung', () {
      expect(matchOemGuidance('samsung')?.vendor, contains('Samsung'));
    });

    test('returns null for Nothing / Google / empty', () {
      expect(matchOemGuidance('Nothing'), isNull);
      expect(matchOemGuidance('Google'), isNull);
      expect(matchOemGuidance(''), isNull);
      expect(matchOemGuidance(null), isNull);
      expect(matchOemGuidance('   '), isNull);
    });
  });

  group('oemGuidanceListPreferring', () {
    test('puts matched vendor first', () {
      final vivo = matchOemGuidance('vivo')!;
      final list = oemGuidanceListPreferring(vivo);
      expect(list.first.vendor, contains('Vivo'));
      expect(list.length, oemAutostartGuidance.length);
    });

    test('unchanged order when unmatched', () {
      final list = oemGuidanceListPreferring(null);
      expect(list.map((g) => g.vendor), oemAutostartGuidance.map((g) => g.vendor));
    });
  });

  test('overlayPermissionFindHint names the display brand', () {
    expect(overlayPermissionFindHint, contains('Beacon'));
  });

  test('oemGuidanceIntro stresses allow-background AND leave smart optimize', () {
    expect(oemGuidanceIntro, contains('smart'));
    expect(oemGuidanceIntro, contains('not enough'));
  });

  test('OnePlus / Oppo steps mention Don\'t optimize', () {
    final g = matchOemGuidance('oneplus')!;
    expect(g.steps.any((s) => s.contains('Don\'t optimize')), isTrue);
    expect(g.steps.any((s) => s.contains('Allow background')), isTrue);
  });

  test('Vivo steps match Background power control screenshots', () {
    final g = matchOemGuidance('vivo')!;
    expect(g.steps.any((s) => s.contains('Background power control')), isTrue);
    expect(g.steps.any((s) => s.contains('Allow background power usage')), isTrue);
    expect(g.steps.any((s) => s.contains('Background power smart control')), isTrue);
  });
}
