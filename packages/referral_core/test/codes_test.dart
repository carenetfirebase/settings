import 'dart:math';

import 'package:referral_core/referral_core.dart';
import 'package:test/test.dart';

void main() {
  group('referral code', () {
    test('omits the characters humans confuse when transcribing', () {
      for (final ch in ['I', 'L', 'O', 'U']) {
        expect(ReferralCode.alphabet, isNot(contains(ch)));
      }
      expect(ReferralCode.alphabet.length, 32);
    });

    test('is five characters from the alphabet', () {
      for (var i = 0; i < 500; i++) {
        final code = ReferralCode.generate();
        expect(code.length, 5);
        for (final rune in code.runes) {
          expect(ReferralCode.alphabet, contains(String.fromCharCode(rune)));
        }
      }
    });

    test('encodes nothing — the same inputs give different codes', () {
      final codes = {for (var i = 0; i < 2000; i++) ReferralCode.generate()};
      // Collisions are possible but a near-total set proves it is not derived
      // from anything about the caller.
      expect(codes.length, greaterThan(1900));
    });

    test('is not sequential', () {
      final a = ReferralCode.generate();
      final b = ReferralCode.generate();
      expect(a, isNot(b));
    });

    test('regenerates on collision', () {
      final taken = <String>{};
      // A rigged generator returns the same code until it is taken.
      var calls = 0;
      final rigged = _ScriptedRandom([
        ...List.filled(5, 1), // -> "11111"
        ...List.filled(5, 2), // -> "22222"
      ]);
      final first = ReferralCode.generateUnique(
        (c) {
          calls++;
          return taken.contains(c);
        },
        random: rigged,
      );
      taken.add(first);
      final second = ReferralCode.generateUnique(
        taken.contains,
        random: _ScriptedRandom([
          ...List.filled(5, 1),
          ...List.filled(5, 2),
        ]),
      );
      expect(second, isNot(first));
      expect(calls, greaterThan(0));
    });

    test('normalises a code a human wrote down', () {
      expect(ReferralCode.normalise('r0k4p'), 'R0K4P');
      expect(ReferralCode.normalise('RO K4P'), 'R0K4P');
      expect(ReferralCode.normalise('R0-K4P'), 'R0K4P');
      // I and L both read as 1.
      expect(ReferralCode.normalise('R1K4P'), 'R1K4P');
      expect(ReferralCode.normalise('RIK4P'), 'R1K4P');
      expect(ReferralCode.normalise('RLK4P'), 'R1K4P');
    });

    test('recognises a well-formed code', () {
      expect(ReferralCode.isWellFormed('R7K4P'), isTrue);
      expect(ReferralCode.isWellFormed('R7K4'), isFalse);
    });
  });

  group('uuid', () {
    test('is a valid v4', () {
      for (var i = 0; i < 200; i++) {
        expect(Uuid.isValid(Uuid.v4()), isTrue);
      }
    });

    test('is unique across many draws', () {
      final ids = {for (var i = 0; i < 5000; i++) Uuid.v4()};
      expect(ids.length, 5000);
    });
  });

  group('timestamps', () {
    test('render in the professional zone, not UTC', () {
      // 16:42 UTC is 10:42 in Mountain Daylight Time.
      final utc = DateTime.utc(2026, 9, 2, 16, 42);
      const mdt = Duration(hours: -6);
      expect(ReferralTime.formatTime(utc, mdt), '10:42 AM');
      expect(ReferralTime.formatDate(utc, mdt), 'September 2, 2026');
      expect(
        ReferralTime.formatStamp(utc, mdt),
        '10:42 AM · September 2, 2026',
      );
    });

    test('handles midnight and noon', () {
      const utc0 = Duration.zero;
      expect(
        ReferralTime.formatTime(DateTime.utc(2026, 1, 1, 0, 5), utc0),
        '12:05 AM',
      );
      expect(
        ReferralTime.formatTime(DateTime.utc(2026, 1, 1, 12, 0), utc0),
        '12:00 PM',
      );
    });

    test('an offset can move the local date across a day boundary', () {
      final utc = DateTime.utc(2026, 9, 3, 3, 30);
      const mdt = Duration(hours: -6);
      expect(ReferralTime.formatDate(utc, mdt), 'September 2, 2026');
      expect(ReferralTime.formatTime(utc, mdt), '9:30 PM');
    });

    test('the clock is injectable so timestamps are testable', () {
      final clock = FixedClock(DateTime.utc(2026, 9, 2, 16, 42));
      expect(clock.nowUtc(), DateTime.utc(2026, 9, 2, 16, 42));
      expect(clock.nowUtc().isUtc, isTrue);
    });
  });
}

/// Returns a scripted sequence, then falls back to a fixed value.
class _ScriptedRandom implements Random {
  _ScriptedRandom(this._script);

  final List<int> _script;
  int _index = 0;

  @override
  int nextInt(int max) {
    if (_index < _script.length) return _script[_index++] % max;
    return 3 % max;
  }

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.5;
}
