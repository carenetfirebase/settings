import type { CaseFactDefinition } from '../types.ts';
import { section, yes } from './_helpers.ts';

const d = section('J', 'outcome');

/**
 * Section J — what happened in the mouth.
 *
 * Labs lose real money to remakes and mostly cannot say why. Cause codes that
 * are recorded per case, attributed, and auditable turn "your crowns don't fit"
 * into a number both parties can look at — which is a better conversation for
 * everyone, including the lab that turns out to be right.
 */
export const outcomeFacts: CaseFactDefinition[] = [
  d('outcome.seated_at', 'Seated', 'date', 7,
    ['did it get seated', 'when was it fitted'],
    { necessity: 'expected', safety: 'commercial' }),
  d('outcome.fit_reported', 'Fit as reported by the practice', 'enum', 9,
    ['how did it fit', 'did it seat ok'],
    { enumOptions: ['excellent', 'acceptable', 'adjusted_chairside', 'poor', 'did_not_seat'],
      necessity: 'expected', safety: 'remake_risk' }),
  d('outcome.adjustment_notes', 'Chairside adjustments', 'text', 8,
    ['what did you have to adjust', 'how much adjustment was needed'],
    { necessity: 'optional', safety: 'remake_risk' }),
  d('outcome.shade_accepted', 'Shade accepted', 'boolean', 9,
    ['was the shade right', 'did the patient like the shade'],
    { necessity: 'expected', safety: 'remake_risk' }),
  d('outcome.remake_requested', 'Remake requested', 'boolean', 10,
    ['is this being remade', 'are you remaking it', 'did i ask for a remake'],
    { necessity: 'expected', safety: 'commercial' }),
  d('outcome.remake_cause', 'Remake cause', 'enum', 10,
    ['why was it remade', 'what went wrong', 'whose fault was the remake'],
    { enumOptions: ['lab_fit', 'lab_shade', 'lab_contact', 'lab_occlusion',
                    'lab_aesthetic', 'lab_damage_in_transit',
                    'clinical_prep', 'clinical_impression', 'clinical_margin',
                    'clinical_bite_record', 'clinical_change_of_plan',
                    'patient_preference', 'material_defect', 'undetermined'],
      appliesWhen: yes('is_remake'), necessity: 'blocking', safety: 'commercial',
      helpText: 'Recorded with the evidence that supports it. "Undetermined" is ' +
                'an honest and available answer; guessing an attribution to win ' +
                'an argument corrupts the only dataset that could settle it.' }),
  d('outcome.remake_liability', 'Remake at whose cost', 'enum', 10,
    ['who pays for the remake', 'am i being charged for this', 'is the remake free'],
    { enumOptions: ['lab_no_charge', 'practice_charged', 'shared', 'warranty',
                    'under_review'],
      appliesWhen: yes('is_remake'), necessity: 'blocking', safety: 'commercial' }),
  d('outcome.remake_evidence', 'Remake evidence', 'text', 8,
    ['what is the evidence for that', 'how did you decide the cause'],
    { appliesWhen: yes('is_remake'), necessity: 'required', safety: 'commercial' }),
  d('outcome.warranty_period', 'Warranty period', 'text', 9,
    ['what is the warranty', 'how long is it guaranteed for', 'is it under warranty'],
    { necessity: 'required', safety: 'commercial' }),
  d('outcome.warranty_expires', 'Warranty expiry', 'date', 8,
    ['when does the warranty run out', 'is it still in warranty'],
    { necessity: 'required', safety: 'commercial' }),
  d('outcome.complaint_logged', 'Complaint logged', 'boolean', 8,
    ['did you log my complaint', 'is there a record of the issue'],
    { necessity: 'expected', safety: 'patient_safety', isDhr: true }),
  d('outcome.complaint_detail', 'Complaint detail', 'text', 8,
    ['what was the complaint'],
    { necessity: 'expected', safety: 'patient_safety', isDhr: true }),
  d('outcome.followup_action', 'Follow-up action taken', 'text', 8,
    ['what are you doing about it', 'how are you fixing it'],
    { necessity: 'expected', safety: 'commercial' }),
];
