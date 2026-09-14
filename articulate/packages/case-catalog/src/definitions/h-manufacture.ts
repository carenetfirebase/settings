import type { CaseFactDefinition } from '../types.ts';
import { APPLIANCE, not, oneOf, section, yes } from './_helpers.ts';

const d = section('H', 'manufacture');

/**
 * Section H — how it was actually made.
 *
 * The Device History Record in the narrow sense: who did what, on which
 * machine, to which program, and who checked it. A lab that records this only
 * on paper cannot answer a complaint, and a lab that records nothing cannot
 * defend one.
 */
const h = (
  key: string, label: string, dataType: CaseFactDefinition['dataType'],
  weight: number, questions: string[], extra: Partial<CaseFactDefinition> = {},
): CaseFactDefinition => d(key, label, dataType, weight, questions,
  { isDhr: true, necessity: 'required', safety: 'informational', ...extra });

export const manufactureFacts: CaseFactDefinition[] = [
  h('manufacture.method', 'Fabrication method', 'enum', 6,
    ['how was it made', 'is it milled or printed', 'did you press it'],
    { enumOptions: ['milled', 'printed', 'pressed', 'cast', 'layered', 'packed',
                    'thermoformed'],
      necessity: 'blocking' }),
  h('manufacture.mill', 'Mill', 'text', 3,
    ['which mill was it cut on'], { necessity: 'expected' }),
  h('manufacture.mill_program', 'Mill program', 'text', 3,
    ['what milling program'], { necessity: 'optional' }),
  h('manufacture.bur_set_changed', 'Tool set condition logged', 'boolean', 3,
    ['were the burs fresh'],
    { visibility: 'lab_only', necessity: 'optional', safety: 'remake_risk' }),
  h('manufacture.printer', 'Printer', 'text', 3,
    ['which printer was it made on'],
    { appliesWhen: yes('is_printed'), necessity: 'expected' }),
  h('manufacture.print_orientation', 'Print orientation and supports', 'text', 3,
    ['how was it oriented on the plate'],
    { appliesWhen: yes('is_printed'), visibility: 'lab_only', necessity: 'optional' }),
  h('manufacture.post_cure', 'Post-cure cycle', 'text', 6,
    ['how was it post cured', 'was it fully cured'],
    { appliesWhen: yes('is_printed'), safety: 'patient_safety' }),
  h('manufacture.sintering_furnace', 'Sintering furnace', 'text', 4,
    ['which furnace did it sinter in'],
    { appliesWhen: oneOf('material_class', ['zirconia']) }),
  h('manufacture.sintering_program', 'Sintering program', 'text', 7,
    ['what sintering cycle did you run', 'was it a speed sinter'],
    { appliesWhen: oneOf('material_class', ['zirconia']), safety: 'patient_safety',
      helpText: 'A speed-sintered zirconia is not the same device as a ' +
                'conventionally sintered one. The cycle is recorded, not assumed.' }),
  h('manufacture.firing_cycles', 'Firing cycles', 'text', 6,
    ['how many times was it fired', 'what firing schedule'],
    { appliesWhen: not(APPLIANCE), necessity: 'expected', safety: 'remake_risk' }),
  h('manufacture.press_furnace', 'Press furnace and program', 'text', 4,
    ['how was it pressed'],
    { appliesWhen: oneOf('material_class', ['glass_ceramic']), necessity: 'optional' }),
  h('manufacture.casting_details', 'Casting details', 'text', 4,
    ['how was it cast'],
    { appliesWhen: oneOf('material_class', ['cast_metal', 'framework']),
      necessity: 'optional' }),
  h('manufacture.technicians', 'Technicians involved', 'text', 5,
    ['who worked on it', 'who built it'], { necessity: 'required' }),
  h('manufacture.started_at', 'Production started', 'datetime', 6,
    ['when did you start it'], { safety: 'commercial' }),
  h('manufacture.completed_at', 'Production completed', 'datetime', 8,
    ['when was it finished', 'is it finished'], { safety: 'commercial' }),
  h('manufacture.time_minutes', 'Bench time', 'number', 2,
    ['how long did it take'],
    { unit: 'minutes', visibility: 'lab_only', necessity: 'optional',
      safety: 'commercial' }),
  h('qc.inspected_by', 'QC inspector', 'text', 6,
    ['who checked it', 'did anyone inspect it'], { safety: 'patient_safety' }),
  h('qc.inspected_at', 'QC completed', 'datetime', 6,
    ['when was it checked'], { safety: 'patient_safety' }),
  h('qc.fit_on_model', 'Fit verified on model', 'boolean', 9,
    ['did it fit on the model', 'did you check the fit'],
    { necessity: 'required', safety: 'remake_risk' }),
  h('qc.margin_integrity', 'Margin integrity check', 'enum', 9,
    ['how are the margins', 'are the margins closed'],
    { enumOptions: ['pass', 'minor_adjustment_made', 'fail_remade'],
      necessity: 'required', safety: 'remake_risk' }),
  h('qc.occlusion_check', 'Occlusion verified', 'enum', 8,
    ['did you check the bite', 'how is the occlusion'],
    { enumOptions: ['pass', 'adjusted', 'fail_remade'], necessity: 'required',
      safety: 'remake_risk' }),
  h('qc.shade_verified_under', 'Shade verified under', 'enum', 7,
    ['what light did you check the shade under', 'how did you verify the shade'],
    { enumOptions: ['corrected_daylight', 'daylight', 'operatory', 'photo_comparison'],
      appliesWhen: not(APPLIANCE), necessity: 'expected', safety: 'remake_risk' }),
  h('qc.photos_taken', 'QC photos on file', 'boolean', 7,
    ['do you have photos of it', 'can i see a picture before it ships'],
    { necessity: 'expected', safety: 'commercial' }),
  h('qc.disinfected', 'Disinfection before dispatch', 'boolean', 8,
    ['was it disinfected', 'is it clean to try in'],
    { necessity: 'required', safety: 'patient_safety',
      helpText: 'A device going into a mouth leaves the lab disinfected and it ' +
                'is recorded. This is an infection-control requirement, not ' +
                'housekeeping.' }),
  h('qc.disinfection_method', 'Disinfection method', 'text', 5,
    ['how do you disinfect', 'what do you use to disinfect'],
    { necessity: 'required', safety: 'patient_safety' }),
];
