import '../enums.dart';

/// One standardised clinical concept a professional can refer to.
///
/// [id] is the wire value stored on the draft. [synonyms] are the spoken forms
/// that map onto it — this is where dental shorthand is expanded, and it is the
/// only place that needs editing to teach the parser a new phrase.
class ClinicalConcept {
  const ClinicalConcept(this.id, this.display, this.synonyms);

  final String id;
  final String display;
  final List<String> synonyms;
}

/// A specialty's referral shape: what it needs, what it offers, and how it is
/// spoken about.
class ReferralTemplate {
  const ReferralTemplate({
    required this.specialty,
    required this.synonyms,
    required this.requiredFields,
    required this.reasons,
    this.findings = const [],
    this.symptoms = const [],
    this.recordOptions = const [],
    this.displayOrder = 0,
    this.isActive = true,
  });

  final Specialty specialty;

  /// Spoken forms that select this specialty.
  final List<String> synonyms;

  /// Fields the professional must supply before a draft can be saved.
  final Set<ReferralField> requiredFields;

  final List<ClinicalConcept> reasons;
  final List<ClinicalConcept> findings;
  final List<ClinicalConcept> symptoms;
  final List<RecordType> recordOptions;
  final int displayOrder;
  final bool isActive;

  String get displayName => specialty.displayName;
  String get shortName => specialty.shortName;

  ClinicalConcept? conceptById(String id) {
    for (final list in [reasons, findings, symptoms]) {
      for (final c in list) {
        if (c.id == id) return c;
      }
    }
    return null;
  }
}

/// Concepts shared across specialties, declared once.
const _apicalPathology = ClinicalConcept(
  'apical_pathology',
  'Apical pathology',
  [
    'apical radiolucency',
    'periapical radiolucency',
    'periapical lesion',
    'apical pathology',
    'apical rarefaction',
    'apical lesion',
    'parl',
  ],
);

const _trauma = ClinicalConcept('trauma', 'Trauma', [
  'traumatic injury',
  'avulsion',
  'luxation',
  'trauma',
]);

const _biopsy = ClinicalConcept('biopsy_assessment', 'Biopsy assessment', [
  'biopsy assessment',
  'biopsy',
]);

const _implantConsult =
    ClinicalConcept('implant_consultation', 'Implant consultation', [
  'implant consultation',
  'implant consult',
]);

/// The registry.
///
/// To add a specialty: add a [ReferralTemplate] here. To teach an existing
/// specialty a new phrase: add a synonym to the relevant [ClinicalConcept].
/// Neither requires a change anywhere else in the package.
abstract final class ReferralTemplates {
  static const List<ReferralTemplate> all = [
    _endodontics,
    _periodontics,
    _oralSurgery,
    _orthodontics,
    _prosthodontics,
    _pediatricDentistry,
    _oralMedicine,
    _other,
  ];

  static List<ReferralTemplate> get active =>
      all.where((t) => t.isActive).toList()
        ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

  static ReferralTemplate? forSpecialty(Specialty specialty) {
    for (final t in all) {
      if (t.specialty == specialty) return t;
    }
    return null;
  }

  static const _endodontics = ReferralTemplate(
    specialty: Specialty.endodontics,
    displayOrder: 1,
    synonyms: [
      'endodontics',
      'endodontic',
      'endodontist',
      'root canal',
      'endo',
      'rct',
    ],
    requiredFields: {
      ReferralField.specialty,
      ReferralField.location,
      ReferralField.reason,
    },
    reasons: [
      ClinicalConcept(
        'suspected_pulp_necrosis',
        'Suspected pulp necrosis',
        [
          'suspected pulp necrosis',
          'suspected necrosis',
          'pulp necrosis',
          'necrotic pulp',
          'non vital',
          'nonvital',
          'necrosis',
          'necrotic',
        ],
      ),
      ClinicalConcept('irreversible_pulpitis', 'Irreversible pulpitis', [
        'irreversible pulpitis',
      ]),
      ClinicalConcept('pulpitis', 'Pulpitis', ['pulpitis']),
      ClinicalConcept('retreatment', 'Retreatment', [
        'failed root canal',
        'retreatment',
        'failed rct',
        'retreat',
      ]),
      ClinicalConcept('cracked_tooth', 'Cracked tooth', [
        'cracked tooth',
        'crown fracture',
        'fractured',
        'fracture',
        'cracked',
        'crack',
      ]),
      ClinicalConcept('resorption', 'Resorption', [
        'internal resorption',
        'external resorption',
        'resorptive',
        'resorption',
      ]),
      _trauma,
      ClinicalConcept('rct_evaluation', 'RCT evaluation', [
        'root canal evaluation',
        'assessment for rct',
        'endo evaluation',
        'rct evaluation',
      ]),
    ],
    findings: [
      _apicalPathology,
      ClinicalConcept('sinus_tract', 'Sinus tract', [
        'draining tract',
        'sinus tract',
        'parulis',
        'fistula',
      ]),
      ClinicalConcept('swelling', 'Swelling', [
        'buccal swelling',
        'swelling',
        'swollen',
      ]),
      ClinicalConcept('non_responsive_to_cold', 'Non-responsive to cold', [
        'does not respond to cold',
        'no response to cold',
        'non responsive to cold',
        'negative to cold',
      ]),
    ],
    symptoms: [
      ClinicalConcept('spontaneous_pain', 'Spontaneous pain', [
        'unprovoked pain',
        'spontaneous pain',
        'spontaneous',
      ]),
      ClinicalConcept('lingering_cold', 'Lingering cold', [
        'lingering to cold',
        'prolonged cold',
        'lingering cold',
        'cold lingers',
      ]),
      ClinicalConcept('heat_sensitivity', 'Heat sensitivity', [
        'sensitive to heat',
        'heat sensitivity',
        'hot sensitivity',
      ]),
      ClinicalConcept('percussion_sensitivity', 'Percussion sensitivity', [
        'tender to percussion',
        'percussion sensitive',
        'percussion sensitivity',
        'sensitive to percussion',
        'percussion',
      ]),
      ClinicalConcept('palpation_sensitivity', 'Palpation sensitivity', [
        'tender to palpation',
        'palpation sensitive',
        'palpation sensitivity',
        'palpation',
      ]),
    ],
    recordOptions: [
      RecordType.periapical,
      RecordType.bitewing,
      RecordType.cbct,
      RecordType.photographs,
    ],
  );

  static const _periodontics = ReferralTemplate(
    specialty: Specialty.periodontics,
    displayOrder: 2,
    synonyms: [
      'periodontics',
      'periodontal',
      'periodontist',
      'perio',
    ],
    requiredFields: {
      ReferralField.specialty,
      ReferralField.location,
      ReferralField.reason,
    },
    reasons: [
      ClinicalConcept('bone_loss', 'Bone loss', [
        'periodontal bone loss',
        'alveolar bone loss',
        'bone loss',
        'boneloss',
      ]),
      ClinicalConcept('periodontal_assessment', 'Periodontal assessment', [
        'periodontal assessment',
        'periodontal evaluation',
        'perio assessment',
        'routine assessment',
      ]),
      ClinicalConcept('mucogingival_concern', 'Mucogingival concern', [
        'mucogingival concern',
        'mucogingival',
        'gingival graft',
        'gum graft',
      ]),
      ClinicalConcept('implant_assessment', 'Implant assessment', [
        'implant assessment',
        'implant evaluation',
      ]),
      ClinicalConcept('peri_implant_concern', 'Peri-implant concern', [
        // Matching runs on normalised text, so a hyphen here would make the
        // phrase unreachable. The spaced and joined forms cover what a
        // recogniser actually emits.
        'peri implantitis',
        'periimplantitis',
        'peri implant',
      ]),
      ClinicalConcept('crown_lengthening', 'Crown lengthening', [
        'crown lengthening',
      ]),
      // Recession, mobility and furcation are reasons a professional refers,
      // not merely observations about a case already being referred.
      ClinicalConcept('recession', 'Recession', [
        'gingival recession',
        'severe recession',
        'recession',
      ]),
      ClinicalConcept('mobility', 'Mobility', [
        'loose teeth',
        'loose tooth',
        'mobility',
        'mobile',
      ]),
      ClinicalConcept('furcation_involvement', 'Furcation involvement', [
        'furcation involvement',
        'furcation',
      ]),
    ],
    findings: [
      ClinicalConcept('bleeding_on_probing', 'Bleeding on probing', [
        'bleeding on probing',
        'bop',
      ]),
      ClinicalConcept('deep_pocketing', 'Deep pocketing', [
        'deep pocketing',
        'deep pockets',
        'pocketing',
      ]),
    ],
    recordOptions: [
      RecordType.periapical,
      RecordType.bitewing,
      RecordType.panoramic,
      RecordType.periodontalChart,
      RecordType.photographs,
      RecordType.cbct,
    ],
  );

  static const _oralSurgery = ReferralTemplate(
    specialty: Specialty.oralSurgery,
    displayOrder: 3,
    synonyms: [
      'oral and maxillofacial surgery',
      'maxillofacial',
      'oral surgery',
      'oral surgeon',
      'omfs',
      'oms',
      'os',
    ],
    requiredFields: {
      ReferralField.specialty,
      ReferralField.location,
      ReferralField.reason,
    },
    reasons: [
      ClinicalConcept('impacted_third_molars', 'Impacted third molars', [
        'impacted third molars',
        'impacted wisdom teeth',
        'impacted thirds',
        'wisdom teeth',
        'wisdom tooth',
        'third molars',
      ]),
      ClinicalConcept('extraction', 'Extraction', [
        'surgical extraction',
        'extraction',
        'extract',
        'removal',
        'exo',
      ]),
      ClinicalConcept('pathology_assessment', 'Pathology assessment', [
        'pathology assessment',
        'lesion assessment',
        'pathology',
      ]),
      _implantConsult,
      ClinicalConcept('exposure_and_bond', 'Exposure and bond', [
        'exposure and bond',
        'expose and bond',
      ]),
      _biopsy,
      _trauma,
    ],
    findings: [
      ClinicalConcept('impacted', 'Impacted', ['impacted', 'impaction']),
      ClinicalConcept('partially_erupted', 'Partially erupted', [
        'partially erupted',
        'partial eruption',
      ]),
    ],
    recordOptions: [
      RecordType.periapical,
      RecordType.panoramic,
      RecordType.cbct,
      RecordType.photographs,
    ],
  );

  static const _orthodontics = ReferralTemplate(
    specialty: Specialty.orthodontics,
    displayOrder: 4,
    synonyms: [
      'orthodontics',
      'orthodontic',
      'orthodontist',
      'ortho',
      'braces',
    ],
    requiredFields: {ReferralField.specialty, ReferralField.reason},
    reasons: [
      ClinicalConcept('orthodontic_assessment', 'Orthodontic assessment', [
        'orthodontic assessment',
        'ortho assessment',
        'ortho consult',
      ]),
      ClinicalConcept('crowding', 'Crowding', ['crowding', 'crowded']),
      ClinicalConcept('malocclusion', 'Malocclusion', [
        'malocclusion',
        'crossbite',
        'open bite',
        'deep bite',
        'overjet',
      ]),
      ClinicalConcept('space_management', 'Space management', [
        'space management',
        'space maintenance',
        'space closure',
      ]),
      ClinicalConcept('skeletal_discrepancy', 'Skeletal discrepancy', [
        'skeletal discrepancy',
        'skeletal',
      ]),
    ],
    recordOptions: [
      RecordType.panoramic,
      RecordType.photographs,
      RecordType.cbct,
    ],
  );

  static const _prosthodontics = ReferralTemplate(
    specialty: Specialty.prosthodontics,
    displayOrder: 5,
    synonyms: [
      'prosthodontics',
      'prosthodontic',
      'prosthodontist',
      'prostho',
    ],
    requiredFields: {ReferralField.specialty, ReferralField.reason},
    reasons: [
      ClinicalConcept('prosthodontic_assessment', 'Prosthodontic assessment', [
        'prosthodontic assessment',
        'prostho assessment',
      ]),
      ClinicalConcept(
        'full_mouth_rehabilitation',
        'Full-mouth rehabilitation',
        ['full mouth rehabilitation', 'full mouth rehab', 'rehabilitation'],
      ),
      ClinicalConcept('implant_restoration', 'Implant restoration', [
        'implant restoration',
        'implant crown',
      ]),
      ClinicalConcept('complex_crown_and_bridge', 'Complex crown and bridge', [
        'complex crown and bridge',
        'crown and bridge',
        'bridge',
      ]),
      ClinicalConcept('denture_assessment', 'Denture assessment', [
        'denture assessment',
        'complete denture',
        'partial denture',
        'denture',
      ]),
    ],
    recordOptions: [
      RecordType.periapical,
      RecordType.panoramic,
      RecordType.photographs,
      RecordType.cbct,
    ],
  );

  static const _pediatricDentistry = ReferralTemplate(
    specialty: Specialty.pediatricDentistry,
    displayOrder: 6,
    synonyms: [
      'pediatric dentistry',
      'paediatric dentistry',
      'pediatric dentist',
      'paediatric',
      'pediatric',
      'paedo',
      'pedo',
    ],
    requiredFields: {ReferralField.specialty, ReferralField.reason},
    reasons: [
      ClinicalConcept('pediatric_assessment', 'Pediatric assessment', [
        'pediatric assessment',
        'paediatric assessment',
      ]),
      ClinicalConcept('behaviour_management', 'Behaviour management', [
        'behaviour management',
        'behavior management',
        'uncooperative',
      ]),
      ClinicalConcept(
        'early_childhood_caries',
        'Early childhood caries',
        ['early childhood caries', 'nursing caries', 'ecc'],
      ),
      ClinicalConcept('space_maintenance', 'Space maintenance', [
        'space maintenance',
        'space maintainer',
      ]),
      _trauma,
    ],
    recordOptions: [
      RecordType.periapical,
      RecordType.bitewing,
      RecordType.panoramic,
      RecordType.photographs,
    ],
  );

  static const _oralMedicine = ReferralTemplate(
    specialty: Specialty.oralMedicine,
    displayOrder: 7,
    synonyms: [
      'oral medicine',
      'oral pathology',
      'oral path',
      'oral med',
    ],
    requiredFields: {ReferralField.specialty, ReferralField.reason},
    reasons: [
      ClinicalConcept('mucosal_lesion', 'Mucosal lesion', [
        'mucosal lesion',
        'white lesion',
        'ulcer',
        'lesion',
      ]),
      _biopsy,
      ClinicalConcept('orofacial_pain', 'Orofacial pain', [
        'orofacial pain',
        'facial pain',
        'burning mouth',
        'tmd',
      ]),
      ClinicalConcept('dry_mouth', 'Dry mouth', ['xerostomia', 'dry mouth']),
      ClinicalConcept('suspected_pathology', 'Suspected pathology', [
        'suspected pathology',
      ]),
    ],
    recordOptions: [
      RecordType.photographs,
      RecordType.panoramic,
      RecordType.cbct,
    ],
  );

  static const _other = ReferralTemplate(
    specialty: Specialty.other,
    displayOrder: 8,
    synonyms: ['other'],
    requiredFields: {ReferralField.specialty},
    reasons: [
      ClinicalConcept('general_assessment', 'General assessment', [
        'general assessment',
        'assessment',
      ]),
    ],
    recordOptions: [
      RecordType.periapical,
      RecordType.bitewing,
      RecordType.panoramic,
      RecordType.cbct,
      RecordType.photographs,
    ],
  );
}
