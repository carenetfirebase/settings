import '../enums.dart';

/// The four quadrants, in the order FDI numbers them.
enum Quadrant {
  upperRight('UR', 'Upper right', 1, 5),
  upperLeft('UL', 'Upper left', 2, 6),
  lowerLeft('LL', 'Lower left', 3, 7),
  lowerRight('LR', 'Lower right', 4, 8);

  const Quadrant(
      this.wire, this.displayName, this.fdiPermanent, this.fdiPrimary);

  final String wire;
  final String displayName;

  /// FDI first digit for permanent dentition.
  final int fdiPermanent;

  /// FDI first digit for primary dentition.
  final int fdiPrimary;

  static Quadrant? fromWire(String? value) {
    for (final q in Quadrant.values) {
      if (q.wire == value) return q;
    }
    return null;
  }

  static Quadrant? fromFdiQuadrantDigit(int digit) {
    for (final q in Quadrant.values) {
      if (q.fdiPermanent == digit || q.fdiPrimary == digit) return q;
    }
    return null;
  }
}

/// Named areas a professional may refer instead of naming teeth.
enum OralRegion {
  upperAnterior('upper_anterior', 'Upper anterior'),
  lowerAnterior('lower_anterior', 'Lower anterior'),
  upperPosterior('upper_posterior', 'Upper posterior'),
  lowerPosterior('lower_posterior', 'Lower posterior'),
  anterior('anterior', 'Anterior'),
  posterior('posterior', 'Posterior');

  const OralRegion(this.wire, this.displayName);

  final String wire;
  final String displayName;

  static OralRegion? fromWire(String? value) {
    for (final r in OralRegion.values) {
      if (r.wire == value) return r;
    }
    return null;
  }
}

/// Why a tooth code failed validation, so the UI can say something useful
/// instead of "invalid".
enum ToothRejection {
  malformed,
  outOfRange,

  /// Syntactically fine, but not a tooth that exists in this notation — for
  /// example FDI 19, where quadrant 1 has no ninth tooth.
  noSuchTooth,
}

/// Result of checking one spoken or typed tooth code against one notation.
class ToothCheck {
  const ToothCheck.valid(this.canonicalFdi)
      : isValid = true,
        rejection = null;

  const ToothCheck.invalid(this.rejection)
      : isValid = false,
        canonicalFdi = null;

  final bool isValid;

  /// FDI is used as the internal canonical form because it is unambiguous and
  /// covers both dentitions in two characters. It is an internal key only —
  /// nothing is ever displayed in FDI unless the professional works in FDI.
  final String? canonicalFdi;

  final ToothRejection? rejection;
}

/// Validation and conversion across FDI, Universal and Palmer.
///
/// Conversion exists so a code can be *displayed* in another notation with the
/// notation named. Nothing in this package converts a professional's tooth
/// number into another system behind their back.
abstract final class ToothCodec {
  static const String _universalPrimaryLetters = 'ABCDEFGHIJKLMNOPQRST';

  /// Checks [raw] against [notation] and returns its canonical FDI form.
  static ToothCheck check(String raw, ToothNotation notation) {
    final code = raw.trim().toUpperCase();
    if (code.isEmpty) return const ToothCheck.invalid(ToothRejection.malformed);

    switch (notation) {
      case ToothNotation.fdi:
        return _checkFdi(code);
      case ToothNotation.universal:
        return _checkUniversal(code);
      case ToothNotation.palmer:
        return _checkPalmer(code);
    }
  }

  static ToothCheck _checkFdi(String code) {
    if (!RegExp(r'^\d{2}$').hasMatch(code)) {
      return const ToothCheck.invalid(ToothRejection.malformed);
    }
    final quadrant = int.parse(code[0]);
    final index = int.parse(code[1]);
    if (quadrant < 1 || quadrant > 8 || index < 1) {
      return const ToothCheck.invalid(ToothRejection.outOfRange);
    }
    // Permanent quadrants carry eight teeth; primary quadrants carry five.
    final maxIndex = quadrant <= 4 ? 8 : 5;
    if (index > maxIndex) {
      return const ToothCheck.invalid(ToothRejection.noSuchTooth);
    }
    return ToothCheck.valid(code);
  }

  static ToothCheck _checkUniversal(String code) {
    if (RegExp(r'^[A-T]$').hasMatch(code)) {
      final idx = _universalPrimaryLetters.indexOf(code);
      final quadrantDigit = 5 + (idx ~/ 5);
      final withinQuadrant = idx % 5;
      // A-E and K-O run distal-to-mesial; F-J and P-T run mesial-to-distal.
      final index = (quadrantDigit == 5 || quadrantDigit == 7)
          ? 5 - withinQuadrant
          : withinQuadrant + 1;
      return ToothCheck.valid('$quadrantDigit$index');
    }
    if (!RegExp(r'^\d{1,2}$').hasMatch(code)) {
      return const ToothCheck.invalid(ToothRejection.malformed);
    }
    final n = int.parse(code);
    if (n < 1 || n > 32) {
      return const ToothCheck.invalid(ToothRejection.outOfRange);
    }
    final (int quadrant, int index) = switch (n) {
      <= 8 => (1, 9 - n),
      <= 16 => (2, n - 8),
      <= 24 => (3, 25 - n),
      _ => (4, n - 24),
    };
    return ToothCheck.valid('$quadrant$index');
  }

  static ToothCheck _checkPalmer(String code) {
    final match = RegExp(r'^(UR|UL|LL|LR)([1-8]|[A-E])$').firstMatch(code);
    if (match == null) {
      return const ToothCheck.invalid(ToothRejection.malformed);
    }
    final quadrant = Quadrant.fromWire(match.group(1))!;
    final tail = match.group(2)!;
    if (RegExp(r'^[1-8]$').hasMatch(tail)) {
      return ToothCheck.valid('${quadrant.fdiPermanent}$tail');
    }
    final index = 'ABCDE'.indexOf(tail) + 1;
    return ToothCheck.valid('${quadrant.fdiPrimary}$index');
  }

  /// Renders a canonical FDI code in [notation]. Returns null when the tooth
  /// has no representation there.
  static String? render(String canonicalFdi, ToothNotation notation) {
    final check = _checkFdi(canonicalFdi);
    if (!check.isValid) return null;
    final quadrant = int.parse(canonicalFdi[0]);
    final index = int.parse(canonicalFdi[1]);

    switch (notation) {
      case ToothNotation.fdi:
        return canonicalFdi;

      case ToothNotation.universal:
        if (quadrant <= 4) {
          final n = switch (quadrant) {
            1 => 9 - index,
            2 => 8 + index,
            3 => 25 - index,
            _ => 24 + index,
          };
          return '$n';
        }
        final base = (quadrant - 5) * 5;
        final offset = (quadrant == 5 || quadrant == 7) ? 5 - index : index - 1;
        return _universalPrimaryLetters[base + offset];

      case ToothNotation.palmer:
        final q = Quadrant.fromFdiQuadrantDigit(quadrant);
        if (q == null) return null;
        final tail = quadrant <= 4 ? '$index' : 'ABCDE'[index - 1];
        return '${q.wire}$tail';
    }
  }

  /// Every notation in which [raw] is a real tooth.
  static List<ToothNotation> notationsAccepting(String raw) => [
        for (final n in ToothNotation.values)
          if (check(raw, n).isValid) n,
      ];
}

/// What the extractor concluded about one spoken tooth code.
class ToothInterpretation {
  const ToothInterpretation({
    required this.raw,
    required this.configured,
    required this.validInConfigured,
    required this.canonicalFdi,
    required this.alsoValidIn,
  });

  final String raw;
  final ToothNotation configured;
  final bool validInConfigured;
  final String? canonicalFdi;

  /// Other notations in which this code is a real tooth. Populated whether or
  /// not the configured notation accepted it.
  final List<ToothNotation> alsoValidIn;

  /// True when the code is not a tooth in the professional's own notation but
  /// is one somewhere else — the case that must be asked about rather than
  /// silently rewritten.
  bool get isCrossNotationCandidate =>
      !validInConfigured && alsoValidIn.isNotEmpty;

  /// True when the code is not a tooth in any supported notation.
  bool get isUnknownEverywhere => !validInConfigured && alsoValidIn.isEmpty;

  static ToothInterpretation of(String raw, ToothNotation configured) {
    final own = ToothCodec.check(raw, configured);
    final others = [
      for (final n in ToothNotation.values)
        if (n != configured && ToothCodec.check(raw, n).isValid) n,
    ];
    return ToothInterpretation(
      raw: raw.trim().toUpperCase(),
      configured: configured,
      validInConfigured: own.isValid,
      canonicalFdi: own.canonicalFdi,
      alsoValidIn: others,
    );
  }
}
