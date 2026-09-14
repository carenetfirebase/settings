/**
 * The bench board in a terminal: every case, what is holding it, and what the
 * record looks like.
 *
 *   node tools/bench.ts
 *   node tools/bench.ts 24418      one case in full
 */
import { buildDemoLab } from '../fixtures/demo-lab.ts';
import { createTruthEngine } from '../packages/truth-engine/src/engine.ts';
import { buildDeviceHistoryRecord } from '../packages/traceability/src/index.ts';

const store = buildDemoLab();
const engine = createTruthEngine(store);
const bold = (s: string) => `\x1b[1m${s}\x1b[0m`;
const dim = (s: string) => `\x1b[2m${s}\x1b[0m`;
const red = (s: string) => `\x1b[31m${s}\x1b[0m`;
const pct = (n: number) => `${Math.round(n * 100)}%`;

const target = process.argv[2];

if (target) {
  const labCase = store.listCases().find((c) => c.caseNumber === target);
  if (!labCase) { console.error(`no case ${target}`); process.exit(1); }

  const score = engine.score(labCase.id);
  const record = buildDeviceHistoryRecord(store, labCase);
  console.log(`\n${bold(labCase.caseNumber)} · ${labCase.practiceName} · ` +
              `${labCase.doctorName} · ${labCase.patientInitials}`);
  console.log(dim(`${labCase.status} · due ${labCase.dueDate}\n`));
  console.log(`Ready to start ${pct(score.readiness)}   ` +
              `Answerable ${pct(score.answerCoverage)}   ` +
              `Record ${pct(score.dhrCompleteness)}\n`);

  const blockers = engine.blockers(labCase.id);
  if (blockers.length > 0) {
    console.log(bold('Holding'));
    for (const blocker of blockers) {
      const mark = blocker.phase === 'start' ? red('■') : '·';
      console.log(`  ${mark} ${blocker.label} ${dim(`(${blocker.phase})`)}`);
      console.log(dim(`      ${blocker.detail}`));
    }
    console.log();
  }

  const asks = engine.asks(labCase.id, 5);
  if (asks.length > 0) {
    console.log(bold('To ask the practice'));
    for (const ask of asks) console.log(`  ${ask.question}`);
    console.log();
  }

  console.log(bold(`Device history record — ${record.complete ? 'complete' : 'incomplete'}`));
  console.log(dim(`  ${record.entries.length} entries, ${record.missing.length} outstanding`));
  for (const step of record.steps) {
    console.log(`  ${step.at.slice(0, 16).replace('T', ' ')}  ${step.step} — ${step.by}` +
                `${step.equipment ? dim(` · ${step.equipment}`) : ''}`);
  }
  for (const material of record.materials) {
    console.log(`  ${dim(material.role.padEnd(12))} ${material.product} ` +
                `${bold(`lot ${material.lot}`)}`);
  }
  console.log();
  process.exit(0);
}

console.log(`\n${bold('Meridian Dental Studio')} — bench board`);
console.log(dim('DEMO DATA — fictional practices and patients\n'));
console.log(dim('  case   practice                 due         status              ' +
                'ready  record  holding'));
for (const labCase of store.listCases()) {
  const score = engine.score(labCase.id);
  const starting = engine.blockers(labCase.id).filter((b) => b.phase === 'start');
  const flag = starting.length > 0 ? red(`■ ${starting.length}`) : dim('—  ');
  console.log(`  ${labCase.caseNumber}  ${labCase.practiceName.padEnd(24)} ` +
              `${labCase.dueDate}  ${labCase.status.padEnd(20)}` +
              `${pct(score.readiness).padStart(4)}   ` +
              `${pct(score.dhrCompleteness).padStart(4)}    ${flag}`);
}
console.log(dim('\n  node tools/bench.ts 24418   for one case in full\n'));
