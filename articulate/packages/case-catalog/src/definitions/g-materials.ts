import type { CaseFactDefinition } from '../types.ts';
import { APPLIANCE, ALWAYS, oneOf, not, section, yes } from './_helpers.ts';

const d = section('G', 'materials');

/**
 * Section G — materials and lot traceability.
 *
 * This is the section that earns the subscription. When a manufacturer recalls
 * a zirconia lot, a lab that can answer "which patients received it" in three
 * seconds is a different business from one that spends three days in a filing
 * cabinet. Everything here is Device History Record content and is retained
 * accordingly.
 */
const g = (
  key: string, label: string, dataType: CaseFactDefinition['dataType'],
  weight: number, questions: string[], extra: Partial<CaseFactDefinition> = {},
): CaseFactDefinition => d(key, label, dataType, weight, questions,
  { isDhr: true, necessity: 'required', ...extra });

export const materialFacts: CaseFactDefinition[] = [
  g('material.primary_brand', 'Primary material brand', 'text', 8,
    ['what brand of zirconia', 'whose material do you use', 'what brand is it'],
    { necessity: 'blocking', safety: 'patient_safety' }),
  g('material.primary_product', 'Primary material product', 'text', 7,
    ['which product line is it', 'what exact material'],
    { necessity: 'blocking', safety: 'patient_safety' }),
  g('material.primary_lot', 'Primary material lot', 'lot', 9,
    ['what lot number was used', 'can you give me the lot', 'which batch was it'],
    { necessity: 'blocking', safety: 'patient_safety',
      helpText: 'Lot capture is the difference between a three-second recall ' +
                'answer and a three-day one.' }),
  g('material.primary_expiry', 'Primary material expiry', 'date', 7,
    ['was the material in date', 'when does that lot expire'],
    { safety: 'patient_safety' }),
  g('material.shade_block_lot', 'Shade block or ingot lot', 'lot', 7,
    ['what lot was the ingot', 'which block did you use'],
    { appliesWhen: oneOf('material_class', ['glass_ceramic', 'zirconia']),
      safety: 'patient_safety' }),
  g('material.stain_glaze_lot', 'Stain and glaze lot', 'lot', 5,
    ['what glaze did you use'],
    { appliesWhen: not(APPLIANCE), necessity: 'expected', safety: 'remake_risk' }),
  g('material.liner_opaque_lot', 'Liner or opaque lot', 'lot', 5,
    ['what opaque did you use'],
    { appliesWhen: oneOf('material_class', ['pfm']), necessity: 'expected',
      safety: 'remake_risk' }),
  g('material.alloy_composition', 'Alloy composition', 'text', 9,
    ['what is the alloy', 'what metals are in it', 'is there nickel in it'],
    { appliesWhen: oneOf('material_class', ['pfm', 'cast_metal', 'framework']),
      necessity: 'blocking', safety: 'patient_safety',
      helpText: 'A patient asking "is there nickel in this?" is asking a safety ' +
                'question. The answer comes from the certificate, not from ' +
                'what the alloy usually contains.' }),
  g('material.noble_content', 'Noble metal content', 'text', 7,
    ['what is the gold content', 'is it high noble'],
    { appliesWhen: oneOf('material_class', ['pfm', 'cast_metal']),
      safety: 'commercial' }),
  g('material.certificate_on_file', 'Material certificate on file', 'boolean', 8,
    ['can i get the material certificate', 'do you have documentation for the material',
     'can you send me the material cert'],
    { necessity: 'required', safety: 'patient_safety' }),
  g('material.biocompatibility_statement', 'Biocompatibility statement', 'text', 8,
    ['is it biocompatible', 'is there a biocompatibility statement'],
    { safety: 'patient_safety' }),
  g('material.resin_lot', 'Print resin lot', 'lot', 7,
    ['which resin lot was it', 'what resin did you print in'],
    { appliesWhen: yes('is_printed'), safety: 'patient_safety' }),
  g('material.resin_class', 'Resin regulatory class', 'text', 7,
    ['is the resin approved for intraoral use', 'is it a class iia resin'],
    { appliesWhen: yes('is_printed'), safety: 'patient_safety' }),
  g('material.acrylic_lot', 'Acrylic lot', 'lot', 7,
    ['what acrylic lot was used'],
    { appliesWhen: oneOf('material_class', ['acrylic']), safety: 'patient_safety' }),
  g('material.denture_tooth_lot', 'Denture tooth lot', 'lot', 6,
    ['what lot are the teeth from'],
    { appliesWhen: oneOf('material_class', ['acrylic']), necessity: 'expected',
      safety: 'patient_safety' }),
  g('material.cement_recommendation', 'Recommended cementation', 'text', 9,
    ['what cement should i use', 'how do i cement it', 'can i use resin cement'],
    { necessity: 'expected', safety: 'patient_safety',
      helpText: 'Given as the material manufacturer\'s instruction for use, ' +
                'named as such. Which cement to use in a given mouth is a ' +
                'clinical decision the lab does not make.' }),
  g('material.bonding_protocol', 'Manufacturer bonding protocol', 'text', 8,
    ['how do i bond it', 'do i etch it', 'what surface treatment does it need'],
    { necessity: 'expected', safety: 'patient_safety' }),
  g('material.supplier', 'Material supplier', 'text', 3,
    ['where do you buy your material'],
    { visibility: 'lab_only', necessity: 'optional', safety: 'commercial' }),
  g('material.received_date', 'Material lot received', 'date', 3,
    ['when did you receive that lot'],
    { visibility: 'lab_only', necessity: 'optional', safety: 'informational' }),
];
