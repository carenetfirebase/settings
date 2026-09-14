import type { CaseFactDefinition } from './types.ts';

export type QuestionTemplate = {
  question: string;
  normalized: string;
  factKeys: string[];
  category: string;
  frequency: number;
  isSeed: boolean;
};

export function normalizeQuestion(text: string): string {
  return text
    .toLowerCase()
    .replace(/[’']/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .replace(/^(so|ok|okay|um|uh|hey|hi|and|but|just|quick question)\s+/, '')
    .replace(/\s+/g, ' ');
}

/**
 * The questions a practice actually asks, in the words they use on the phone.
 *
 * Frequencies are seeded from what a lab's front desk fields all day — "where
 * is it" dwarfs everything else — and are meant to be replaced by the real
 * corpus once the product has one.
 */
export const MULTI_FACT_QUESTIONS: Omit<QuestionTemplate, 'normalized' | 'isSeed'>[] = [
  { question: 'Where is my case?',
    factKeys: ['case.status', 'case.due_date', 'delivery.ship_date',
               'delivery.expected_arrival', 'delivery.tracking_number',
               'case.hold_reason'],
    category: 'status', frequency: 100 },
  { question: 'Will it be here for the appointment?',
    factKeys: ['delivery.expected_arrival', 'case.seat_date', 'case.due_date',
               'case.status'],
    category: 'status', frequency: 94 },
  { question: 'What do you need from me?',
    factKeys: ['case.hold_reason', 'inputs.margin_issue_detail',
               'inputs.bite_registration', 'inputs.opposing_model',
               'rx.stump_shade', 'rx.signed'],
    category: 'blocked', frequency: 88 },
  { question: 'Why is it late?',
    factKeys: ['delivery.delay_reason', 'delivery.revised_due_date',
               'case.hold_reason', 'case.status'],
    category: 'status', frequency: 79 },
  { question: 'What did you make it out of?',
    factKeys: ['rx.material', 'material.primary_brand', 'material.primary_product',
               'material.primary_lot'],
    category: 'material', frequency: 71 },
  { question: 'What shade is it?',
    factKeys: ['rx.shade_body', 'rx.shade_incisal', 'rx.stump_shade',
               'rx.shade_system'],
    category: 'shade', frequency: 76 },
  { question: 'How do I cement it?',
    factKeys: ['material.cement_recommendation', 'material.bonding_protocol',
               'rx.material'],
    category: 'handling', frequency: 68 },
  { question: 'Can I get the material certificate?',
    factKeys: ['material.certificate_on_file', 'material.primary_lot',
               'material.biocompatibility_statement', 'material.alloy_composition'],
    category: 'traceability', frequency: 41 },
  { question: 'Which lot went into this case?',
    factKeys: ['material.primary_lot', 'material.shade_block_lot',
               'material.resin_lot', 'material.primary_expiry'],
    category: 'traceability', frequency: 38 },
  { question: 'Who pays for the remake?',
    factKeys: ['outcome.remake_liability', 'outcome.remake_cause',
               'outcome.remake_evidence', 'outcome.warranty_period'],
    category: 'remake', frequency: 64 },
  { question: 'Why was it remade?',
    factKeys: ['outcome.remake_cause', 'outcome.remake_evidence',
               'outcome.followup_action'],
    category: 'remake', frequency: 61 },
  { question: 'Is it still under warranty?',
    factKeys: ['outcome.warranty_period', 'outcome.warranty_expires',
               'delivery.delivered_at'],
    category: 'remake', frequency: 52 },
  { question: 'How much is this case?',
    factKeys: ['commercial.quoted_price', 'commercial.surcharges',
               'commercial.fee_schedule', 'commercial.invoice_number'],
    category: 'commercial', frequency: 58 },
  { question: 'Did you get everything you need?',
    factKeys: ['inputs.scan_received', 'inputs.bite_registration',
               'inputs.opposing_model', 'inputs.margin_visible', 'rx.signed'],
    category: 'blocked', frequency: 73 },
  { question: 'Is the margin OK?',
    factKeys: ['inputs.margin_visible', 'inputs.margin_issue_detail',
               'qc.margin_integrity'],
    category: 'quality', frequency: 66 },
  { question: 'What torque do I use?',
    factKeys: ['implant.torque_spec', 'implant.screw_part_number',
               'implant.abutment_type'],
    category: 'implant', frequency: 49 },
  { question: 'Which abutment and screw did you use?',
    factKeys: ['implant.abutment_type', 'implant.abutment_part_number',
               'implant.screw_part_number', 'implant.ti_base_part_number'],
    category: 'implant', frequency: 44 },
  { question: 'Where was it made?',
    factKeys: ['reg.outsourced_steps', 'reg.outsourced_to', 'reg.outsource_country'],
    category: 'regulatory', frequency: 33 },
  { question: 'Was this case affected by the recall?',
    factKeys: ['reg.recall_affected', 'material.primary_lot', 'reg.recall_notified_at'],
    category: 'regulatory', frequency: 12 },
  { question: 'What is in the box?',
    factKeys: ['delivery.contents', 'delivery.models_returned',
               'delivery.instructions_enclosed'],
    category: 'delivery', frequency: 37 },
];

export function buildQuestionTemplates(defs: CaseFactDefinition[]): QuestionTemplate[] {
  const byNormalized = new Map<string, QuestionTemplate>();

  const add = (t: QuestionTemplate) => {
    const existing = byNormalized.get(t.normalized);
    if (!existing) { byNormalized.set(t.normalized, t); return; }
    existing.factKeys = [...new Set([...existing.factKeys, ...t.factKeys])];
    existing.frequency = Math.max(existing.frequency, t.frequency);
  };

  for (const def of defs) {
    for (const q of def.answersQuestions) {
      add({
        question: q,
        normalized: normalizeQuestion(q),
        factKeys: [def.key],
        category: def.category,
        frequency: def.answerWeight * 5,
        isSeed: true,
      });
    }
  }
  for (const q of MULTI_FACT_QUESTIONS) {
    add({ ...q, normalized: normalizeQuestion(q.question), isSeed: true });
  }
  return [...byNormalized.values()];
}
