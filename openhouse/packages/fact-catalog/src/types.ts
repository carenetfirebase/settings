/**
 * Canonical fact catalog types (architecture §6.2).
 *
 * The catalog is global and versioned, not per-property. A property never
 * defines a fact key; it only ever holds claims and resolved values against
 * keys that exist here. That is what makes extraction schema-constrained and
 * therefore injection-resistant (§14.3) — no text in a PDF can invent a key.
 */

export type FactDataType =
  | 'year'
  | 'text'
  | 'enum'
  | 'number'
  | 'boolean'
  | 'money'
  | 'dimension'
  | 'date';

export type FactVisibility = 'public' | 'agent_only';

export type JsonValue =
  | string
  | number
  | boolean
  | null
  | JsonValue[]
  | { [key: string]: JsonValue };

/**
 * `applies_when` predicate language.
 *
 * Deliberately tiny and data-only: it is stored as jsonb, evaluated in the
 * Truth Engine, and must be reviewable by someone who is not a programmer.
 * A condo has no roof and no septic field; scoring a condo against the full
 * catalog produces a permanently broken coverage number and destroys agent
 * trust in the metric on their first condo listing (§6.2).
 */
export type Predicate =
  | { always: true }
  | { all: Predicate[] }
  | { any: Predicate[] }
  | { not: Predicate }
  | { field: string; op: 'eq' | 'ne'; value: JsonValue }
  | { field: string; op: 'in' | 'not_in'; value: JsonValue[] }
  | { field: string; op: 'is_true' | 'is_false' }
  | { field: string; op: 'gte' | 'lte'; value: number };

/** Section letters A–L, matching the spec's fact sections. */
export type SectionKey =
  | 'A' | 'B' | 'C' | 'D' | 'E' | 'F' | 'G' | 'H' | 'I' | 'J' | 'K' | 'L';

export type FactDefinition = {
  /** Dotted, stable, and never reused: 'mechanical.furnace.install_year'. */
  key: string;
  label: string;
  section: SectionKey;
  category: string;
  dataType: FactDataType;
  unit?: string;
  enumOptions?: string[];
  appliesWhen: Predicate;
  defaultVisibility: FactVisibility;
  /** Disclosure facts are never auto-hidden and never bulk-confirmable (§8.1). */
  isDisclosure?: boolean;
  /** 1–10: how much buyers actually care. Drives coverage and gap ranking. */
  coverageWeight: number;
  /** Natural-language questions this fact answers, used for key resolution. */
  answersQuestions: string[];
  /** True when the fact is held per room rather than per property. */
  roomScoped?: boolean;
  helpText?: string;
};

export type SectionMeta = {
  key: SectionKey;
  label: string;
  /** Order in the agent console's fact editor and coverage breakdown. */
  order: number;
};

/**
 * Everything the predicate evaluator is allowed to see. These are answered
 * once at property setup — the console derives the questionnaire from the
 * fields the catalog actually references, so adding a fact that needs a new
 * applicability field automatically adds a setup question.
 */
export type ApplicabilityContext = Record<string, JsonValue | undefined>;

export type Ternary = true | false | 'unknown';
