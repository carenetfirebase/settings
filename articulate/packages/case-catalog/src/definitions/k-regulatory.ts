import type { CaseFactDefinition } from '../types.ts';
import { section, yes } from './_helpers.ts';

const d = section('K', 'regulatory');

/**
 * Section K — the regulatory spine.
 *
 * A dental lab makes patient-matched devices to a practitioner's prescription.
 * The specific obligations differ by jurisdiction, so this section records what
 * the lab did rather than asserting what any regulator requires: the statement
 * issued, the record retained, the complaint logged. What a given rule demands
 * is a question for the lab's regulatory adviser, and the AI says so.
 */
const k = (
  key: string, label: string, dataType: CaseFactDefinition['dataType'],
  weight: number, questions: string[], extra: Partial<CaseFactDefinition> = {},
): CaseFactDefinition => d(key, label, dataType, weight, questions,
  { isDhr: true, necessity: 'required', safety: 'patient_safety', ...extra });

export const regulatoryFacts: CaseFactDefinition[] = [
  k('reg.device_statement_issued', 'Patient-matched device statement issued', 'boolean', 8,
    ['is there a statement of manufacture', 'did you include the device statement',
     'can i get the conformity paperwork']),
  k('reg.statement_reference', 'Statement reference', 'text', 6,
    ['what is the reference on the statement']),
  k('reg.prescriber_on_record', 'Prescriber on record', 'boolean', 7,
    ['is the prescribing dentist on file']),
  k('reg.dhr_complete', 'Device history record complete', 'boolean', 9,
    ['is the record complete', 'do you have full traceability on this case'],
    { helpText: 'Computed, not asserted: every DHR-flagged fact on this case ' +
                'resolved. A lab that says "yes" without the check is guessing ' +
                'about its own records.' }),
  k('reg.retention_until', 'Record retention until', 'date', 5,
    ['how long do you keep the records', 'when do these records get destroyed']),
  k('reg.lot_traceable', 'All materials lot-traceable', 'boolean', 9,
    ['can you trace the materials', 'do you know which lots went in']),
  k('reg.adverse_event_reported', 'Adverse event reported', 'boolean', 9,
    ['was this reported', 'did you report it to anyone'],
    { necessity: 'expected' }),
  k('reg.recall_affected', 'Affected by a material recall', 'boolean', 10,
    ['was this case affected by the recall', 'did my patient get the recalled lot',
     'is this one of the affected cases'],
    { necessity: 'expected',
      helpText: 'Answered from lot genealogy, not from memory. This is the ' +
                'question that has to be right the first time.' }),
  k('reg.recall_notified_at', 'Practice notified of recall', 'datetime', 10,
    ['when did you tell me about the recall', 'was i notified'],
    { necessity: 'expected' }),
  k('reg.outsourced_steps', 'Steps outsourced', 'text', 8,
    ['did you make this in house', 'was any of it sent out', 'do you outsource'],
    { helpText: 'Practices increasingly ask this directly, and the honest answer ' +
                'protects the lab. Outsourcing is normal; concealing it is not.' }),
  k('reg.outsourced_to', 'Outsourced to', 'text', 8,
    ['who made it', 'which lab did you send it to'],
    { appliesWhen: yes('is_outsourced') }),
  k('reg.outsource_country', 'Country of manufacture', 'text', 9,
    ['where was it made', 'was it made overseas', 'what country did it come from'],
    { appliesWhen: yes('is_outsourced') }),
  k('reg.infection_control_protocol', 'Infection control protocol', 'text', 6,
    ['what is your infection control protocol']),
  k('reg.lab_registration', 'Lab registration reference', 'text', 6,
    ['are you registered', 'what is your registration number', 'are you certified']),
  k('reg.quality_system', 'Quality system', 'text', 6,
    ['do you have iso', 'what quality system do you work to']),
];
