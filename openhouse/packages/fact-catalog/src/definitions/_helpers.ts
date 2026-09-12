import type { FactDefinition, Predicate, SectionKey } from '../types.ts';

export const ALWAYS: Predicate = { always: true };

export const CONDO: Predicate =
  { field: 'property_type', op: 'in', value: ['condo_apartment', 'condo_townhouse'] };

export const NOT_APARTMENT: Predicate =
  { field: 'property_type', op: 'not_in', value: ['condo_apartment'] };

export const FREEHOLD: Predicate =
  { field: 'property_type', op: 'not_in', value: ['condo_apartment', 'condo_townhouse'] };

export const yes = (field: string): Predicate => ({ field, op: 'is_true' });

export const eq = (field: string, value: string): Predicate =>
  ({ field, op: 'eq', value });

export const all = (...preds: Predicate[]): Predicate => ({ all: preds });

/**
 * Section-scoped definition builder. Defaults are the common case — public,
 * not a disclosure, not room-scoped — so each entry below reads as its own
 * content rather than as boilerplate.
 */
export function section(sectionKey: SectionKey, category: string) {
  return function define(
    key: string,
    label: string,
    dataType: FactDefinition['dataType'],
    coverageWeight: number,
    answersQuestions: string[],
    extra: Partial<FactDefinition> = {},
  ): FactDefinition {
    return {
      key,
      label,
      section: sectionKey,
      category,
      dataType,
      coverageWeight,
      answersQuestions,
      appliesWhen: ALWAYS,
      defaultVisibility: 'public',
      ...extra,
    };
  };
}
