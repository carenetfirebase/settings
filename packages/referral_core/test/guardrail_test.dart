import 'package:referral_core/referral_core.dart';
import 'package:test/test.dart';

void main() {
  group('detects', () {
    void trips(String phrase, IdentifierCategory category) {
      test('$category in "$phrase"', () {
        final r = IdentifierGuardrail.screen(phrase);
        expect(r.tripped, isTrue);
        expect(r.categories, contains(category));
      });
    }

    trips('Endo 36, patient is Mr Smith', IdentifierCategory.personalName);
    trips('her name is Sarah, endo 36', IdentifierCategory.personalName);
    trips('endo 36, call 403-555-0199', IdentifierCategory.phoneNumber);
    trips('endo 36, 4035550199', IdentifierCategory.phoneNumber);
    trips('endo 36, email jane@example.com', IdentifierCategory.emailAddress);
    trips('endo 36, born May 2nd 1984', IdentifierCategory.dateOfBirth);
    trips('endo 36, DOB 1984', IdentifierCategory.dateOfBirth);
    trips(
        'endo 36, date of birth is next week', IdentifierCategory.dateOfBirth);
    trips('endo 36, 14 Riverside Drive', IdentifierCategory.streetAddress);
    trips('endo 36, chart number 88213',
        IdentifierCategory.healthOrInsuranceNumber);
    trips('endo 36, health card 9981234567',
        IdentifierCategory.healthOrInsuranceNumber);
    trips('endo 36, file 4471902', IdentifierCategory.identifierNumber);
  });

  group('does not trip on ordinary clinical speech', () {
    final clean = [
      'Endo, 36, necrotic.',
      'Endo, tooth 36, suspected necrosis with apical pathology, '
          'spontaneous pain, soon, usual endodontist, PA required.',
      'Oral surgery, 18 and 28, impacted thirds, panoramic.',
      'Perio, generalized bone loss.',
      'Endo, 46, cracked tooth, lingering cold and percussion sensitive.',
      'Perio, upper right, furcation involvement and mobility.',
      // A destination is a professional, and this product stores those.
      'Endo, 36, necrotic, refer to Dr Smith at Calgary Endodontics.',
      'Ortho, crowding, routine.',
      'Endo, op 3, tooth 36, necrotic.',
    ];
    for (final phrase in clean) {
      test('"$phrase"', () {
        expect(IdentifierGuardrail.screen(phrase).tripped, isFalse);
      });
    }
  });

  test('tooth numbers never look like a phone number', () {
    expect(
      IdentifierGuardrail.screen('Oral surgery, 18 and 28, impacted thirds')
          .tripped,
      isFalse,
    );
  });

  test('reports categories only, never the matched text', () {
    final r = IdentifierGuardrail.screen('endo 36, email jane@example.com');
    expect(r.categories, isNotEmpty);
    // The result type has no field that could carry the offending text.
    expect(r.categories.map((c) => c.wire).join(), isNot(contains('jane')));
  });

  test('an empty transcript is clean, not suspicious', () {
    expect(IdentifierGuardrail.screen('   ').tripped, isFalse);
  });
}
