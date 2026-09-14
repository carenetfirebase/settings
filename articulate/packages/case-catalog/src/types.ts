/**
 * ARTICULATE — canonical case-fact catalog.
 *
 * A dental lab case is a patient-matched medical device. Every fact here is
 * something the lab may one day have to state under its own name: to a dentist,
 * to a patient's lawyer, or to a regulator asking which lot went into which
 * mouth. The catalog is global and versioned; a case never invents a key, which
 * is what makes extraction from a prescription schema-constrained rather than
 * persuadable.
 */

export type FactDataType =
  | 'text' | 'number' | 'integer' | 'enum' | 'boolean' | 'date' | 'datetime'
  | 'shade' | 'tooth' | 'tooth_set' | 'lot' | 'money' | 'dimension' | 'torque';

export type Visibility =
  /** The practice sees it in the portal and the AI may say it. */
  | 'practice'
  /** Lab-internal: costs, technician performance, margin. */
  | 'lab_only'
  /** Protected health information — minimised, never in an answer payload. */
  | 'phi';

export type JsonValue =
  | string | number | boolean | null | JsonValue[] | { [key: string]: JsonValue };

export type Predicate =
  | { always: true }
  | { all: Predicate[] }
  | { any: Predicate[] }
  | { not: Predicate }
  | { field: string; op: 'eq' | 'ne'; value: JsonValue }
  | { field: string; op: 'in' | 'not_in'; value: JsonValue[] }
  | { field: string; op: 'is_true' | 'is_false' }
  | { field: string; op: 'gte' | 'lte'; value: number };

export type SectionKey =
  | 'A' | 'B' | 'C' | 'D' | 'E' | 'F' | 'G' | 'H' | 'I' | 'J' | 'K' | 'L';

/**
 * How badly the lab needs this before it can start.
 *
 * `blocking` is the one that earns its keep: a case missing a blocking fact
 * cannot be worked, and the lab's most expensive habit is discovering that on
 * the bench three days later instead of at intake.
 */
export type Necessity = 'blocking' | 'required' | 'expected' | 'optional';

/**
 * Getting this wrong hurts someone. Drives conflict severity, and whether a
 * mismatch stops the case or merely flags it.
 */
export type SafetyClass = 'patient_safety' | 'remake_risk' | 'commercial' | 'informational';

export type CaseFactDefinition = {
  /** Dotted, stable, never reused: 'rx.tooth_numbers'. */
  key: string;
  label: string;
  section: SectionKey;
  category: string;
  dataType: FactDataType;
  unit?: string;
  enumOptions?: string[];
  appliesWhen: Predicate;
  visibility: Visibility;
  necessity: Necessity;
  safety: SafetyClass;
  /** 1–10: how much a dentist actually cares. Drives answer coverage. */
  answerWeight: number;
  /** How the practice asks about it, in their words. */
  answersQuestions: string[];
  /** Part of the Device History Record the lab is required to retain. */
  isDhr?: boolean;
  /** The question the lab asks the practice when this is missing. */
  askPractice?: string;
  helpText?: string;
};

export type SectionMeta = { key: SectionKey; label: string; order: number };

export type CaseContext = Record<string, JsonValue | undefined>;

export type Ternary = true | false | 'unknown';
