import 'dart:math';

/// Injectable clock so timestamp behaviour is testable without waiting.
abstract class Clock {
  const Clock();

  /// Always UTC. Local rendering is a display concern and happens against the
  /// professional's configured timezone, never by storing local time.
  DateTime nowUtc();
}

class SystemClock extends Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// A clock that returns whatever it was told to.
class FixedClock extends Clock {
  FixedClock(this._now);

  DateTime _now;

  set now(DateTime value) => _now = value.toUtc();

  @override
  DateTime nowUtc() => _now.toUtc();
}

/// Short, human-transcribable referral codes.
///
/// The alphabet is Crockford base32, which omits I, L, O and U. That matters
/// because the code's job is to survive being read off a screen and typed into
/// a different system: 0/O and 1/I/L are the pairs humans confuse, and U is
/// omitted so the alphabet cannot spell unfortunate words.
///
/// The code carries no information. It is not derived from the professional,
/// the clinical content, the timestamp, or any counter — it is random, so it
/// is neither predictable nor sequential.
abstract final class ReferralCode {
  static const String alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const int defaultLength = 5;

  static final Random _secure = Random.secure();

  /// Generates a code of [length] characters.
  ///
  /// Uniqueness only has to hold within one clinic's live drafts, and 32^5 is
  /// about 33.5 million, so collisions are rare — but callers must still check
  /// and regenerate via [generateUnique] rather than assume.
  static String generate({int length = defaultLength, Random? random}) {
    final rng = random ?? _secure;
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(alphabet[rng.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  /// Generates a code that [isTaken] rejects no code for.
  ///
  /// Gives up after [maxAttempts] by widening the code rather than looping
  /// forever, so a saturated namespace degrades instead of hanging.
  static String generateUnique(
    bool Function(String code) isTaken, {
    int length = defaultLength,
    int maxAttempts = 8,
    Random? random,
  }) {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final code = generate(length: length, random: random);
      if (!isTaken(code)) return code;
    }
    for (var extra = 1; extra <= 4; extra++) {
      final code = generate(length: length + extra, random: random);
      if (!isTaken(code)) return code;
    }
    throw StateError('Could not generate an unused referral code.');
  }

  /// Normalises a code a human typed or wrote down.
  ///
  /// Case-insensitive, tolerant of spaces and hyphens, and maps the confusable
  /// letters onto their digits — so "ro k4p", "R0-K4P" and "r0k4p" all resolve
  /// to the same code.
  static String normalise(String input) {
    final buffer = StringBuffer();
    for (final rune in input.toUpperCase().runes) {
      final ch = String.fromCharCode(rune);
      switch (ch) {
        case ' ' || '-' || '_' || '.':
          continue;
        case 'I' || 'L':
          buffer.write('1');
        case 'O':
          buffer.write('0');
        default:
          if (alphabet.contains(ch)) buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  /// Whether [input] normalises to a well-formed code.
  static bool isWellFormed(String input, {int length = defaultLength}) {
    final n = normalise(input);
    return n.length >= length &&
        n.runes.every((r) {
          return alphabet.contains(String.fromCharCode(r));
        });
  }
}

/// RFC 4122 version 4 identifiers, generated on the client.
///
/// The draft's id is created at capture time, before any write, so that saving
/// is idempotent: a double tap, a retry and an offline replay all address the
/// same document rather than creating duplicates.
abstract final class Uuid {
  static final Random _secure = Random.secure();

  static String v4({Random? random}) {
    final rng = random ?? _secure;
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx

    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-'
        '${hex(8, 10)}-${hex(10, 16)}';
  }

  static final RegExp _pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  static bool isValid(String value) => _pattern.hasMatch(value.toLowerCase());
}
