/**
 * Open house in a terminal.
 *
 *   node tools/demo.ts                       walk the demo property
 *   node tools/demo.ts "how old is the roof" ask one question
 *   node tools/demo.ts --agent               the agent's view: coverage, conflicts, gaps
 *
 * The point is to make the whole pipeline touchable before any UI exists: the
 * same Truth Engine, the same boundary layer, the same validator, the same
 * ledger entries a real session would write.
 */
import { buildDemoProperty, DEMO_PROPERTY_ID }
  from '../fixtures/demo-property/maple-crescent.ts';
import { createTruthEngine } from '../packages/truth-engine/src/engine.ts';
import { createAnswerPipeline, emptyFrame }
  from '../packages/answer-pipeline/src/pipeline.ts';
import { buildInstructions } from '../packages/ai-gateway/src/voice-session.ts';

const store = buildDemoProperty();
const engine = createTruthEngine(store);
const property = store.getProperty(DEMO_PROPERTY_ID)!;
const answer = createAnswerPipeline({
  engine, property,
  commentary: () => store.getCommentary(DEMO_PROPERTY_ID),
  disclosures: () => store.getDisclosures(DEMO_PROPERTY_ID),
});

const args = process.argv.slice(2);
const dim = (s: string) => `\x1b[2m${s}\x1b[0m`;
const bold = (s: string) => `\x1b[1m${s}\x1b[0m`;
const pct = (n: number) => `${Math.round(n * 100)}%`;

if (args.includes('--agent')) {
  const score = engine.score(DEMO_PROPERTY_ID);
  console.log(`\n${bold(property.addressLine1)} — agent view\n`);
  console.log(`Answer coverage ${pct(score.answerCoverage)}   ·   ` +
              `Prepared ${pct(score.preparation)}`);
  console.log(dim(`${score.answerableCount} of ${score.applicableCount} applicable ` +
                  `facts verified\n`));

  for (const section of score.sections) {
    const filled = Math.round(section.answerCoverage * 12);
    console.log(`  ${section.label.padEnd(32)} ${String(pct(section.answerCoverage)).padStart(4)}  ` +
                `${'█'.repeat(filled)}${'░'.repeat(12 - filled)}`);
  }

  const conflicts = engine.detectConflicts(DEMO_PROPERTY_ID);
  console.log(`\n${bold('Conflicts')} (${conflicts.length})`);
  for (const conflict of conflicts) {
    console.log(`  ${conflict.blocksPublish ? '⚠ ' : '  '}${conflict.label}`);
    for (const claim of conflict.claims) {
      console.log(dim(`      ${claim.display}  ←  ${claim.sourceType}` +
                      `${claim.page ? ` p.${claim.page}` : ''}`));
    }
  }

  const blockers = engine.publishBlockers(DEMO_PROPERTY_ID);
  console.log(`\n${bold('Publish')}: ${blockers.length === 0 ? 'ready' :
    `${blockers.length} blocker(s) — ${blockers.map((b) => b.label).join(', ')}`}`);

  console.log(`\n${bold('Top gaps')}`);
  for (const gap of engine.gaps(DEMO_PROPERTY_ID, 8)) {
    console.log(`  ${gap.question}`);
    console.log(dim(`      ${gap.section} · weight ${gap.coverageWeight}`));
  }
  console.log();
  process.exit(0);
}

if (args.includes('--instructions')) {
  console.log(buildInstructions(engine.buildFactPack(DEMO_PROPERTY_ID), {
    agentName: 'Sarah Thompson', brokerage: 'Thompson Real Estate Group',
  }));
  process.exit(0);
}

const script = args.length > 0 ? [args.join(' ')] : [
  'How old is the furnace?',
  'Is it rented?',
  'How old is the fridge?',
  'What about the dishwasher?',
  'How old are the windows?',
  'Is the basement suite legal?',
  'Has the basement ever had water in it?',
  'What are the property taxes?',
  'Is this a safe neighbourhood?',
  'What should I offer?',
  'How old is the roof?',
];

console.log(`\n${bold(property.addressLine1)}, ${property.city} · ` +
            `$${property.listPrice?.toLocaleString('en-CA')}`);
console.log(dim('DEMO PROPERTY — FICTIONAL DATA\n'));

let frame = emptyFrame();
for (const question of script) {
  const result = await answer({
    propertyId: DEMO_PROPERTY_ID, sessionId: 'demo-cli', question, frame,
  });
  frame = result.frame;
  console.log(`  ${bold('V')}  ${question}`);
  console.log(`  ${bold('A')}  ${result.answer}`);
  console.log(dim(`     ${result.retrievalPath} · ${result.latencyMs}ms` +
                  `${result.resolvedFactKeys.length > 0
                     ? ` · ${result.resolvedFactKeys.join(', ')}` : ''}` +
                  `${result.blocked ? ' · BLOCKED BY VALIDATOR' : ''}`));
  console.log();
}
