/// Kinds of likely patient-identifying content the guardrail looks for.
///
/// The category is safe to count and report. The text that matched is not, and
/// this library never returns, stores or logs it.
enum IdentifierCategory {
  emailAddress('email_address'),
  phoneNumber('phone_number'),
  dateOfBirth('date_of_birth'),
  streetAddress('street_address'),
  identifierNumber('identifier_number'),
  personalName('personal_name'),
  healthOrInsuranceNumber('health_or_insurance_number');

  const IdentifierCategory(this.wire);

  final String wire;
}

/// Outcome of screening a transcript.
class GuardrailResult {
  const GuardrailResult(this.categories);

  const GuardrailResult.clean() : categories = const {};

  /// Which kinds of identifier were suspected. Never the matched text.
  final Set<IdentifierCategory> categories;

  bool get tripped => categories.isNotEmpty;
}

/// Screens a transcript for obvious patient identifiers before anything is
/// extracted from it.
///
/// This runs first and its verdict is absolute: a tripped transcript is
/// discarded whole, never partially salvaged, because salvaging would mean
/// parsing text that was already judged unsafe.
///
/// It detects patterned identifiers. It cannot detect a bare name — "the
/// patient Sarah has pain" reads to any pattern matcher exactly like ordinary
/// clinical speech. Treat this as a safety net under a UI that keeps asking
/// for no identifying information, never as a filter that makes it safe to
/// say one.
abstract final class IdentifierGuardrail {
  static final RegExp _email = RegExp(
    r'[a-z0-9._%+-]+\s*(@|\bat\b)\s*[a-z0-9.-]+\s*\.\s*[a-z]{2,}',
    caseSensitive: false,
  );

  // Ten-digit, seven-digit and parenthesised forms. Deliberately requires
  // enough digits that tooth numbers ("18 and 28") cannot reach it.
  static final RegExp _phone = RegExp(
    r'(\(\d{3}\)\s*\d{3}[-.\s]?\d{4})'
    r'|(\b\d{3}[-.\s]\d{3}[-.\s]\d{4}\b)'
    r'|(\b\d{10,11}\b)'
    r'|(\b\d{3}[-.\s]\d{4}\b)',
  );

  static final RegExp _birthWords = RegExp(
    r'\b(d\.?o\.?b\.?|date of birth|born on|born in|born|birthday|birthdate)\b',
    caseSensitive: false,
  );

  static final RegExp _monthDayYear = RegExp(
    r'\b(january|february|march|april|may|june|july|august|september|'
    r'october|november|december|jan|feb|mar|apr|jun|jul|aug|sept?|oct|nov|dec)'
    r'\.?\s+\d{1,2}(st|nd|rd|th)?,?\s+(19|20)\d{2}\b',
    caseSensitive: false,
  );

  static final RegExp _streetAddress = RegExp(
    r'\b\d{1,5}\s+([a-z]+\s+){0,2}'
    r'(street|avenue|road|drive|lane|boulevard|court|crescent|place|terrace|'
    r'way|st|ave|rd|blvd|ln|cres)\b',
    caseSensitive: false,
  );

  // Six or more consecutive digits: chart numbers, file numbers, account
  // numbers. No dental notation reaches six digits.
  static final RegExp _longDigitRun = RegExp(r'\b\d{6,}\b');

  // "Dr" is deliberately absent: a doctor's name is a referral destination,
  // which this product stores on purpose.
  static final RegExp _honorificName = RegExp(
    r'\b(mr|mrs|ms|miss|mister|missus)\b\.?\s+[a-z]{2,}',
    caseSensitive: false,
  );

  static final RegExp _nameIntroduction = RegExp(
    r"\b(patient'?s? name|first name|last name|surname|full name|name is)\b",
    caseSensitive: false,
  );

  static final RegExp _healthNumber = RegExp(
    r'\b(health card|healthcard|health number|insurance|policy number|'
    r'member (number|id)|chart (number|no)|file number|mrn|'
    r'medical record number|social insurance|social security|ssn|sin number)\b',
    caseSensitive: false,
  );

  /// Screens [transcript]. The input is not retained.
  static GuardrailResult screen(String transcript) {
    if (transcript.trim().isEmpty) return const GuardrailResult.clean();

    final found = <IdentifierCategory>{};

    if (_email.hasMatch(transcript)) {
      found.add(IdentifierCategory.emailAddress);
    }
    if (_phone.hasMatch(transcript)) {
      found.add(IdentifierCategory.phoneNumber);
    }
    if (_birthWords.hasMatch(transcript) ||
        _monthDayYear.hasMatch(transcript)) {
      found.add(IdentifierCategory.dateOfBirth);
    }
    if (_streetAddress.hasMatch(transcript)) {
      found.add(IdentifierCategory.streetAddress);
    }
    if (_healthNumber.hasMatch(transcript)) {
      found.add(IdentifierCategory.healthOrInsuranceNumber);
    }
    if (_longDigitRun.hasMatch(transcript)) {
      found.add(IdentifierCategory.identifierNumber);
    }
    if (_honorificName.hasMatch(transcript) ||
        _nameIntroduction.hasMatch(transcript)) {
      found.add(IdentifierCategory.personalName);
    }

    return GuardrailResult(found);
  }
}
