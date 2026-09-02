import 'package:referral_core/referral_core.dart';
import 'package:test/test.dart';

void main() {
  group('FDI', () {
    test('accepts a permanent tooth', () {
      final check = ToothCodec.check('36', ToothNotation.fdi);
      expect(check.isValid, isTrue);
      expect(check.canonicalFdi, '36');
    });

    test('accepts primary quadrants 5-8 with five teeth', () {
      expect(ToothCodec.check('55', ToothNotation.fdi).isValid, isTrue);
      expect(
        ToothCodec.check('56', ToothNotation.fdi).rejection,
        ToothRejection.noSuchTooth,
      );
    });

    test('rejects a ninth tooth in a permanent quadrant', () {
      final check = ToothCodec.check('19', ToothNotation.fdi);
      expect(check.isValid, isFalse);
      expect(check.rejection, ToothRejection.noSuchTooth);
    });

    test('rejects quadrant 9', () {
      expect(ToothCodec.check('91', ToothNotation.fdi).isValid, isFalse);
    });
  });

  group('Universal', () {
    test('accepts 1 to 32', () {
      expect(ToothCodec.check('1', ToothNotation.universal).isValid, isTrue);
      expect(ToothCodec.check('32', ToothNotation.universal).isValid, isTrue);
    });

    test('rejects 36 — out of range', () {
      final check = ToothCodec.check('36', ToothNotation.universal);
      expect(check.isValid, isFalse);
      expect(check.rejection, ToothRejection.outOfRange);
    });

    test('accepts primary letters', () {
      expect(ToothCodec.check('A', ToothNotation.universal).canonicalFdi, '55');
      expect(ToothCodec.check('E', ToothNotation.universal).canonicalFdi, '51');
      expect(ToothCodec.check('T', ToothNotation.universal).canonicalFdi, '85');
    });
  });

  group('Palmer', () {
    test('accepts quadrant plus tooth', () {
      expect(ToothCodec.check('LL6', ToothNotation.palmer).canonicalFdi, '36');
      expect(ToothCodec.check('UR1', ToothNotation.palmer).canonicalFdi, '11');
    });

    test('rejects a bare number', () {
      expect(ToothCodec.check('36', ToothNotation.palmer).isValid, isFalse);
    });
  });

  group('conversion', () {
    test('FDI 36 is Universal 19 and Palmer LL6', () {
      expect(ToothCodec.render('36', ToothNotation.universal), '19');
      expect(ToothCodec.render('36', ToothNotation.palmer), 'LL6');
    });

    test('round-trips every permanent tooth through Universal', () {
      for (final quadrant in [1, 2, 3, 4]) {
        for (var index = 1; index <= 8; index++) {
          final fdi = '$quadrant$index';
          final universal = ToothCodec.render(fdi, ToothNotation.universal)!;
          expect(
            ToothCodec.check(universal, ToothNotation.universal).canonicalFdi,
            fdi,
            reason: 'FDI $fdi -> Universal $universal -> back',
          );
        }
      }
    });

    test('round-trips every primary tooth through Universal', () {
      for (final quadrant in [5, 6, 7, 8]) {
        for (var index = 1; index <= 5; index++) {
          final fdi = '$quadrant$index';
          final universal = ToothCodec.render(fdi, ToothNotation.universal)!;
          expect(
            ToothCodec.check(universal, ToothNotation.universal).canonicalFdi,
            fdi,
          );
        }
      }
    });

    test('Universal maps the arches the way dentists number them', () {
      // 1 is the upper right third molar; 19 the lower left first molar.
      expect(ToothCodec.check('1', ToothNotation.universal).canonicalFdi, '18');
      expect(
          ToothCodec.check('19', ToothNotation.universal).canonicalFdi, '36');
      expect(
          ToothCodec.check('32', ToothNotation.universal).canonicalFdi, '48');
    });
  });

  group('cross-notation interpretation', () {
    test('36 under Universal is a candidate for asking, not translating', () {
      final i = ToothInterpretation.of('36', ToothNotation.universal);
      expect(i.validInConfigured, isFalse);
      expect(i.isCrossNotationCandidate, isTrue);
      expect(i.alsoValidIn, contains(ToothNotation.fdi));
      expect(i.canonicalFdi, isNull, reason: 'must not silently translate');
    });

    test('18 is a real tooth in both systems — the dangerous case', () {
      // FDI 18 is an upper right third molar; Universal 18 is a lower left
      // second molar. Nothing distinguishes them but the configured system.
      expect(ToothCodec.check('18', ToothNotation.fdi).canonicalFdi, '18');
      expect(
          ToothCodec.check('18', ToothNotation.universal).canonicalFdi, '37');

      final asFdi = ToothInterpretation.of('18', ToothNotation.fdi);
      expect(asFdi.validInConfigured, isTrue);
      expect(asFdi.isCrossNotationCandidate, isFalse,
          reason: 'valid in the professional own system, so no question');
    });

    test('99 is not a tooth anywhere', () {
      final i = ToothInterpretation.of('99', ToothNotation.fdi);
      expect(i.isUnknownEverywhere, isTrue);
    });
  });

  test('a tooth location always names its notation', () {
    final location = ReferralLocation.tooth(
      code: '36',
      notation: ToothNotation.fdi,
      canonicalFdi: '36',
    );
    expect(location.display(), '36 · FDI');
    expect(location.renderIn(ToothNotation.universal), '19');
  });
}
