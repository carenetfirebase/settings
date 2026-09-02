/// Pure-Dart domain core for Quick Referral.
///
/// Contains no Flutter, no platform channels and no I/O, so it can be unit
/// tested without a device and reused by any surface that needs to capture a
/// referral — the phone app, and later a watch or a widget.
///
/// It stores no patient identity. See `ReferralDraft` for what that means and
/// what it does not claim.
library;

export 'src/ambiguity/ambiguity.dart';
export 'src/codes/codes.dart';
export 'src/draft_factory.dart';
export 'src/enums.dart';
export 'src/extraction/extractor.dart';
export 'src/extraction/normaliser.dart';
export 'src/extraction/parsed_result.dart';
export 'src/guardrail/guardrail.dart';
export 'src/handoff/handoff.dart';
export 'src/models/destination.dart';
export 'src/models/draft.dart';
export 'src/models/preferences.dart';
export 'src/referral_time.dart';
export 'src/repository.dart';
export 'src/templates/templates.dart';
export 'src/tooth/location.dart';
export 'src/tooth/tooth.dart';
