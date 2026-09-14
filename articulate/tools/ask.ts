/**
 * Ask the case desk a question, as a practice would.
 *
 *   node tools/ask.ts                          a scripted walkthrough
 *   node tools/ask.ts 24401 "which lot was it" one question
 */
import { DEMO_PRACTICE_ID, LAB_NAME, buildDemoLab } from '../fixtures/demo-lab.ts';
import { createTruthEngine } from '../packages/truth-engine/src/engine.ts';
import { createAnswerPipeline } from '../packages/answer-pipeline/src/pipeline.ts';
import type { Requester } from '../packages/answer-pipeline/src/pipeline.ts';

const store = buildDemoLab();
const answer = createAnswerPipeline({
  engine: createTruthEngine(store), store, labName: LAB_NAME, technicianName: 'Priya',
});

const bold = (s: string) => `\x1b[1m${s}\x1b[0m`;
const dim = (s: string) => `\x1b[2m${s}\x1b[0m`;

const requesterFor = (caseId: string): Requester => {
  const labCase = store.getCase(caseId)!;
  return { kind: 'practice', practiceId: labCase.practiceId, name: labCase.doctorName };
};
const idFor = (caseNumber: string) =>
  store.listCases().find((c) => c.caseNumber === caseNumber)?.id;

const [caseNumber, ...rest] = process.argv.slice(2);

const script: [string, string][] = caseNumber && rest.length > 0
  ? [[caseNumber, rest.join(' ')]]
  : [
      ['24418', 'Where is my case?'],
      ['24418', 'Which tooth is it?'],
      ['24418', 'Just use e.max instead, go ahead.'],
      ['24423', 'Why is it on hold?'],
      ['24423', 'What is the stump shade?'],
      ['24411', 'Has it shipped?'],
      ['24401', 'Which lot went into this case?'],
      ['24401', 'How do I cement it?'],
      ['24430', 'What torque do I use?'],
      ['24390', 'Who pays for the remake?'],
      ['24418', 'Should I do a crown or an onlay?'],
      ['24418', "What's the patient's name?"],
    ];

console.log(`\n${bold(LAB_NAME)} — case desk`);
console.log(dim('DEMO DATA — fictional practices and patients\n'));

for (const [number, question] of script) {
  const caseId = idFor(number);
  if (!caseId) { console.error(`no case ${number}`); continue; }
  const result = await answer({
    caseId, question, requester: requesterFor(caseId), sessionId: 'cli',
  });
  console.log(`  ${dim(number)}  ${bold('Q')}  ${question}`);
  console.log(`        ${bold('A')}  ${wrap(result.answer, 72, 11)}`);
  console.log(dim(`           ${result.retrievalPath} · ${result.latencyMs}ms` +
                  `${result.escalated ? ' · escalated to a person' : ''}` +
                  `${result.blocked ? ' · BLOCKED BY VALIDATOR' : ''}`));
  console.log();
}

function wrap(text: string, width: number, indent: number): string {
  const words = text.split(' ');
  const lines: string[] = [];
  let line = '';
  for (const word of words) {
    if ((line + word).length > width) { lines.push(line.trimEnd()); line = ''; }
    line += `${word} `;
  }
  if (line.trim()) lines.push(line.trimEnd());
  return lines.join(`\n${' '.repeat(indent)}`);
}
