import type { CaseFactDefinition } from '../types.ts';
import { IMPLANT, section, yes } from './_helpers.ts';

const d = section('E', 'implant');

/**
 * Section E — implant componentry.
 *
 * Every fact here is implant-only, which is the clearest case for the
 * applicability predicate: a veneer case scored against abutment torque would
 * sit permanently incomplete with no way to finish. It is also the section
 * where a wrong value is most expensive — an incompatible platform is a
 * surgical problem, not a remake.
 */
const e = (
  key: string, label: string, dataType: CaseFactDefinition['dataType'],
  weight: number, questions: string[], extra: Partial<CaseFactDefinition> = {},
): CaseFactDefinition => d(key, label, dataType, weight, questions,
  { appliesWhen: IMPLANT, safety: 'patient_safety', isDhr: true, ...extra });

export const implantFacts: CaseFactDefinition[] = [
  e('implant.system', 'Implant system', 'text', 10,
    ['what implant system is it', 'which implant brand', 'is it nobel or straumann'],
    { necessity: 'blocking',
      askPractice: 'Which implant system and platform is placed? We cannot order ' +
                   'componentry without it.' }),
  e('implant.platform_diameter', 'Platform diameter', 'dimension', 9,
    ['what platform is it', 'what diameter is the implant'],
    { unit: 'mm', necessity: 'blocking' }),
  e('implant.connection_type', 'Connection type', 'enum', 8,
    ['what connection is it', 'is it internal hex'],
    { enumOptions: ['internal_hex', 'internal_octagon', 'conical', 'external_hex',
                    'tri_channel', 'trilobe', 'other'],
      necessity: 'required' }),
  e('implant.retention', 'Retention type', 'enum', 9,
    ['is it screw retained or cemented', 'how is it retained'],
    { enumOptions: ['screw_retained', 'cement_retained', 'screwmentable'],
      necessity: 'blocking', safety: 'patient_safety',
      askPractice: 'Screw-retained or cement-retained for this case?' }),
  e('implant.abutment_type', 'Abutment type', 'enum', 9,
    ['what abutment are you using', 'is it a custom abutment'],
    { enumOptions: ['stock', 'custom_titanium', 'custom_zirconia', 'ti_base',
                    'multi_unit', 'none'],
      necessity: 'blocking' }),
  e('implant.abutment_part_number', 'Abutment part number', 'text', 7,
    ['what part number is the abutment', 'which abutment did you order'],
    { necessity: 'required' }),
  e('implant.ti_base_part_number', 'Ti-base part number', 'text', 7,
    ['which ti base did you use'],
    { appliesWhen: yes('uses_ti_base'), necessity: 'required' }),
  e('implant.screw_part_number', 'Screw part number', 'text', 8,
    ['which screw comes with it', 'what screw do i need'],
    { necessity: 'required' }),
  e('implant.torque_spec', 'Torque specification', 'torque', 10,
    ['what torque do i use', 'what should i torque it to', 'what is the torque value'],
    { unit: 'Ncm', necessity: 'required',
      helpText: 'Stated as the manufacturer specification for the component ' +
                'supplied, with the source named. The lab reports the spec; it ' +
                'does not instruct the clinician.' }),
  e('implant.angulation', 'Angulation correction', 'text', 7,
    ['how much angulation is there', 'did you have to angle correct'],
    { necessity: 'expected' }),
  e('implant.soft_tissue_model', 'Soft tissue model used', 'boolean', 5,
    ['did you use a gingival mask'],
    { necessity: 'optional', safety: 'remake_risk' }),
  e('implant.scan_body', 'Scan body used', 'text', 6,
    ['which scan body was it', 'what scan body did the office use'],
    { necessity: 'required' }),
  e('implant.analog_part_number', 'Analog part number', 'text', 5,
    ['which analog is in the model'],
    { necessity: 'expected', safety: 'remake_risk' }),
  e('implant.verification_jig', 'Verification jig made', 'boolean', 7,
    ['is there a verification jig', 'did you make a jig'],
    { necessity: 'optional', safety: 'remake_risk' }),
  e('implant.cement_gap_managed', 'Cement margin depth', 'dimension', 8,
    ['how deep is the cement margin', 'will i be able to clean the cement'],
    { unit: 'mm', appliesWhen: { all: [IMPLANT, { field: 'is_screw_retained', op: 'is_false' }] },
      necessity: 'required' }),
];
