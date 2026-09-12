import type {
  ApplicabilityContext, FactDefinition, SectionKey, Ternary,
} from './types.ts';
import { evaluate, referencedFields } from './predicate.ts';
import { buildQuestionTemplates, normalizeQuestion } from './questions.ts';
import { SECTIONS, SECTION_LABEL } from './sections.ts';

import { listingFacts }    from './definitions/a-listing.ts';
import { structureFacts }  from './definitions/b-structure.ts';
import { exteriorFacts }   from './definitions/c-exterior.ts';
import { mechanicalFacts } from './definitions/d-mechanical.ts';
import { kitchenFacts }    from './definitions/e-kitchen.ts';
import { bathroomFacts }   from './definitions/f-bathrooms.ts';
import { interiorFacts }   from './definitions/g-interior.ts';
import { basementFacts }   from './definitions/h-basement.ts';
import { energyFacts }     from './definitions/i-energy.ts';
import { condoFacts }      from './definitions/j-condo.ts';
import { utilitiesFacts }  from './definitions/k-utilities.ts';
import { legalFacts }      from './definitions/l-legal.ts';

export * from './types.ts';
export { evaluate, referencedFields } from './predicate.ts';
export { normalizeQuestion, buildQuestionTemplates, MULTI_FACT_QUESTIONS } from './questions.ts';
export type { QuestionTemplate } from './questions.ts';
export { SECTIONS, SECTION_LABEL } from './sections.ts';

/** Bump when a definition's meaning changes; additions alone do not require it. */
export const CATALOG_VERSION = 1;

export const FACT_DEFINITIONS: FactDefinition[] = [
  ...listingFacts, ...structureFacts, ...exteriorFacts, ...mechanicalFacts,
  ...kitchenFacts, ...bathroomFacts, ...interiorFacts, ...basementFacts,
  ...energyFacts, ...condoFacts, ...utilitiesFacts, ...legalFacts,
];

export const FACT_BY_KEY: Map<string, FactDefinition> =
  new Map(FACT_DEFINITIONS.map((d) => [d.key, d]));

export const QUESTION_TEMPLATES = buildQuestionTemplates(FACT_DEFINITIONS);

export function getDefinition(key: string): FactDefinition | undefined {
  return FACT_BY_KEY.get(key);
}

export function definitionsInSection(section: SectionKey): FactDefinition[] {
  return FACT_DEFINITIONS.filter((d) => d.section === section);
}

export function disclosureDefinitions(): FactDefinition[] {
  return FACT_DEFINITIONS.filter((d) => d.isDisclosure === true);
}

/**
 * Every applicability field the catalog reads. The property setup screen asks
 * exactly these questions — adding a fact that needs a new field adds a setup
 * question automatically, instead of silently producing 'unknown' applicability
 * forever.
 */
export function applicabilityFields(): string[] {
  const fields = new Set<string>();
  for (const def of FACT_DEFINITIONS) referencedFields(def.appliesWhen, fields);
  return [...fields].sort();
}

export type ApplicabilitySplit = {
  applicable: FactDefinition[];
  /** Ruled out by the property's own shape: a condo has no roof. */
  notApplicable: FactDefinition[];
  /** Blocked on a setup question the agent has not answered yet. */
  unresolved: FactDefinition[];
  /** The specific setup fields to ask about, ranked by what they unlock. */
  missingFields: { field: string; unlocks: number; weight: number }[];
};

export function splitByApplicability(ctx: ApplicabilityContext): ApplicabilitySplit {
  const applicable: FactDefinition[] = [];
  const notApplicable: FactDefinition[] = [];
  const unresolved: FactDefinition[] = [];
  const missing = new Map<string, { field: string; unlocks: number; weight: number }>();

  for (const def of FACT_DEFINITIONS) {
    const result: Ternary = evaluate(def.appliesWhen, ctx);
    if (result === true) { applicable.push(def); continue; }
    if (result === false) { notApplicable.push(def); continue; }

    unresolved.push(def);
    for (const field of referencedFields(def.appliesWhen)) {
      if (ctx[field] !== undefined && ctx[field] !== null) continue;
      const entry = missing.get(field) ?? { field, unlocks: 0, weight: 0 };
      entry.unlocks += 1;
      entry.weight += def.coverageWeight;
      missing.set(field, entry);
    }
  }

  const missingFields = [...missing.values()].sort(
    (a, b) => b.weight - a.weight || a.field.localeCompare(b.field));

  return { applicable, notApplicable, unresolved, missingFields };
}

/**
 * Catalog invariants, enforced in tests and at seed time. A malformed catalog
 * is not a runtime error somewhere downstream — it is a build failure here.
 */
export function validateCatalog(defs: FactDefinition[] = FACT_DEFINITIONS): string[] {
  const problems: string[] = [];
  const seen = new Set<string>();
  const sectionKeys = new Set(SECTIONS.map((s) => s.key));

  for (const def of defs) {
    if (seen.has(def.key)) problems.push(`duplicate key: ${def.key}`);
    seen.add(def.key);

    if (!/^[a-z0-9]+(\.[a-z0-9_]+)+$/.test(def.key)) {
      problems.push(`key is not dotted lowercase: ${def.key}`);
    }
    if (!sectionKeys.has(def.section)) {
      problems.push(`${def.key}: unknown section ${def.section}`);
    }
    if (def.coverageWeight < 1 || def.coverageWeight > 10) {
      problems.push(`${def.key}: coverage weight out of range`);
    }
    if (def.dataType === 'enum' && (!def.enumOptions || def.enumOptions.length < 2)) {
      problems.push(`${def.key}: enum with fewer than two options`);
    }
    if (def.dataType !== 'enum' && def.enumOptions) {
      problems.push(`${def.key}: enumOptions on a non-enum fact`);
    }
    // A dimension is meaningless without a unit; a plain number is often a
    // count ("how many bedrooms"), which has none.
    if (def.dataType === 'dimension' && !def.unit) {
      problems.push(`${def.key}: dimension fact with no unit`);
    }
    if (def.answersQuestions.length === 0) {
      problems.push(`${def.key}: answers no question — why is it in the catalog?`);
    }
    for (const q of def.answersQuestions) {
      if (normalizeQuestion(q).length < 3) {
        problems.push(`${def.key}: unusable question template "${q}"`);
      }
    }
    if (def.isDisclosure && def.coverageWeight < 6) {
      problems.push(`${def.key}: disclosure facts must carry real weight`);
    }
  }

  for (const template of QUESTION_TEMPLATES) {
    for (const key of template.factKeys) {
      if (!seen.has(key)) {
        problems.push(`question "${template.question}" maps to unknown key ${key}`);
      }
    }
  }

  return problems;
}

/** SQL seed for `fact_definitions`, emitted rather than hand-maintained. */
export function toSeedRows(defs: FactDefinition[] = FACT_DEFINITIONS) {
  return defs.map((d) => ({
    key: d.key,
    label: d.label,
    section: d.section,
    category: d.category,
    data_type: d.dataType,
    unit: d.unit ?? null,
    enum_options: d.enumOptions ? JSON.stringify(d.enumOptions) : null,
    applies_when: JSON.stringify(d.appliesWhen),
    default_visibility: d.defaultVisibility,
    is_disclosure: d.isDisclosure === true,
    coverage_weight: d.coverageWeight,
    answers_questions: d.answersQuestions,
    room_scoped: d.roomScoped === true,
    help_text: d.helpText ?? null,
    catalog_version: CATALOG_VERSION,
  }));
}

export { SECTION_LABEL as sectionLabels };
