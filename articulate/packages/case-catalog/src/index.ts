import type {
  CaseContext, CaseFactDefinition, Necessity, SectionKey, Ternary,
} from './types.ts';
import { evaluate, referencedFields } from './predicate.ts';
import { buildQuestionTemplates, normalizeQuestion } from './questions.ts';
import { SECTIONS, SECTION_LABEL } from './sections.ts';

import { intakeFacts }       from './definitions/a-intake.ts';
import { prescriptionFacts } from './definitions/b-prescription.ts';
import { inputFacts }        from './definitions/c-inputs.ts';
import { designFacts }       from './definitions/d-design.ts';
import { implantFacts }      from './definitions/e-implant.ts';
import { removableFacts }    from './definitions/f-removable.ts';
import { materialFacts }     from './definitions/g-materials.ts';
import { manufactureFacts }  from './definitions/h-manufacture.ts';
import { deliveryFacts }     from './definitions/i-delivery.ts';
import { outcomeFacts }      from './definitions/j-outcome.ts';
import { regulatoryFacts }   from './definitions/k-regulatory.ts';
import { commercialFacts }   from './definitions/l-commercial.ts';

export * from './types.ts';
export { evaluate, referencedFields } from './predicate.ts';
export { normalizeQuestion, buildQuestionTemplates, MULTI_FACT_QUESTIONS } from './questions.ts';
export type { QuestionTemplate } from './questions.ts';
export { SECTIONS, SECTION_LABEL } from './sections.ts';

export const CATALOG_VERSION = 1;

export const CASE_FACTS: CaseFactDefinition[] = [
  ...intakeFacts, ...prescriptionFacts, ...inputFacts, ...designFacts,
  ...implantFacts, ...removableFacts, ...materialFacts, ...manufactureFacts,
  ...deliveryFacts, ...outcomeFacts, ...regulatoryFacts, ...commercialFacts,
];

export const FACT_BY_KEY: Map<string, CaseFactDefinition> =
  new Map(CASE_FACTS.map((d) => [d.key, d]));

export const QUESTION_TEMPLATES = buildQuestionTemplates(CASE_FACTS);

export function getDefinition(key: string): CaseFactDefinition | undefined {
  return FACT_BY_KEY.get(key);
}

export function definitionsInSection(section: SectionKey): CaseFactDefinition[] {
  return CASE_FACTS.filter((d) => d.section === section);
}

/** Everything the lab is required to retain for this device. */
export function dhrDefinitions(): CaseFactDefinition[] {
  return CASE_FACTS.filter((d) => d.isDhr === true);
}

export function caseContextFields(): string[] {
  const fields = new Set<string>();
  for (const def of CASE_FACTS) referencedFields(def.appliesWhen, fields);
  return [...fields].sort();
}

export type ApplicabilitySplit = {
  applicable: CaseFactDefinition[];
  notApplicable: CaseFactDefinition[];
  unresolved: CaseFactDefinition[];
  missingFields: { field: string; unlocks: number; weight: number }[];
};

export function splitByApplicability(ctx: CaseContext): ApplicabilitySplit {
  const applicable: CaseFactDefinition[] = [];
  const notApplicable: CaseFactDefinition[] = [];
  const unresolved: CaseFactDefinition[] = [];
  const missing = new Map<string, { field: string; unlocks: number; weight: number }>();

  for (const def of CASE_FACTS) {
    const result: Ternary = evaluate(def.appliesWhen, ctx);
    if (result === true) { applicable.push(def); continue; }
    if (result === false) { notApplicable.push(def); continue; }

    unresolved.push(def);
    for (const field of referencedFields(def.appliesWhen)) {
      if (ctx[field] !== undefined && ctx[field] !== null) continue;
      const entry = missing.get(field) ?? { field, unlocks: 0, weight: 0 };
      entry.unlocks += 1;
      entry.weight += def.answerWeight;
      missing.set(field, entry);
    }
  }

  return {
    applicable, notApplicable, unresolved,
    missingFields: [...missing.values()]
      .sort((a, b) => b.weight - a.weight || a.field.localeCompare(b.field)),
  };
}

export const NECESSITY_ORDER: Necessity[] = ['blocking', 'required', 'expected', 'optional'];

export function validateCatalog(defs: CaseFactDefinition[] = CASE_FACTS): string[] {
  const problems: string[] = [];
  const seen = new Set<string>();
  const sections = new Set(SECTIONS.map((s) => s.key));

  for (const def of defs) {
    if (seen.has(def.key)) problems.push(`duplicate key: ${def.key}`);
    seen.add(def.key);

    if (!/^[a-z0-9]+(\.[a-z0-9_]+)+$/.test(def.key)) {
      problems.push(`key is not dotted lowercase: ${def.key}`);
    }
    if (!sections.has(def.section)) problems.push(`${def.key}: unknown section`);
    if (def.answerWeight < 1 || def.answerWeight > 10) {
      problems.push(`${def.key}: answer weight out of range`);
    }
    if (def.dataType === 'enum' && (def.enumOptions?.length ?? 0) < 2) {
      problems.push(`${def.key}: enum with fewer than two options`);
    }
    if (def.dataType !== 'enum' && def.enumOptions) {
      problems.push(`${def.key}: enumOptions on a non-enum fact`);
    }
    if ((def.dataType === 'dimension' || def.dataType === 'torque') && !def.unit) {
      problems.push(`${def.key}: ${def.dataType} with no unit`);
    }
    if (def.answersQuestions.length === 0) {
      problems.push(`${def.key}: answers no question — why is it in the catalog?`);
    }
    // A blocking fact with no phrasing for the practice cannot be chased, and a
    // fact nobody can chase is not actually blocking — it is just stuck.
    if (def.necessity === 'blocking' && def.safety === 'patient_safety' &&
        !def.askPractice && !def.isDhr && def.visibility === 'practice') {
      problems.push(`${def.key}: blocking safety fact with no way to ask for it`);
    }
    // PHI is not forbidden — an allergy note is one of the most valuable facts
    // on a case. What is forbidden is PHI reaching anyone but the originating
    // practice, which the pipeline enforces, and PHI being swept into a broad
    // question that was not asking for it.
    if (def.visibility === 'phi' && def.safety === 'commercial') {
      problems.push(`${def.key}: PHI held for a commercial purpose`);
    }
  }

  const phi = new Set(defs.filter((d) => d.visibility === 'phi').map((d) => d.key));
  for (const template of QUESTION_TEMPLATES) {
    for (const key of template.factKeys) {
      if (!seen.has(key)) {
        problems.push(`question "${template.question}" maps to unknown key ${key}`);
      }
      if (phi.has(key) && template.factKeys.length > 1) {
        problems.push(`broad question "${template.question}" would sweep in PHI (${key})`);
      }
    }
  }
  return problems;
}

export { SECTION_LABEL as sectionLabels };
