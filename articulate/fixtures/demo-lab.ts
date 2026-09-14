import { InMemoryCaseStore } from '../packages/truth-engine/src/store.ts';
import type { CaseRecord } from '../packages/truth-engine/src/store.ts';
import type { CaseClaim } from '../packages/truth-engine/src/types.ts';

export const LAB_NAME = 'Meridian Dental Studio';
export const DEMO_PRACTICE_ID = 'practice-okafor';

/**
 * A small lab's Tuesday.
 *
 * Eight cases in the states a real bench actually holds them in, seeded through
 * the same claim → confirm path a live case takes rather than written straight
 * into resolved facts. The imperfections are deliberate and each one exists to
 * exercise a decision the product has to get right:
 *
 *   24418  the prescription and the scan disagree about which tooth — a hard
 *          stop, and the reason the two-tier fact model is not academic
 *   24423  blocked on a stump shade nobody sent, which is the single most
 *          common preventable remake
 *   24401  delivered with zirconia lot ZR-24-0881, which is about to be recalled
 *   24390  remade, cause attributed, with the evidence attached
 */
export function buildDemoLab(): InMemoryCaseStore {
  const store = new InMemoryCaseStore();
  for (const seed of CASES) seedCase(store, seed);
  return store;
}

type Seed = {
  id: string;
  caseNumber: string;
  practiceId: string;
  practiceName: string;
  doctorName: string;
  patientInitials: string;
  receivedAt: string;
  dueDate: string;
  seatDate?: string;
  status: string;
  context: Record<string, unknown>;
  facts: [string, string][];
  unknowns?: [string, 'practice_has_not_supplied' | 'not_recorded_at_the_time' |
                     'awaiting_supplier' | 'will_follow_up'][];
  conflicting?: { factKey: string; values: { value: string; source: CaseClaim['source'];
                                             doc?: string; page?: number; snippet?: string }[] };
  materials?: { role: 'primary' | 'ingot' | 'stain_glaze' | 'resin' | 'acrylic' |
                       'alloy' | 'teeth';
                brand: string; product: string; lot: string; expiry?: string }[];
  steps?: { step: string; by: string; at: string; equipment?: string; program?: string }[];
  messages?: { direction: 'to_practice' | 'from_practice'; body: string; at: string }[];
};

const OKAFOR = {
  practiceId: DEMO_PRACTICE_ID,
  practiceName: 'Riverbend Dental',
  doctorName: 'Dr. Okafor',
};
const HALE = {
  practiceId: 'practice-hale',
  practiceName: 'Hale Family Dentistry',
  doctorName: 'Dr. Hale',
};
const VOSS = {
  practiceId: 'practice-voss',
  practiceName: 'Voss Implant Centre',
  doctorName: 'Dr. Voss',
};

const CASES: Seed[] = [
  {
    id: 'case-24418', caseNumber: '24418', ...OKAFOR, patientInitials: 'M.D.',
    receivedAt: '2026-09-11T09:20:00Z', dueDate: '2026-09-18', seatDate: '2026-09-21',
    status: 'on_hold_pending_practice',
    context: {
      restoration_type: 'crown', material_class: 'zirconia', is_digital: true,
      is_on_hold: true, is_remake: false, is_delayed: false, is_outsourced: false,
      is_printed: false, is_screw_retained: false, uses_ti_base: false,
      tooth_notation: 'universal',
    },
    facts: [
      ['case.number', '24418'],
      ['case.practice', 'Riverbend Dental'],
      ['case.doctor', 'Dr. Okafor'],
      ['case.patient_initials', 'M.D.'],
      ['case.received_at', '2026-09-11T09:20:00Z'],
      ['case.intake_channel', 'digital scan'],
      ['case.due_date', '2026-09-18'],
      ['case.seat_date', '2026-09-21'],
      ['case.status', 'on hold pending practice'],
      ['case.hold_reason',
       'The prescription and the scan file disagree on the tooth number, so we ' +
       'have stopped the case until you confirm which one is correct.'],
      ['case.assigned_technician', 'Priya R.'],
      ['rx.restoration_type', 'crown'],
      ['rx.tooth_notation', 'universal'],
      ['rx.arch', 'mandibular'],
      ['rx.unit_count', '1'],
      ['rx.material', 'zirconia multilayer'],
      ['rx.shade_system', 'vita classical'],
      ['rx.shade_body', 'A2'],
      ['rx.stump_shade', 'B1'],
      ['rx.signed', 'yes'],
      ['rx.received_document', 'Rx-24418.pdf'],
      ['rx.special_instructions',
       'Light contacts please, patient has had tight contacts on the last two units.'],
      ['rx.opposing_dentition', 'natural'],
      ['inputs.scan_received', 'yes'],
      ['inputs.scanner', 'itero'],
      ['inputs.file_format', 'stl'],
      ['inputs.scan_quality', 'good'],
      ['inputs.margin_visible', 'yes'],
      ['inputs.bite_registration', 'yes'],
      ['inputs.bite_usable', 'yes'],
      ['inputs.opposing_model', 'yes'],
      ['commercial.quoted_price', '$189.00'],
      ['outcome.warranty_period', '5 years against fracture and fit'],
    ],
    conflicting: {
      factKey: 'rx.tooth_numbers',
      values: [
        { value: '#19', source: 'rx_document', doc: 'Rx-24418.pdf', page: 1,
          snippet: 'Unit 1: #19 — full contour zirconia crown' },
        { value: '#20', source: 'scan_metadata',
          snippet: 'iTero export: prepared tooth 20, adjacent 19 unprepared' },
      ],
    },
    messages: [
      { direction: 'to_practice', at: '2026-09-11T10:02:00Z',
        body: 'Case 24418 — your Rx specifies #19 but the scan shows the ' +
              'preparation on #20. We have held the case rather than guess. ' +
              'Which is correct?' },
    ],
  },
  {
    id: 'case-24423', caseNumber: '24423', ...OKAFOR, patientInitials: 'T.W.',
    receivedAt: '2026-09-12T14:05:00Z', dueDate: '2026-09-19', seatDate: '2026-09-23',
    status: 'on_hold_pending_practice',
    context: {
      restoration_type: 'veneer', material_class: 'glass_ceramic', is_digital: true,
      is_on_hold: true, is_remake: false, is_delayed: false, is_outsourced: false,
      is_printed: false, is_screw_retained: false, uses_ti_base: false,
      tooth_notation: 'universal',
    },
    facts: [
      ['case.number', '24423'],
      ['case.practice', 'Riverbend Dental'],
      ['case.doctor', 'Dr. Okafor'],
      ['case.patient_initials', 'T.W.'],
      ['case.received_at', '2026-09-12T14:05:00Z'],
      ['case.due_date', '2026-09-19'],
      ['case.seat_date', '2026-09-23'],
      ['case.status', 'on hold pending practice'],
      ['case.hold_reason',
       'We need the stump shade before we can match a translucent material.'],
      ['case.assigned_technician', 'Marcus L.'],
      ['case.intake_channel', 'digital scan'],
      ['rx.restoration_type', 'veneer'],
      ['rx.tooth_numbers', '#8, #9'],
      ['rx.tooth_notation', 'universal'],
      ['rx.arch', 'maxillary'],
      ['rx.unit_count', '2'],
      ['rx.material', 'lithium disilicate'],
      ['rx.shade_system', 'vita classical'],
      ['rx.shade_body', 'B1'],
      ['rx.signed', 'yes'],
      ['rx.received_document', 'Rx-24423.pdf'],
      ['rx.shade_photos_provided', 'yes'],
      ['rx.opposing_dentition', 'natural'],
      ['inputs.scan_received', 'yes'],
      ['inputs.scanner', 'trios'],
      ['inputs.scan_quality', 'good'],
      ['inputs.margin_visible', 'yes'],
      ['inputs.bite_registration', 'yes'],
      ['inputs.opposing_model', 'yes'],
      ['commercial.quoted_price', '$412.00'],
    ],
    unknowns: [['rx.stump_shade', 'practice_has_not_supplied']],
    messages: [
      { direction: 'to_practice', at: '2026-09-12T14:40:00Z',
        body: 'Case 24423 — lithium disilicate veneers will read the prepared ' +
              'tooth through the restoration. Could you send the stump shade?' },
    ],
  },
  {
    id: 'case-24401', caseNumber: '24401', ...HALE, patientInitials: 'R.S.',
    receivedAt: '2026-09-02T08:30:00Z', dueDate: '2026-09-09', status: 'seated',
    context: {
      restoration_type: 'crown', material_class: 'zirconia', is_digital: true,
      is_on_hold: false, is_remake: false, is_delayed: false, is_outsourced: false,
      is_printed: false, is_screw_retained: false, uses_ti_base: false,
      tooth_notation: 'universal',
    },
    facts: [
      ['case.number', '24401'], ['case.practice', 'Hale Family Dentistry'],
      ['case.doctor', 'Dr. Hale'], ['case.patient_initials', 'R.S.'],
      ['case.received_at', '2026-09-02T08:30:00Z'], ['case.due_date', '2026-09-09'],
      ['case.status', 'seated'], ['case.assigned_technician', 'Priya R.'],
      ['case.intake_channel', 'digital scan'],
      ['rx.restoration_type', 'crown'], ['rx.tooth_numbers', '#30'],
      ['rx.tooth_notation', 'universal'], ['rx.arch', 'mandibular'],
      ['rx.unit_count', '1'], ['rx.material', 'zirconia 4y'],
      ['rx.shade_system', 'vita classical'], ['rx.shade_body', 'A3'],
      ['rx.stump_shade', 'A3'], ['rx.signed', 'yes'],
      ['rx.received_document', 'Rx-24401.pdf'], ['rx.opposing_dentition', 'natural'],
      ['inputs.scan_received', 'yes'], ['inputs.scanner', 'primescan'],
      ['inputs.scan_quality', 'good'], ['inputs.margin_visible', 'yes'],
      ['inputs.bite_registration', 'yes'], ['inputs.opposing_model', 'yes'],
      ['design.margin_design', 'chamfer'], ['design.cement_space', '60 µm'],
      ['design.occlusal_clearance', '1.4 mm'],
      ['design.minimum_thickness_required', '0.8 mm'],
      ['design.designer', 'Marcus L.'], ['design.software', 'exocad'],
      ['material.primary_brand', 'Katana'],
      ['material.primary_product', 'Katana Zirconia UTML'],
      ['material.primary_lot', 'ZR-24-0881'],
      ['material.primary_expiry', '2028-04-30'],
      ['material.certificate_on_file', 'yes'],
      ['material.cement_recommendation',
       'Manufacturer instructs self-adhesive resin cement after alumina ' +
       'air-abrasion at 0.2 MPa.'],
      ['manufacture.method', 'milled'], ['manufacture.mill', 'DWX-52D'],
      ['manufacture.sintering_furnace', 'Dekema Austromat 674'],
      ['manufacture.sintering_program', 'Conventional 8h cycle'],
      ['manufacture.technicians', 'Priya R.'],
      ['manufacture.completed_at', '2026-09-05T16:10:00Z'],
      ['qc.inspected_by', 'Dana K.'], ['qc.fit_on_model', 'yes'],
      ['qc.margin_integrity', 'pass'], ['qc.occlusion_check', 'pass'],
      ['qc.disinfected', 'yes'],
      ['qc.disinfection_method', 'Sodium hypochlorite 0.5%, 10 minutes, rinsed and dried'],
      ['delivery.ship_date', '2026-09-06T11:00:00Z'], ['delivery.carrier', 'UPS'],
      ['delivery.tracking_number', '1Z999AA10123456784'],
      ['delivery.expected_arrival', '2026-09-08'],
      ['delivery.delivered_at', '2026-09-08T10:12:00Z'],
      ['delivery.contents', 'Crown, working model, cementation instructions'],
      ['delivery.instructions_enclosed', 'yes'],
      ['outcome.seated_at', '2026-09-09'], ['outcome.fit_reported', 'excellent'],
      ['outcome.shade_accepted', 'yes'],
      ['outcome.warranty_period', '5 years against fracture and fit'],
      ['outcome.warranty_expires', '2031-09-09'],
      ['reg.device_statement_issued', 'yes'], ['reg.prescriber_on_record', 'yes'],
      ['reg.lot_traceable', 'yes'],
      ['reg.outsourced_steps', 'None — fabricated entirely in house.'],
      ['commercial.quoted_price', '$189.00'],
      ['commercial.invoice_number', 'INV-88214'],
    ],
    materials: [
      { role: 'primary', brand: 'Katana', product: 'Katana Zirconia UTML',
        lot: 'ZR-24-0881', expiry: '2028-04-30' },
      { role: 'stain_glaze', brand: 'Ivoclar', product: 'IPS e.max Ceram Glaze',
        lot: 'GL-24-3310' },
    ],
    steps: [
      { step: 'Design', by: 'Marcus L.', at: '2026-09-03T10:00:00Z', equipment: 'exocad' },
      { step: 'Mill', by: 'Priya R.', at: '2026-09-04T09:15:00Z', equipment: 'DWX-52D' },
      { step: 'Sinter', by: 'Priya R.', at: '2026-09-04T18:00:00Z',
        equipment: 'Dekema Austromat 674', program: 'Conventional 8h' },
      { step: 'Stain and glaze', by: 'Priya R.', at: '2026-09-05T13:20:00Z' },
      { step: 'QC', by: 'Dana K.', at: '2026-09-05T16:10:00Z' },
      { step: 'Ship', by: 'Front desk', at: '2026-09-06T11:00:00Z', equipment: 'UPS' },
    ],
  },
  {
    id: 'case-24430', caseNumber: '24430', ...VOSS, patientInitials: 'K.A.',
    receivedAt: '2026-09-12T11:00:00Z', dueDate: '2026-09-22', status: 'in_production',
    context: {
      restoration_type: 'implant_crown', material_class: 'zirconia', is_digital: true,
      is_on_hold: false, is_remake: false, is_delayed: false, is_outsourced: false,
      is_printed: false, is_screw_retained: true, uses_ti_base: true,
      tooth_notation: 'universal',
    },
    facts: [
      ['case.number', '24430'], ['case.practice', 'Voss Implant Centre'],
      ['case.doctor', 'Dr. Voss'], ['case.patient_initials', 'K.A.'],
      ['case.received_at', '2026-09-12T11:00:00Z'], ['case.due_date', '2026-09-22'],
      ['case.status', 'in production'], ['case.assigned_technician', 'Dana K.'],
      ['case.intake_channel', 'digital scan'],
      ['rx.restoration_type', 'implant crown'], ['rx.tooth_numbers', '#14'],
      ['rx.tooth_notation', 'universal'], ['rx.arch', 'maxillary'],
      ['rx.unit_count', '1'], ['rx.material', 'zirconia 4y'],
      ['rx.shade_system', 'vita classical'], ['rx.shade_body', 'A2'],
      ['rx.stump_shade', 'A3'], ['rx.signed', 'yes'],
      ['rx.received_document', 'Rx-24430.pdf'], ['rx.opposing_dentition', 'natural'],
      ['inputs.scan_received', 'yes'], ['inputs.scanner', 'medit'],
      ['inputs.scan_quality', 'good'], ['inputs.margin_visible', 'yes'],
      ['inputs.bite_registration', 'yes'], ['inputs.opposing_model', 'yes'],
      ['implant.system', 'Straumann BLX'], ['implant.platform_diameter', '4.5 mm'],
      ['implant.connection_type', 'conical'], ['implant.retention', 'screw retained'],
      ['implant.abutment_type', 'ti base'],
      ['implant.abutment_part_number', 'BLX-VS-45'],
      ['implant.ti_base_part_number', 'TB-BLX-45-C'],
      ['implant.screw_part_number', 'SCS-BLX-01'],
      ['implant.torque_spec', '35 Ncm'],
      ['implant.scan_body', 'Straumann CARES Mono Scanbody BLX'],
      ['design.screw_access_position', 'Palatal, within the central fossa'],
      ['design.designer', 'Dana K.'], ['design.software', '3shape'],
      ['commercial.quoted_price', '$465.00'],
      ['outcome.warranty_period', '5 years against fracture and fit'],
    ],
    materials: [
      { role: 'primary', brand: 'Katana', product: 'Katana Zirconia STML',
        lot: 'ZR-24-0902', expiry: '2028-06-30' },
    ],
    steps: [
      { step: 'Design', by: 'Dana K.', at: '2026-09-13T09:30:00Z', equipment: '3Shape' },
    ],
  },
  {
    id: 'case-24390', caseNumber: '24390', ...HALE, patientInitials: 'J.P.',
    receivedAt: '2026-08-25T09:00:00Z', dueDate: '2026-09-01', status: 'remake_in_progress',
    context: {
      restoration_type: 'crown', material_class: 'glass_ceramic', is_digital: true,
      is_on_hold: false, is_remake: true, is_delayed: false, is_outsourced: false,
      is_printed: false, is_screw_retained: false, uses_ti_base: false,
      tooth_notation: 'universal',
    },
    facts: [
      ['case.number', '24390'], ['case.practice', 'Hale Family Dentistry'],
      ['case.doctor', 'Dr. Hale'], ['case.patient_initials', 'J.P.'],
      ['case.received_at', '2026-08-25T09:00:00Z'], ['case.due_date', '2026-09-01'],
      ['case.status', 'remake in progress'], ['case.assigned_technician', 'Marcus L.'],
      ['case.intake_channel', 'digital scan'],
      ['rx.restoration_type', 'crown'], ['rx.tooth_numbers', '#12'],
      ['rx.tooth_notation', 'universal'], ['rx.arch', 'maxillary'],
      ['rx.unit_count', '1'], ['rx.material', 'lithium disilicate'],
      ['rx.shade_system', 'vita classical'], ['rx.shade_body', 'A1'],
      ['rx.signed', 'yes'], ['rx.received_document', 'Rx-24390.pdf'],
      ['rx.opposing_dentition', 'natural'],
      ['inputs.scan_received', 'yes'], ['inputs.scanner', 'itero'],
      ['inputs.scan_quality', 'marginal'], ['inputs.margin_visible', 'no'],
      ['inputs.margin_issue_detail',
       'Distal margin obscured by tissue and blood in the original scan.'],
      ['inputs.rescan_requested_at', '2026-09-04T09:00:00Z'],
      ['inputs.rescan_received_at', '2026-09-05T15:30:00Z'],
      ['inputs.bite_registration', 'yes'], ['inputs.opposing_model', 'yes'],
      ['outcome.seated_at', '2026-09-03'], ['outcome.fit_reported', 'did not seat'],
      ['outcome.remake_requested', 'yes'],
      ['outcome.remake_cause', 'clinical margin'],
      ['outcome.remake_liability', 'shared'],
      ['outcome.remake_evidence',
       'Original scan shows the distal margin obscured; the lab flagged it on ' +
       '25 August and proceeded on the practice\'s instruction. Rescan received ' +
       '5 September is clean.'],
      ['outcome.warranty_period', '5 years against fracture and fit'],
      ['outcome.complaint_logged', 'yes'],
      ['outcome.complaint_detail', 'Crown did not seat fully at the distal margin.'],
      ['outcome.followup_action',
       'Remaking at no charge for the lab portion; rescan supplied by the practice.'],
      ['commercial.quoted_price', '$236.00'],
      ['commercial.credit_issued', '$118.00'],
    ],
    messages: [
      { direction: 'to_practice', at: '2026-08-25T11:30:00Z',
        body: 'Case 24390 — the distal margin is not readable on this scan. We ' +
              'can proceed on our best interpretation or wait for a rescan. ' +
              'Which would you prefer?' },
      { direction: 'from_practice', at: '2026-08-25T12:05:00Z',
        body: 'Go ahead, patient is travelling.' },
    ],
  },
  {
    id: 'case-24428', caseNumber: '24428', ...OKAFOR, patientInitials: 'L.N.',
    receivedAt: '2026-09-12T16:40:00Z', dueDate: '2026-09-26', status: 'in_design',
    context: {
      restoration_type: 'partial_denture', material_class: 'framework',
      is_digital: false, is_on_hold: false, is_remake: false, is_delayed: false,
      is_outsourced: false, is_printed: false, is_screw_retained: false,
      uses_ti_base: false, tooth_notation: 'universal',
    },
    facts: [
      ['case.number', '24428'], ['case.practice', 'Riverbend Dental'],
      ['case.doctor', 'Dr. Okafor'], ['case.patient_initials', 'L.N.'],
      ['case.received_at', '2026-09-12T16:40:00Z'], ['case.due_date', '2026-09-26'],
      ['case.status', 'in design'], ['case.assigned_technician', 'Marcus L.'],
      ['case.intake_channel', 'physical impression'],
      ['rx.restoration_type', 'partial denture'],
      ['rx.tooth_numbers', '#4, #5, #12, #13'], ['rx.tooth_notation', 'universal'],
      ['rx.arch', 'maxillary'], ['rx.unit_count', '4'],
      ['rx.material', 'cobalt chrome'], ['rx.shade_system', 'vita classical'],
      ['rx.shade_body', 'A2'], ['rx.signed', 'yes'],
      ['rx.received_document', 'Rx-24428.pdf'], ['rx.try_in_requested', 'yes'],
      ['rx.opposing_dentition', 'natural'],
      ['inputs.impression_type', 'pvs'], ['inputs.impression_quality', 'good'],
      ['inputs.bite_registration', 'yes'], ['inputs.opposing_model', 'yes'],
      ['inputs.model_received', 'yes'],
      ['removable.stage', 'framework try in'],
      ['removable.framework_alloy', 'cobalt chrome'],
      ['removable.tooth_brand', 'Ivoclar SR Vivodent'],
      ['removable.tooth_mould', 'A24'], ['removable.tooth_shade', 'A2'],
      ['removable.base_material', 'heat cured acrylic'],
      ['removable.base_shade', 'A2'],
      ['removable.clasp_design', 'Circumferential clasps on #3 and #14'],
      ['removable.major_connector', 'Anterior-posterior palatal strap'],
      ['removable.rest_seats', 'Mesial rests required on #3 and #14'],
      ['removable.vertical_dimension', 'Maintained at existing OVD'],
      ['commercial.quoted_price', '$780.00'],
    ],
    unknowns: [['removable.midline', 'not_recorded_at_the_time']],
  },
  {
    id: 'case-24425', caseNumber: '24425', ...VOSS, patientInitials: 'S.B.',
    receivedAt: '2026-09-12T09:10:00Z', dueDate: '2026-09-16', status: 'ready_to_ship',
    context: {
      restoration_type: 'night_guard', material_class: 'acrylic', is_digital: true,
      is_on_hold: false, is_remake: false, is_delayed: false, is_outsourced: false,
      is_printed: true, is_screw_retained: false, uses_ti_base: false,
      tooth_notation: 'universal',
    },
    facts: [
      ['case.number', '24425'], ['case.practice', 'Voss Implant Centre'],
      ['case.doctor', 'Dr. Voss'], ['case.patient_initials', 'S.B.'],
      ['case.received_at', '2026-09-12T09:10:00Z'], ['case.due_date', '2026-09-16'],
      ['case.status', 'ready to ship'], ['case.assigned_technician', 'Dana K.'],
      ['case.intake_channel', 'digital scan'],
      ['rx.restoration_type', 'night guard'], ['rx.tooth_numbers', '#3'],
      ['rx.tooth_notation', 'universal'], ['rx.arch', 'maxillary'],
      ['rx.unit_count', '1'], ['rx.material', 'pmma'],
      ['rx.appliance_type', 'hard acrylic'],
      ['rx.appliance_coverage', 'full arch maxillary'],
      ['rx.signed', 'yes'], ['rx.received_document', 'Rx-24425.pdf'],
      ['rx.bruxism_flag', 'yes'], ['rx.opposing_dentition', 'natural'],
      ['inputs.scan_received', 'yes'], ['inputs.scanner', 'medit'],
      ['inputs.scan_quality', 'good'], ['inputs.margin_visible', 'yes'],
      ['inputs.bite_registration', 'yes'], ['inputs.opposing_model', 'yes'],
      ['design.appliance_thickness', '2.5 mm'], ['design.designer', 'Dana K.'],
      ['manufacture.method', 'printed'], ['manufacture.printer', 'Formlabs Form 3B+'],
      ['manufacture.post_cure', 'Form Cure, 60°C, 30 minutes'],
      ['manufacture.technicians', 'Dana K.'],
      ['manufacture.completed_at', '2026-09-13T14:00:00Z'],
      ['material.primary_brand', 'Formlabs'],
      ['material.primary_product', 'Dental LT Clear V2'],
      ['material.primary_lot', 'RS-24-1177'],
      ['material.resin_lot', 'RS-24-1177'],
      ['material.resin_class', 'Class IIa long-term intraoral'],
      ['material.certificate_on_file', 'yes'],
      ['qc.inspected_by', 'Priya R.'], ['qc.fit_on_model', 'yes'],
      ['qc.disinfected', 'yes'],
      ['qc.disinfection_method', 'Isopropyl 70%, wipe and air dry'],
      ['commercial.quoted_price', '$145.00'],
    ],
    materials: [
      { role: 'resin', brand: 'Formlabs', product: 'Dental LT Clear V2',
        lot: 'RS-24-1177', expiry: '2027-11-30' },
    ],
  },
  {
    id: 'case-24411', caseNumber: '24411', ...HALE, patientInitials: 'A.G.',
    receivedAt: '2026-09-08T10:00:00Z', dueDate: '2026-09-15', status: 'shipped',
    context: {
      restoration_type: 'bridge', material_class: 'zirconia', is_digital: true,
      is_on_hold: false, is_remake: false, is_delayed: true, is_outsourced: false,
      is_printed: false, is_screw_retained: false, uses_ti_base: false,
      tooth_notation: 'universal',
    },
    facts: [
      ['case.number', '24411'], ['case.practice', 'Hale Family Dentistry'],
      ['case.doctor', 'Dr. Hale'], ['case.patient_initials', 'A.G.'],
      ['case.received_at', '2026-09-08T10:00:00Z'], ['case.due_date', '2026-09-15'],
      ['case.status', 'shipped'], ['case.assigned_technician', 'Priya R.'],
      ['case.intake_channel', 'digital scan'],
      ['rx.restoration_type', 'bridge'], ['rx.tooth_numbers', '#18, #19, #20'],
      ['rx.pontic_sites', '#19'], ['rx.tooth_notation', 'universal'],
      ['rx.arch', 'mandibular'], ['rx.unit_count', '3'],
      ['rx.material', 'zirconia 3y'], ['rx.shade_system', 'vita classical'],
      ['rx.shade_body', 'A3.5'], ['rx.stump_shade', 'A4'], ['rx.signed', 'yes'],
      ['rx.received_document', 'Rx-24411.pdf'], ['rx.opposing_dentition', 'restored'],
      ['inputs.scan_received', 'yes'], ['inputs.scanner', 'itero'],
      ['inputs.scan_quality', 'good'], ['inputs.margin_visible', 'yes'],
      ['inputs.bite_registration', 'yes'], ['inputs.opposing_model', 'yes'],
      ['design.margin_design', 'chamfer'],
      ['design.connector_dimensions', '3.2mm x 3.4mm at both connectors'],
      ['design.pontic_design', 'modified ridge lap'],
      ['design.occlusal_clearance', '1.6 mm'],
      ['design.minimum_thickness_required', '0.7 mm'],
      ['design.designer', 'Marcus L.'], ['design.software', 'exocad'],
      ['material.primary_brand', 'Katana'],
      ['material.primary_product', 'Katana Zirconia HTML Plus'],
      ['material.primary_lot', 'ZR-24-0881'],
      ['material.primary_expiry', '2028-04-30'],
      ['material.certificate_on_file', 'yes'],
      ['manufacture.method', 'milled'], ['manufacture.mill', 'DWX-52D'],
      ['manufacture.sintering_program', 'Conventional 8h cycle'],
      ['manufacture.technicians', 'Priya R.'],
      ['manufacture.completed_at', '2026-09-13T09:00:00Z'],
      ['qc.inspected_by', 'Dana K.'], ['qc.fit_on_model', 'yes'],
      ['qc.margin_integrity', 'pass'], ['qc.occlusion_check', 'adjusted'],
      ['qc.disinfected', 'yes'],
      ['delivery.ship_date', '2026-09-13T15:30:00Z'], ['delivery.carrier', 'FedEx'],
      ['delivery.tracking_number', '772819930041'],
      ['delivery.expected_arrival', '2026-09-15'],
      ['delivery.delay_reason',
       'The first sintering run flagged a furnace fault and the framework was ' +
       'remade in house rather than shipped uncertain.'],
      ['delivery.revised_due_date', '2026-09-15'],
      ['delivery.contents', 'Three-unit bridge, model, cementation instructions'],
      ['delivery.instructions_enclosed', 'yes'],
      ['outcome.warranty_period', '5 years against fracture and fit'],
      ['commercial.quoted_price', '$610.00'],
    ],
    materials: [
      { role: 'primary', brand: 'Katana', product: 'Katana Zirconia HTML Plus',
        lot: 'ZR-24-0881', expiry: '2028-04-30' },
    ],
    steps: [
      { step: 'Design', by: 'Marcus L.', at: '2026-09-09T11:00:00Z', equipment: 'exocad' },
      { step: 'Mill', by: 'Priya R.', at: '2026-09-10T08:00:00Z', equipment: 'DWX-52D' },
      { step: 'Sinter (aborted — furnace fault)', by: 'Priya R.',
        at: '2026-09-10T19:00:00Z', equipment: 'Dekema Austromat 674' },
      { step: 'Re-mill and sinter', by: 'Priya R.', at: '2026-09-11T20:00:00Z',
        equipment: 'Dekema Austromat 674', program: 'Conventional 8h' },
      { step: 'QC', by: 'Dana K.', at: '2026-09-13T09:00:00Z' },
      { step: 'Ship', by: 'Front desk', at: '2026-09-13T15:30:00Z', equipment: 'FedEx' },
    ],
  },
];

function seedCase(store: InMemoryCaseStore, seed: Seed): void {
  const record: CaseRecord = {
    labCase: {
      id: seed.id,
      caseNumber: seed.caseNumber,
      practiceId: seed.practiceId,
      practiceName: seed.practiceName,
      doctorName: seed.doctorName,
      patientInitials: seed.patientInitials,
      context: seed.context as never,
      receivedAt: seed.receivedAt,
      dueDate: seed.dueDate,
      seatDate: seed.seatDate ?? null,
      status: seed.status,
      isDemo: true,
    },
    claims: [], facts: [], steps: [], materials: [], messages: [],
  };
  store.load(record);

  for (const [factKey, value] of seed.facts) {
    const claim = store.addClaim(seed.id, {
      factKey, valueRaw: value, source: 'lab_entry', assertedBy: 'Lab', status: 'pending',
    });
    store.confirm(seed.id, claim.id, 'Lab');
  }

  for (const [factKey, reason] of seed.unknowns ?? []) {
    store.markUnknown(seed.id, factKey, reason);
  }

  // The conflict is left unresolved on purpose: two live claims, no winner,
  // which is exactly the state a case should sit in until a person decides.
  if (seed.conflicting) {
    for (const entry of seed.conflicting.values) {
      store.addClaim(seed.id, {
        factKey: seed.conflicting.factKey,
        valueRaw: entry.value,
        source: entry.source,
        sourceDocumentId: entry.doc ?? null,
        sourcePage: entry.page ?? null,
        sourceSnippet: entry.snippet ?? null,
        status: 'pending',
      });
    }
  }

  for (const material of seed.materials ?? []) {
    store.addMaterial(seed.id, { ...material, expiry: material.expiry ?? null });
  }
  for (const step of seed.steps ?? []) {
    store.addStep(seed.id, {
      step: step.step, performedBy: step.by, performedAt: step.at,
      equipment: step.equipment ?? null, program: step.program ?? null,
    });
  }
  for (const message of seed.messages ?? []) {
    store.addMessage(seed.id, { ...message });
  }
}
