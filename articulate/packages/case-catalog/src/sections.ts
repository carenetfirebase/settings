import type { SectionMeta } from './types.ts';

export const SECTIONS: SectionMeta[] = [
  { key: 'A', label: 'Intake & scheduling',       order: 1 },
  { key: 'B', label: 'Prescription',              order: 2 },
  { key: 'C', label: 'Inputs received',           order: 3 },
  { key: 'D', label: 'Design specification',      order: 4 },
  { key: 'E', label: 'Implant componentry',       order: 5 },
  { key: 'F', label: 'Removable',                 order: 6 },
  { key: 'G', label: 'Materials & lot',           order: 7 },
  { key: 'H', label: 'Manufacture & QC',          order: 8 },
  { key: 'I', label: 'Delivery',                  order: 9 },
  { key: 'J', label: 'Fit & outcome',             order: 10 },
  { key: 'K', label: 'Regulatory record',         order: 11 },
  { key: 'L', label: 'Commercial',                order: 12 },
];

export const SECTION_LABEL: Record<string, string> =
  Object.fromEntries(SECTIONS.map((s) => [s.key, s.label]));
