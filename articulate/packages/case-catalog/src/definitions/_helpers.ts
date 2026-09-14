import type { CaseFactDefinition, Predicate, SectionKey } from '../types.ts';

export const ALWAYS: Predicate = { always: true };

export const FIXED: Predicate = {
  field: 'restoration_type', op: 'in',
  value: ['crown', 'bridge', 'veneer', 'inlay_onlay', 'implant_crown',
          'implant_bridge', 'post_core', 'temporary'],
};

export const IMPLANT: Predicate = {
  field: 'restoration_type', op: 'in', value: ['implant_crown', 'implant_bridge'],
};

export const REMOVABLE: Predicate = {
  field: 'restoration_type', op: 'in',
  value: ['full_denture', 'partial_denture'],
};

export const APPLIANCE: Predicate = {
  field: 'restoration_type', op: 'in',
  value: ['night_guard', 'aligner', 'surgical_guide'],
};

export const MULTI_UNIT: Predicate = {
  field: 'restoration_type', op: 'in', value: ['bridge', 'implant_bridge'],
};

export const yes = (field: string): Predicate => ({ field, op: 'is_true' });
export const eq = (field: string, value: string): Predicate => ({ field, op: 'eq', value });
export const oneOf = (field: string, value: string[]): Predicate =>
  ({ field, op: 'in', value });
export const all = (...preds: Predicate[]): Predicate => ({ all: preds });
export const any = (...preds: Predicate[]): Predicate => ({ any: preds });
export const not = (pred: Predicate): Predicate => ({ not: pred });

/**
 * Section-scoped builder. The defaults are the common case — visible to the
 * practice, expected rather than blocking, remake-risk rather than patient
 * safety — so each definition below reads as domain content, not boilerplate.
 */
export function section(sectionKey: SectionKey, category: string) {
  return function define(
    key: string,
    label: string,
    dataType: CaseFactDefinition['dataType'],
    answerWeight: number,
    answersQuestions: string[],
    extra: Partial<CaseFactDefinition> = {},
  ): CaseFactDefinition {
    return {
      key, label, section: sectionKey, category, dataType, answerWeight,
      answersQuestions,
      appliesWhen: ALWAYS,
      visibility: 'practice',
      necessity: 'expected',
      safety: 'remake_risk',
      ...extra,
    };
  };
}
