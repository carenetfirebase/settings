import type { FactDefinition } from './types.ts';

export type QuestionTemplate = {
  question: string;
  normalized: string;
  factKeys: string[];
  category: string;
  /**
   * How often visitors actually ask this, 1–100. Seeded by hand and then
   * learned from the real question corpus across the platform (§7.4), which is
   * what makes the gap list get smarter as the platform is used.
   */
  frequency: number;
  isSeed: boolean;
};

/** Lowercase, strip punctuation, collapse whitespace, drop a leading filler. */
export function normalizeQuestion(text: string): string {
  return text
    .toLowerCase()
    .replace(/[’']/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .replace(/^(so|ok|okay|um|uh|hey|hi|and|but)\s+/, '')
    .replace(/\s+/g, ' ');
}

/**
 * Questions that span several facts, so they cannot be derived from any single
 * definition's `answersQuestions`. These are the ones visitors actually ask at
 * an open house, in the words they use.
 */
export const MULTI_FACT_QUESTIONS: Omit<QuestionTemplate, 'normalized' | 'isSeed'>[] = [
  { question: 'What are the utilities like?',
    factKeys: ['costs.utilities.annual_gas', 'costs.utilities.annual_electricity',
               'costs.utilities.annual_water', 'costs.utilities.period_covered'],
    category: 'operating_costs', frequency: 78 },
  { question: 'What does it cost to run this house every month?',
    factKeys: ['costs.utilities.annual_gas', 'costs.utilities.annual_electricity',
               'costs.utilities.annual_water', 'taxes.annual_amount',
               'costs.insurance.annual_premium'],
    category: 'operating_costs', frequency: 62 },
  { question: 'How old are the big ticket items?',
    factKeys: ['exterior.roof.replacement_year', 'mechanical.furnace.install_year',
               'mechanical.water_heater.install_year', 'exterior.windows.replacement_year',
               'electrical.panel.install_year'],
    category: 'systems_age', frequency: 88 },
  { question: 'What has been updated recently?',
    factKeys: ['legal.renovation.major_history', 'kitchen.renovation_year',
               'exterior.roof.replacement_year', 'bathrooms.ensuite.renovation_year',
               'interior.flooring.install_year'],
    category: 'renovations', frequency: 84 },
  { question: 'Is there anything wrong with the house?',
    factKeys: ['legal.disclosure.material_latent_defects',
               'basement.water_intrusion_history', 'exterior.roof.leak_history',
               'structure.settlement_history', 'basement.mould_history'],
    category: 'disclosure', frequency: 71 },
  { question: 'What stays and what goes?',
    factKeys: ['legal.chattels.included', 'legal.chattels.excluded',
               'legal.chattels.negotiable', 'kitchen.appliance.refrigerator.included',
               'bathrooms.laundry.washer_dryer_included',
               'interior.windows.coverings_included'],
    category: 'inclusions', frequency: 80 },
  { question: 'Is anything rented or leased?',
    factKeys: ['mechanical.furnace.owned_or_rented',
               'mechanical.water_heater.owned_or_rented',
               'energy.solar.owned_or_leased', 'legal.chattels.leased_items',
               'costs.rental_contracts'],
    category: 'contracts', frequency: 54 },
  { question: 'Can I rent out the basement?',
    factKeys: ['basement.suite_status', 'basement.suite.separate_entrance',
               'legal.secondary_suite_registration', 'basement.suite.egress_windows'],
    category: 'suite', frequency: 76 },
  { question: 'How is the house heated and cooled?',
    factKeys: ['mechanical.heating.type', 'mechanical.furnace.install_year',
               'mechanical.cooling.type', 'mechanical.ac.install_year'],
    category: 'mechanical', frequency: 82 },
  { question: 'What is the parking situation?',
    factKeys: ['exterior.garage.type', 'exterior.garage.car_capacity',
               'exterior.parking.spaces_total', 'exterior.parking.driveway_material'],
    category: 'parking', frequency: 74 },
  { question: 'Tell me about the kitchen.',
    factKeys: ['kitchen.renovation_year', 'kitchen.counter.material',
               'kitchen.appliance.stove.type', 'kitchen.island.present'],
    category: 'kitchen', frequency: 69 },
  { question: 'How much are the taxes and fees?',
    factKeys: ['taxes.annual_amount', 'taxes.tax_year', 'condo.fee_monthly',
               'condo.fee_includes'],
    category: 'operating_costs', frequency: 85 },
  { question: 'Has there ever been water in the basement?',
    factKeys: ['basement.water_intrusion_history',
               'basement.water_intrusion_remediation', 'basement.waterproofing',
               'plumbing.sump_pump.present'],
    category: 'disclosure', frequency: 73 },
  { question: 'Is the work permitted?',
    factKeys: ['legal.permits.history', 'legal.permits.open',
               'legal.permits.unpermitted_work', 'basement.development_permitted'],
    category: 'permits', frequency: 58 },
  { question: 'What is the internet like here?',
    factKeys: ['utilities.internet.providers', 'utilities.internet.max_speed'],
    category: 'utilities', frequency: 47 },
  { question: 'When can I move in?',
    factKeys: ['listing.possession_date', 'listing.possession_flexibility',
               'listing.occupancy'],
    category: 'timing', frequency: 79 },
  { question: 'How big is it really?',
    factKeys: ['property.living_area', 'property.living_area_source',
               'property.total_finished_area', 'basement.finished_area'],
    category: 'size', frequency: 81 },
  { question: 'Which schools are nearby?',
    factKeys: ['location.schools.catchment'],
    category: 'location', frequency: 66 },
];

/**
 * The full seed table: every question a fact claims to answer, plus the
 * multi-fact questions above. Duplicates collapse by normalized form, keeping
 * the higher frequency and merging the fact keys — two definitions claiming
 * the same phrasing is a legitimate multi-key question, not a conflict.
 */
export function buildQuestionTemplates(defs: FactDefinition[]): QuestionTemplate[] {
  const byNormalized = new Map<string, QuestionTemplate>();

  const add = (t: QuestionTemplate) => {
    const existing = byNormalized.get(t.normalized);
    if (!existing) { byNormalized.set(t.normalized, t); return; }
    existing.factKeys = [...new Set([...existing.factKeys, ...t.factKeys])];
    existing.frequency = Math.max(existing.frequency, t.frequency);
    existing.isSeed = existing.isSeed && t.isSeed;
  };

  for (const def of defs) {
    for (const q of def.answersQuestions) {
      add({
        question: q,
        normalized: normalizeQuestion(q),
        factKeys: [def.key],
        category: def.category,
        // Seed frequency from the catalog's own view of buyer interest until
        // real traffic replaces it.
        frequency: def.coverageWeight * 5,
        isSeed: true,
      });
    }
  }

  for (const q of MULTI_FACT_QUESTIONS) {
    add({ ...q, normalized: normalizeQuestion(q.question), isSeed: true });
  }

  return [...byNormalized.values()];
}
