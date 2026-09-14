/**
 * The three-second answer to the question that used to take three days.
 *
 *   node tools/recall.ts ZR-24-0881
 */
import { buildDemoLab } from '../fixtures/demo-lab.ts';
import { findByLot } from '../packages/traceability/src/index.ts';

const lot = process.argv[2];
if (!lot) { console.error('usage: node tools/recall.ts <lot>'); process.exit(1); }

const bold = (s: string) => `\x1b[1m${s}\x1b[0m`;
const dim = (s: string) => `\x1b[2m${s}\x1b[0m`;

const result = findByLot(buildDemoLab(), lot);

console.log(`\n${bold(`Lot ${result.lot}`)}`);
if (result.matched === 0) {
  console.log(dim('  No cases used this lot.\n'));
  process.exit(0);
}
console.log(`  ${result.matched} case(s) · ${result.delivered} already with a patient · ` +
            `${result.inProduction} still in the lab\n`);

for (const hit of result.hits) {
  console.log(`  ${bold(hit.caseNumber)}  ${hit.practiceName} · ${hit.doctorName} · ` +
              `${hit.patientInitials}`);
  console.log(dim(`          ${hit.product} (${hit.role}) · ${hit.status}` +
                  `${hit.delivered ? ' · DELIVERED' : ''}`));
}

console.log(`\n  ${bold('Notify')}`);
for (const practice of result.practicesToNotify) {
  console.log(`    ${practice.practiceName} — ${practice.doctorName}: ` +
              `${practice.cases.join(', ')}`);
}
console.log();
