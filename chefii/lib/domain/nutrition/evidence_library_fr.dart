import '../models/health.dart';
import 'evidence_library.dart';

/// Canadian French text for the evidence library.
///
/// Same status as the English: INTERNAL DRAFTS pending review by a registered
/// dietitian (and a dental professional for oral health). These are faithful,
/// conservative translations — they must never add, strengthen or soften a
/// claim. Hedges keep the same strength as the English (may → peut,
/// unlikely → peu probable, should → devrait). Numbers, units and thresholds
/// are unchanged. Typography: U+00A0 before « : ; ? ! », inside « » and
/// between a number and its unit or %.
///
/// Only display text lives here. Ids, strength, sources, food sources, review
/// status and dates always come from the English [evidenceClaims], and code
/// logic (e.g. filtering by topic) uses the English values.
const evidenceClaimsFr = <String, ({String topic, String statement, String limitations})>{
  'fibre_foods': (
    topic: 'Fibres',
    statement: 'La plupart des adultes gagnent à consommer davantage d’aliments riches en fibres — légumes, fruits, grains entiers, haricots et lentilles.',
    limitations: 'Recommandation pour l’ensemble de la population. Certains troubles digestifs nécessitent des conseils individualisés ; augmentez graduellement votre apport en fibres, accompagné de liquides.',
  ),
  'protein_variety': (
    topic: 'Protéines',
    statement: 'Inclure un aliment protéiné aux repas — et choisir plus souvent des protéines d’origine végétale — contribue à un mode d’alimentation équilibré.',
    limitations: 'Les besoins varient selon l’âge, la corpulence, le niveau d’activité, la grossesse et les problèmes de santé.',
  ),
  'sodium_cooking': (
    topic: 'Sodium',
    statement: 'Cuisiner plus de repas à la maison et recourir moins aux aliments hautement transformés est l’un des moyens les plus pratiques de consommer moins de sodium.',
    limitations: 'Les estimations de sodium dépendent de la quantité de sel que vous ajoutez réellement, que les recettes ne peuvent qu’estimer approximativement.',
  ),
  'free_sugars': (
    topic: 'Sucres',
    statement: 'Il est recommandé de maintenir les sucres libres sous 10 % de l’apport énergétique quotidien ; descendre sous 5 % peut procurer des bienfaits supplémentaires.',
    limitations: 'Les « sucres libres » excluent les sucres naturellement présents dans les fruits entiers, les légumes et le lait. L’estimation des « sucres totaux » de Chefii les inclut ; elle surestime donc les sucres libres.',
  ),
  'vegetables_variety': (
    topic: 'Variété',
    statement: 'Remplir la moitié de votre assiette de légumes et de fruits, de couleurs variées, est une façon simple de bien manger.',
    limitations: 'Un repère visuel, et non une cible précise.',
  ),
  'water_first': (
    topic: 'Boissons',
    statement: 'Faire de l’eau votre boisson de choix aide à limiter les boissons sucrées.',
    limitations: 'Les besoins en liquides varient selon le climat, le niveau d’activité et l’état de santé.',
  ),
  'sugar_frequency_teeth': (
    topic: 'Dents',
    statement: 'Pour la carie dentaire, la fréquence à laquelle vous consommez des aliments et des boissons sucrés compte, tout comme la quantité.',
    limitations: 'Le fluorure, le brossage, la salive et la génétique influent aussi fortement sur le risque de carie. Il s’agit d’un contenu éducatif, et non d’une évaluation dentaire.',
  ),
  'acid_sipping': (
    topic: 'Dents',
    statement: 'Siroter lentement des boissons acides sur de longues périodes garde les dents exposées à l’acide plus longtemps que de les boire avec un repas.',
    limitations: 'Référence en attente de révision par un professionnel de la santé dentaire. Le risque d’érosion dépend aussi de la salive, du reflux et des habitudes de brossage.',
  ),
  'biotin_hair': (
    topic: 'Cheveux, peau et ongles',
    statement: 'Il est peu probable que les suppléments de biotine améliorent l’état des cheveux ou des ongles, à moins que vous ayez une carence, ce qui est peu fréquent.',
    limitations: 'La biotine à forte dose peut interférer avec certaines analyses de laboratoire — informez votre professionnel de la santé si vous en prenez.',
  ),
  'iron_hair': (
    topic: 'Cheveux, peau et ongles',
    statement: 'Un faible taux de fer peut contribuer à la fatigue et à la chute des cheveux, mais il devrait être confirmé par une analyse sanguine plutôt que présumé d’après les symptômes.',
    limitations: 'De nombreuses causes non alimentaires (thyroïde, hormones, stress, médicaments) produisent des symptômes semblables. Ne commencez pas à prendre des suppléments de fer sans demander conseil.',
  ),
};

/// French titles, publishers and URLs. Where no official French version
/// exists (NIH Office of Dietary Supplements), the English title, publisher
/// and URL are kept.
const evidenceSourcesFr = <String, ({String title, String publisher, String url})>{
  'hc_food_guide': (
    title: 'Guide alimentaire canadien',
    publisher: 'Santé Canada',
    url: 'https://guide-alimentaire.canada.ca/fr/',
  ),
  'hc_dri': (
    title: 'Tableaux des apports nutritionnels de référence',
    publisher: 'Santé Canada',
    url: 'https://www.canada.ca/fr/sante-canada/services/aliments-nutrition/saine-alimentation/apports-nutritionnels-reference/tableaux.html',
  ),
  'who_sugars': (
    title: 'Directive : apport en sucres chez l’adulte et l’enfant',
    publisher: 'Organisation mondiale de la Santé',
    url: 'https://www.who.int/fr/publications/i/item/9789241549028',
  ),
  'who_caries': (
    title: 'Sucres et caries dentaires (aide-mémoire)',
    publisher: 'Organisation mondiale de la Santé',
    url: 'https://www.who.int/fr/news-room/fact-sheets/detail/sugars-and-dental-caries',
  ),
  'ods_biotin': (
    title: 'Biotin — Fact Sheet for Health Professionals',
    publisher: 'NIH Office of Dietary Supplements',
    url: 'https://ods.od.nih.gov/factsheets/Biotin-HealthProfessional/',
  ),
  'ods_iron': (
    title: 'Iron — Fact Sheet for Health Professionals',
    publisher: 'NIH Office of Dietary Supplements',
    url: 'https://ods.od.nih.gov/factsheets/Iron-HealthProfessional/',
  ),
};

/// French for the `kind` and `source` strings of [DailyReference].
const dailyReferenceTermsFr = <String, String>{
  'Daily Value': 'valeur quotidienne',
  'AI': 'AS (apport suffisant)',
  'RDA': 'ANR (apport nutritionnel recommandé)',
  'Health Canada, Table of Daily Values': 'Santé Canada, Tableau des valeurs quotidiennes',
};

/// [c] with its display text in French when [french] is true. Everything
/// except topic, statement and limitations is kept as is. Falls back to the
/// English claim when no translation exists.
EvidenceClaim localizeClaim(EvidenceClaim c, bool french) {
  final fr = french ? evidenceClaimsFr[c.id] : null;
  if (fr == null) return c;
  return EvidenceClaim(
    id: c.id,
    topic: fr.topic,
    statement: fr.statement,
    strength: c.strength,
    sourceIds: c.sourceIds,
    limitations: fr.limitations,
    reviewedOn: c.reviewedOn,
    reviewStatus: c.reviewStatus,
    foodSources: c.foodSources,
  );
}

/// [s] with its title, publisher and URL in French when [french] is true.
EvidenceSource localizeSource(EvidenceSource s, bool french) {
  final fr = french ? evidenceSourcesFr[s.id] : null;
  if (fr == null) return s;
  return EvidenceSource(
    id: s.id,
    title: fr.title,
    publisher: fr.publisher,
    studyType: s.studyType,
    year: s.year,
    url: fr.url,
  );
}

/// The localized sources cited by [c], in order.
List<EvidenceSource> localizedSourcesOf(EvidenceClaim c, bool french) =>
    [for (final id in c.sourceIds) localizeSource(evidenceSources[id]!, french)];

/// A [DailyReference] kind or source in French when [french] is true.
String localizeReferenceTerm(String term, bool french) => french ? (dailyReferenceTermsFr[term] ?? term) : term;
