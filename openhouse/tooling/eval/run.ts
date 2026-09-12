/**
 * Answer-quality and hallucination harness (§1.3, §16 Phase 6).
 *
 * Not optional polish. This is how the zero-hallucination claim is proven, and
 * it was built before the pipeline rather than after it, so "0% hallucinated
 * facts" is a number we can produce on demand rather than a slogan.
 *
 *   node tooling/eval/run.ts            human-readable report
 *   node tooling/eval/run.ts --json     machine-readable, for CI
 *
 * Exits non-zero when a threshold is missed.
 */
import { buildDemoProperty, DEMO_PROPERTY_ID }
  from '../../fixtures/demo-property/maple-crescent.ts';
import { createTruthEngine } from '../../packages/truth-engine/src/engine.ts';
import { createAnswerPipeline } from '../../packages/answer-pipeline/src/pipeline.ts';
import { extractNumbers } from '../../packages/answer-pipeline/src/validator.ts';
import { EVAL_SET } from './questions.ts';
import type { EvalCase } from './questions.ts';

export const THRESHOLDS = {
  /** Phase 6 exit criteria. */
  minCorrect: 0.95,
  maxHallucinationRate: 0,
  minUnknownRecall: 1,
  minBoundaryRecall: 1,
  maxP95LatencyMs: 50,
};

export type CaseResult = {
  id: string;
  question: string;
  answer: string;
  expected: string;
  actual: string;
  correct: boolean;
  hallucinated: boolean;
  reasons: string[];
  latencyMs: number;
};

export type EvalReport = {
  total: number;
  correct: number;
  correctRate: number;
  hallucinated: number;
  hallucinationRate: number;
  unknownRecall: number;
  boundaryRecall: number;
  p95LatencyMs: number;
  passed: boolean;
  failures: CaseResult[];
  results: CaseResult[];
};

export async function runEval(): Promise<EvalReport> {
  const store = buildDemoProperty();
  const engine = createTruthEngine(store);
  const property = store.getProperty(DEMO_PROPERTY_ID)!;
  const answer = createAnswerPipeline({
    engine,
    property,
    commentary: () => store.getCommentary(DEMO_PROPERTY_ID),
    disclosures: () => store.getDisclosures(DEMO_PROPERTY_ID),
  });

  // The independent hallucination oracle: every number the property is allowed
  // to say, gathered straight from storage rather than from the pipeline's own
  // grounding payload. Checking the pipeline against itself would prove nothing.
  const permitted = permittedNumbers(store, property);

  const results: CaseResult[] = [];
  for (const testCase of EVAL_SET) {
    const result = await answer({
      propertyId: DEMO_PROPERTY_ID,
      sessionId: `eval-${testCase.id}`,
      question: testCase.question,
    });
    results.push(score(testCase, result.answer, result.retrievalPath,
                       result.latencyMs, permitted));
  }

  const correct = results.filter((r) => r.correct).length;
  const hallucinated = results.filter((r) => r.hallucinated).length;
  const unknownCases = results.filter((r) => r.expected === 'unknown');
  const boundaryCases = results.filter((r) => r.expected === 'boundary_refusal');
  const latencies = results.map((r) => r.latencyMs).sort((a, b) => a - b);

  const report: EvalReport = {
    total: results.length,
    correct,
    correctRate: correct / results.length,
    hallucinated,
    hallucinationRate: hallucinated / results.length,
    unknownRecall: recall(unknownCases),
    boundaryRecall: recall(boundaryCases),
    p95LatencyMs: latencies[Math.floor(latencies.length * 0.95)] ?? 0,
    passed: false,
    failures: results.filter((r) => !r.correct || r.hallucinated),
    results,
  };

  report.passed =
    report.correctRate >= THRESHOLDS.minCorrect &&
    report.hallucinationRate <= THRESHOLDS.maxHallucinationRate &&
    report.unknownRecall >= THRESHOLDS.minUnknownRecall &&
    report.boundaryRecall >= THRESHOLDS.minBoundaryRecall &&
    report.p95LatencyMs <= THRESHOLDS.maxP95LatencyMs;

  return report;
}

function recall(cases: CaseResult[]): number {
  if (cases.length === 0) return 1;
  return cases.filter((r) => r.actual === r.expected).length / cases.length;
}

function score(
  testCase: EvalCase, answerText: string, path: string, latencyMs: number,
  permitted: Set<number>,
): CaseResult {
  const reasons: string[] = [];
  const haystack = answerText.toLowerCase();

  if (path !== testCase.expect) {
    reasons.push(`expected the ${testCase.expect} path, got ${path}`);
  }
  for (const needle of testCase.mustInclude ?? []) {
    if (!haystack.includes(needle.toLowerCase())) reasons.push(`missing "${needle}"`);
  }
  for (const needle of testCase.mustNotInclude ?? []) {
    if (haystack.includes(needle.toLowerCase())) reasons.push(`contains "${needle}"`);
  }

  // A hallucination is any property-shaped number in the answer that the
  // property does not contain. Small counts and the derived-value cases the
  // validator logs are excluded, since those are arithmetic, not invention.
  const invented = extractNumbers(answerText)
    .map((t) => t.value)
    .filter((value) => value > 2 && !permitted.has(value));
  const hallucinated = invented.length > 0;
  if (hallucinated) reasons.push(`invented number(s): ${invented.join(', ')}`);

  return {
    id: testCase.id,
    question: testCase.question,
    answer: answerText,
    expected: testCase.expect,
    actual: path,
    correct: reasons.length === 0,
    hallucinated,
    reasons,
    latencyMs,
  };
}

function permittedNumbers(
  store: ReturnType<typeof buildDemoProperty>,
  property: { addressLine1: string; postalCode?: string | null;
              listPrice?: number | null; bedrooms?: number | null;
              bathrooms?: number | null; livingAreaSqft?: number | null;
              yearBuilt?: number | null },
): Set<number> {
  const numbers = new Set<number>();
  const add = (text: string | number | undefined | null) => {
    if (text === undefined || text === null) return;
    for (const token of extractNumbers(String(text))) numbers.add(token.value);
  };

  // The address and the price are on the sign outside; saying them is not a
  // property claim.
  add(property.addressLine1);
  for (const value of Object.values(property)) {
    if (typeof value === 'number') add(value);
  }
  for (const fact of store.getFacts(DEMO_PROPERTY_ID)) {
    add(fact.valueDisplay);
    if (typeof fact.valueNormalized === 'number') add(fact.valueNormalized);
    if (typeof fact.valueNormalized === 'string') add(fact.valueNormalized);
  }
  for (const claim of store.getClaims(DEMO_PROPERTY_ID)) add(claim.valueRaw);
  for (const item of store.getCommentary(DEMO_PROPERTY_ID)) add(item.text);
  for (const disclosure of store.getDisclosures(DEMO_PROPERTY_ID)) {
    add(disclosure.detail);
    add(disclosure.remediationDetail);
    add(disclosure.occurredOn);
  }
  return numbers;
}

function render(report: EvalReport): string {
  const pct = (n: number) => `${(n * 100).toFixed(1)}%`;
  const lines = [
    '',
    'OPENHOUSE AI — answer quality eval',
    '─'.repeat(52),
    `Questions              ${report.total}`,
    `Correct                ${report.correct} (${pct(report.correctRate)})  ` +
      `target ≥ ${pct(THRESHOLDS.minCorrect)}`,
    `Hallucinated facts     ${report.hallucinated} (${pct(report.hallucinationRate)})  target 0%`,
    `Unknowns identified    ${pct(report.unknownRecall)}  target 100%`,
    `Boundaries enforced    ${pct(report.boundaryRecall)}  target 100%`,
    `p95 latency            ${report.p95LatencyMs}ms  target ≤ ${THRESHOLDS.maxP95LatencyMs}ms`,
    '─'.repeat(52),
  ];

  if (report.failures.length > 0) {
    lines.push('', `${report.failures.length} case(s) need attention:`, '');
    for (const failure of report.failures) {
      lines.push(`  [${failure.id}] ${failure.question}`);
      lines.push(`        → ${failure.answer}`);
      for (const reason of failure.reasons) lines.push(`        ✗ ${reason}`);
      lines.push('');
    }
  }

  lines.push(report.passed ? 'PASS' : 'FAIL', '');
  return lines.join('\n');
}

if (import.meta.filename === process.argv[1]) {
  const report = await runEval();
  process.stdout.write(
    process.argv.includes('--json')
      ? `${JSON.stringify(report, null, 2)}\n`
      : render(report));
  process.exit(report.passed ? 0 : 1);
}
