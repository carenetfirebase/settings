/// Wire-stable enumerations.
///
/// Every value carries an explicit [wire] string. Firestore documents store the
/// wire value, never the Dart index, so reordering a declaration can never
/// silently rewrite stored data.
library;

/// Dental specialty a referral is directed to.
enum Specialty {
  endodontics('endodontics', 'Endodontics', 'ENDO'),
  periodontics('periodontics', 'Periodontics', 'PERIO'),
  oralSurgery('oral_surgery', 'Oral Surgery', 'OS'),
  orthodontics('orthodontics', 'Orthodontics', 'ORTHO'),
  prosthodontics('prosthodontics', 'Prosthodontics', 'PROSTHO'),
  pediatricDentistry('pediatric_dentistry', 'Pediatric Dentistry', 'PEDO'),
  oralMedicine('oral_medicine', 'Oral Medicine / Oral Pathology', 'ORAL MED'),
  other('other', 'Other', 'OTHER');

  const Specialty(this.wire, this.displayName, this.shortName);

  final String wire;
  final String displayName;

  /// Compact label for the confirmation card and inbox rows.
  final String shortName;

  static Specialty? fromWire(String? value) {
    if (value == null) return null;
    for (final s in Specialty.values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

/// How soon the professional wants the patient seen.
///
/// [unspecified] is a real value, not a missing one. Nothing in this package
/// ever promotes it to [routine]: an urgency the professional did not state is
/// not an urgency of routine.
enum Urgency {
  unspecified('unspecified', 'Not specified'),
  routine('routine', 'Routine'),
  soon('soon', 'Soon'),
  urgent('urgent', 'Urgent');

  const Urgency(this.wire, this.displayName);

  final String wire;
  final String displayName;

  static Urgency fromWire(String? value) {
    for (final u in Urgency.values) {
      if (u.wire == value) return u;
    }
    return Urgency.unspecified;
  }
}

/// Lifecycle of a draft. Deliberately contains no value implying the referral
/// was transmitted, because this application does not transmit referrals.
enum ReferralStatus {
  needsCompletion('needs_completion', 'Needs completion'),
  completed('completed', 'Completed'),
  dismissed('dismissed', 'Dismissed'),
  expired('expired', 'Expired');

  const ReferralStatus(this.wire, this.displayName);

  final String wire;
  final String displayName;

  static ReferralStatus fromWire(String? value) {
    for (final s in ReferralStatus.values) {
      if (s.wire == value) return s;
    }
    return ReferralStatus.needsCompletion;
  }
}

/// Whether the local record has reached the backend yet.
enum SyncState {
  pending('pending'),
  synced('synced'),
  failed('failed');

  const SyncState(this.wire);

  final String wire;

  static SyncState fromWire(String? value) {
    for (final s in SyncState.values) {
      if (s.wire == value) return s;
    }
    return SyncState.pending;
  }
}

/// Tooth numbering system the professional works in.
enum ToothNotation {
  fdi('fdi', 'FDI'),
  universal('universal', 'Universal'),
  palmer('palmer', 'Palmer');

  const ToothNotation(this.wire, this.displayName);

  final String wire;
  final String displayName;

  static ToothNotation fromWire(String? value) {
    for (final n in ToothNotation.values) {
      if (n.wire == value) return n;
    }
    return ToothNotation.fdi;
  }
}

/// Records the office should attach later. This package stores the request
/// only; it never stores, transmits or references the record itself.
enum RecordType {
  periapical('pa', 'PA'),
  bitewing('bw', 'BW'),
  panoramic('pan', 'PAN'),
  cbct('cbct', 'CBCT'),
  photographs('photographs', 'Photographs'),
  periodontalChart('periodontal_chart', 'Periodontal chart');

  const RecordType(this.wire, this.displayName);

  final String wire;
  final String displayName;

  static RecordType? fromWire(String? value) {
    for (final r in RecordType.values) {
      if (r.wire == value) return r;
    }
    return null;
  }
}

/// Fields a template may mark required or optional.
enum ReferralField {
  specialty('specialty'),
  location('location'),
  reason('reason'),
  finding('finding'),
  symptom('symptom'),
  urgency('urgency'),
  destination('destination'),
  records('records');

  const ReferralField(this.wire);

  final String wire;
}
