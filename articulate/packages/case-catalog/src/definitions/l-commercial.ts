import type { CaseFactDefinition } from '../types.ts';
import { section, yes } from './_helpers.ts';

const d = section('L', 'commercial');

/** Section L — money. Visible to the practice where it concerns them, not otherwise. */
export const commercialFacts: CaseFactDefinition[] = [
  d('commercial.quoted_price', 'Quoted price', 'money', 9,
    ['how much is it', 'what does it cost', 'what will you charge me'],
    { necessity: 'required', safety: 'commercial' }),
  d('commercial.fee_schedule', 'Fee schedule applied', 'text', 6,
    ['which price list is that', 'what schedule am i on'],
    { necessity: 'expected', safety: 'commercial' }),
  d('commercial.surcharges', 'Surcharges', 'text', 8,
    ['why is it more than usual', 'what are the extra charges', 'is there a rush fee'],
    { necessity: 'expected', safety: 'commercial' }),
  d('commercial.invoice_number', 'Invoice number', 'text', 6,
    ['what is the invoice number', 'has it been invoiced'],
    { necessity: 'expected', safety: 'commercial' }),
  d('commercial.invoiced_at', 'Invoiced', 'date', 5,
    ['when was it invoiced'],
    { necessity: 'optional', safety: 'commercial' }),
  d('commercial.billing_code', 'Billing code', 'text', 7,
    ['what code do i bill this under', 'what is the lab code'],
    { necessity: 'expected', safety: 'commercial',
      helpText: 'The lab states the code it billed under. Which code the practice ' +
                'submits to an insurer is the practice\'s decision and their ' +
                'liability, and the AI does not advise on it.' }),
  d('commercial.material_cost', 'Material cost', 'money', 2,
    ['what did the material cost you'],
    { visibility: 'lab_only', necessity: 'optional', safety: 'commercial' }),
  d('commercial.margin', 'Case margin', 'money', 2,
    ['what is the margin on this case'],
    { visibility: 'lab_only', necessity: 'optional', safety: 'commercial' }),
  d('commercial.remake_cost_absorbed', 'Remake cost absorbed', 'money', 3,
    ['what did the remake cost the lab'],
    { appliesWhen: yes('is_remake'), visibility: 'lab_only', necessity: 'optional',
      safety: 'commercial' }),
  d('commercial.payment_status', 'Payment status', 'enum', 4,
    ['has it been paid', 'is there anything outstanding'],
    { enumOptions: ['unbilled', 'invoiced', 'paid', 'overdue', 'credited'],
      necessity: 'optional', safety: 'commercial' }),
  d('commercial.credit_issued', 'Credit issued', 'money', 8,
    ['did you credit me', 'was a credit issued for this'],
    { necessity: 'optional', safety: 'commercial' }),
];
