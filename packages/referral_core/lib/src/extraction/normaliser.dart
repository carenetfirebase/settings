/// Turns raw speech text into a stable form the matcher can work on.
///
/// Speech recognisers vary in how they render numbers ("thirty six", "36",
/// "3 6"), so this collapses those to digits before anything tries to read a
/// tooth number out of them.
abstract final class Normaliser {
  static const Map<String, int> _units = {
    'zero': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
  };

  static const Map<String, int> _tens = {
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  };

  /// Words that mean a tooth number is coming, so single digits after them can
  /// be joined: "tooth three six" is tooth 36, not teeth 3 and 6.
  static const Set<String> _toothCues = {'tooth', 'teeth', 'number'};

  /// Lower-cases, strips punctuation except the commas that separate segments,
  /// and converts spoken numbers to digits.
  static String normalise(String input) {
    final lowered = input.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lowered.runes) {
      final ch = String.fromCharCode(rune);
      if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
        buffer.write(ch);
      } else if (ch == ',') {
        buffer.write(' , ');
      } else {
        buffer.write(' ');
      }
    }

    final tokens = buffer
        .toString()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    final withDigits = _wordsToDigits(tokens);
    final joined = _joinToothDigits(withDigits);
    return joined.join(' ').replaceAll(RegExp(r'\s+,'), ' ,').trim();
  }

  /// Splits on the commas kept by [normalise].
  static List<String> segments(String normalised) => normalised
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  static List<String> _wordsToDigits(List<String> tokens) {
    final out = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final tens = _tens[token];
      if (tens != null) {
        // "twenty eight" -> 28, but a bare "twenty" stays 20.
        if (i + 1 < tokens.length) {
          final next = _units[tokens[i + 1]];
          if (next != null && next >= 1 && next <= 9) {
            out.add('${tens + next}');
            i++;
            continue;
          }
        }
        out.add('$tens');
        continue;
      }
      final unit = _units[token];
      out.add(unit != null ? '$unit' : token);
    }
    return out;
  }

  static List<String> _joinToothDigits(List<String> tokens) {
    final out = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      out.add(token);
      if (!_toothCues.contains(token)) continue;

      // Join a run of two single digits directly after a tooth cue.
      if (i + 2 < tokens.length &&
          _isSingleDigit(tokens[i + 1]) &&
          _isSingleDigit(tokens[i + 2])) {
        out.add('${tokens[i + 1]}${tokens[i + 2]}');
        i += 2;
      }
    }
    return out;
  }

  static bool _isSingleDigit(String token) =>
      token.length == 1 && RegExp(r'\d').hasMatch(token);
}
