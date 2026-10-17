import '../models/codec.dart';
import '../models/health.dart';
import '../models/nutrition.dart';

/// Curated evidence library.
///
/// Every statement here is an INTERNAL DRAFT until a registered dietitian
/// (and, for oral health, a dental professional) reviews it — see
/// docs/CLINICAL_SAFETY.md. AI features may rephrase these claims for
/// readability but may not invent new ones. Claims without a verified
/// citation carry no source and say so.
const evidenceSources = <String, EvidenceSource>{
  'hc_food_guide': EvidenceSource(
    id: 'hc_food_guide',
    title: 'Canada\'s Food Guide',
    publisher: 'Health Canada',
    studyType: StudyType.guideline,
    year: 2019,
    url: 'https://food-guide.canada.ca/en/',
  ),
  'hc_dri': EvidenceSource(
    id: 'hc_dri',
    title: 'Dietary Reference Intakes tables',
    publisher: 'Health Canada',
    studyType: StudyType.reference,
    year: 2010,
    url: 'https://www.canada.ca/en/health-canada/services/food-nutrition/healthy-eating/dietary-reference-intakes/tables.html',
  ),
  'who_sugars': EvidenceSource(
    id: 'who_sugars',
    title: 'Guideline: Sugars intake for adults and children',
    publisher: 'World Health Organization',
    studyType: StudyType.guideline,
    year: 2015,
    url: 'https://www.who.int/publications/i/item/9789241549028',
  ),
  'who_caries': EvidenceSource(
    id: 'who_caries',
    title: 'Sugars and dental caries (fact sheet)',
    publisher: 'World Health Organization',
    studyType: StudyType.reference,
    year: 2017,
    url: 'https://www.who.int/news-room/fact-sheets/detail/sugars-and-dental-caries',
  ),
  'ods_biotin': EvidenceSource(
    id: 'ods_biotin',
    title: 'Biotin — Fact Sheet for Health Professionals',
    publisher: 'NIH Office of Dietary Supplements',
    studyType: StudyType.reference,
    year: 2022,
    url: 'https://ods.od.nih.gov/factsheets/Biotin-HealthProfessional/',
  ),
  'ods_iron': EvidenceSource(
    id: 'ods_iron',
    title: 'Iron — Fact Sheet for Health Professionals',
    publisher: 'NIH Office of Dietary Supplements',
    studyType: StudyType.reference,
    year: 2024,
    url: 'https://ods.od.nih.gov/factsheets/Iron-HealthProfessional/',
  ),
};

const _draft = 'internal_draft';
const _reviewed = CalendarDate(2026, 10, 15);

const evidenceClaims = <EvidenceClaim>[
  EvidenceClaim(
    id: 'fibre_foods',
    topic: 'Fibre',
    statement: 'Most adults benefit from more fibre-rich foods — vegetables, fruit, whole grains, beans and lentils.',
    strength: EvidenceStrength.strong,
    sourceIds: ['hc_food_guide', 'hc_dri'],
    limitations: 'Population-level guidance. Some digestive conditions need individual advice; increase fibre gradually with fluids.',
    reviewedOn: _reviewed,
    reviewStatus: _draft,
    foodSources: ['lentils', 'black_beans', 'chickpeas', 'oats', 'chia', 'kale', 'broccoli'],
  ),
  EvidenceClaim(
    id: 'protein_variety',
    topic: 'Protein',
    statement: 'Including a protein food at meals — and choosing plant-based proteins more often — supports a balanced pattern of eating.',
    strength: EvidenceStrength.moderate,
    sourceIds: ['hc_food_guide'],
    limitations: 'Needs vary with age, body size, activity, pregnancy and health conditions.',
    reviewedOn: _reviewed,
    reviewStatus: _draft,
    foodSources: ['tofu', 'lentils', 'greek_yogurt', 'egg', 'salmon', 'chickpeas'],
  ),
  EvidenceClaim(
    id: 'sodium_cooking',
    topic: 'Sodium',
    statement: 'Cooking more meals at home and relying less on highly processed foods is one of the most practical ways to eat less sodium.',
    strength: EvidenceStrength.strong,
    sourceIds: ['hc_food_guide'],
    limitations: 'Sodium estimates depend on how much salt you actually add, which recipes can only approximate.',
    reviewedOn: _reviewed,
    reviewStatus: _draft,
  ),
  EvidenceClaim(
    id: 'free_sugars',
    topic: 'Sugars',
    statement: 'Keeping free sugars below 10% of daily energy is recommended; going below 5% may offer further benefits.',
    strength: EvidenceStrength.strong,
    sourceIds: ['who_sugars'],
    limitations: '"Free sugars" excludes sugars naturally in whole fruit, vegetables and milk. Chefii\'s "total sugars" estimate includes them, so it overstates free sugars.',
    reviewedOn: _reviewed,
    reviewStatus: _draft,
  ),
  EvidenceClaim(
    id: 'vegetables_variety',
    topic: 'Variety',
    statement: 'Filling half your plate with vegetables and fruit, in a variety of colours, is a simple way to eat well.',
    strength: EvidenceStrength.strong,
    sourceIds: ['hc_food_guide'],
    limitations: 'A visual guide, not a precise target.',
    reviewedOn: _reviewed,
    reviewStatus: _draft,
  ),
  EvidenceClaim(
    id: 'water_first',
    topic: 'Drinks',
    statement: 'Making water your drink of choice helps limit sugary drinks.',
    strength: EvidenceStrength.strong,
    sourceIds: ['hc_food_guide'],
    limitations: 'Fluid needs vary with climate, activity and health.',
    reviewedOn: _reviewed,
    reviewStatus: _draft,
  ),
  EvidenceClaim(
    id: 'sugar_frequency_teeth',
    topic: 'Teeth',
    statement: 'For tooth decay, how often you have sugary foods and drinks matters, as well as how much.',
    strength: EvidenceStrength.moderate,
    sourceIds: ['who_caries'],
    limitations: 'Fluoride, brushing, saliva and genetics also strongly affect decay risk. This is education, not a dental assessment.',
    reviewedOn: _reviewed,
    reviewStatus: _draft,
  ),
  EvidenceClaim(
    id: 'acid_sipping',
    topic: 'Teeth',
    statement: 'Sipping acidic drinks slowly over long periods keeps teeth exposed to acid for longer than having them with a meal.',
    strength: EvidenceStrength.limited,
    sourceIds: [],
    limitations: 'Citation pending dental professional review. Erosion risk also depends on saliva, reflux and brushing habits.',
    reviewedOn: _reviewed,
    reviewStatus: _draft,
  ),
  EvidenceClaim(
    id: 'biotin_hair',
    topic: 'Hair, skin & nails',
    statement: 'Biotin supplements are unlikely to improve hair or nails unless you have a deficiency, which is uncommon.',
    strength: EvidenceStrength.moderate,
    sourceIds: ['ods_biotin'],
    limitations: 'High-dose biotin can interfere with some lab tests — tell your clinician if you take it.',
    reviewedOn: _reviewed,
    reviewStatus: _draft,
  ),
  EvidenceClaim(
    id: 'iron_hair',
    topic: 'Hair, skin & nails',
    statement: 'Low iron can contribute to tiredness and hair shedding, but it should be confirmed with a blood test rather than assumed from symptoms.',
    strength: EvidenceStrength.moderate,
    sourceIds: ['ods_iron'],
    limitations: 'Many non-dietary causes (thyroid, hormones, stress, medications) produce similar symptoms. Don\'t start iron supplements without advice.',
    reviewedOn: _reviewed,
    reviewStatus: _draft,
    foodSources: ['lentils', 'spinach', 'tofu', 'ground_beef', 'chickpeas'],
  ),
];

/// Which claims explain each nutrient on the dashboard.
const claimsByNutrient = <Nutrient, List<String>>{
  Nutrient.fibre: ['fibre_foods'],
  Nutrient.protein: ['protein_variety'],
  Nutrient.sodium: ['sodium_cooking'],
  Nutrient.sugars: ['free_sugars'],
  Nutrient.iron: ['iron_hair'],
};

EvidenceClaim? claimById(String id) => evidenceClaims.where((c) => c.id == id).firstOrNull;
