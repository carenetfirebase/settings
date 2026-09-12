import type { SectionMeta } from './types.ts';

export const SECTIONS: SectionMeta[] = [
  { key: 'A', label: 'Listing basics',            order: 1 },
  { key: 'B', label: 'Structure & construction',  order: 2 },
  { key: 'C', label: 'Exterior & lot',            order: 3 },
  { key: 'D', label: 'Mechanical',                order: 4 },
  { key: 'E', label: 'Kitchen',                   order: 5 },
  { key: 'F', label: 'Bathrooms & laundry',       order: 6 },
  { key: 'G', label: 'Interior',                  order: 7 },
  { key: 'H', label: 'Basement & lower level',    order: 8 },
  { key: 'I', label: 'Energy, safety & security', order: 9 },
  { key: 'J', label: 'Condo & strata',            order: 10 },
  { key: 'K', label: 'Utilities & operating costs', order: 11 },
  { key: 'L', label: 'Legal, permits & what conveys', order: 12 },
];

export const SECTION_LABEL: Record<string, string> =
  Object.fromEntries(SECTIONS.map((s) => [s.key, s.label]));
