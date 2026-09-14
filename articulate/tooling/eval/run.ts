/**
 * Answer-quality and invention harness.
 *
 *   node tooling/eval/run.ts          human-readable
 *   node tooling/eval/run.ts --json   machine-readable, for CI
 *
 * Exits non-zero when a threshold slips.
 */
import { DEMO_PRACTICE_ID, LAB_NAME, buildDemoLab } from '../../fixtures/demo-lab.ts';
import { createTruthEngine } from '../../packages/truth-engine/src/engine.ts';
import { createAnswerPipeline } from '../../packages/answer-pipeline/src/pipeline.ts';
import { extractIdentifiers, extractNumbers }
  from '../../packages/answer-pipeline/src/validator.ts';
import type { Requester } from '../../packages/answer-pipeline/src/pipeline.ts';
import { EVAL_SET } from './questions.ts';
import type { EvalCase } from './questions.ts';

export const THRESHOLDS = {
  minCorrect: 0.95,
  maxInventionRate: 0,
  minUnknownRecall: 1,
  minBoundaryRecall: 1,
  maxP95LatencyMs: 50,
};

export type CaseResult = {
  id: string; question: string; answer: string; expected: string; actual: string;
  correct: boolean; invented: boolean; reasons: string[]; latencyMs: number;
};

export type EvalReport = {
  total: number; correct: number; correctRate: number;
  invented: number; inventionRate: number;
  unknownRecall: number; boundaryRecall: number; p95LatencyMs: number;
  passed: boolean; failures: CaseResult[]; results: CaseResult[];
};

const REQUESTERS: Record<EvalCase['as'], Requester> = {
  okafor: { kind: 'practice', practiceId: DEMO_PRACTICE_ID, name: 'Dr. Okafor' },
  hale: { kind: 'practice', practiceId: 'practice-hale', name: 'Dr. Hale' },
  voss: { kind: 'practice', practiceId: 'practice-voss', name: 'Dr. Voss' },
  bench: { kind: 'lab', userId: 'u1', name: 'Priya R.' },
};

export async function runEval(): Promise<EvalReport> {
  const store = buildDemoLab();
  const answer = createAnswerPipeline({
    engine: createTruthEngine(store), store, labName: LAB_NAME, technicianName: 'Priya',
  });

  // The oracle is built straight from storage, per case, rather than from the
  // pipeline's own grounding payload. Checking the pipeline against itself
  // would prove nothing — and scoping it per case is what catches a value
  // bleeding in from a different patient's case.
  const permitted = new Map<string, { numbers: Set<number>; text: string }>();
  for (const labCase of store.listCases()) {
    const parts: string[] = [
      labCase.caseNumber, labCase.dueDate, labCase.seatDate ?? '', labCase.status,
      labCase.practiceName, labCase.doctorName,
    ];
    for (const fact of store.getFacts(labCase.id)) {
      parts.push(fact.valueDisplay ?? '', String(fact.valueNormalized ?? ''));
    }
    for (const claim of store.getClaims(labCase.id)) parts.push(claim.valueRaw ?? '');
    for (const material of store.getMaterials(labCase.id)) {
      parts.push(material.lot, material.brand, material.product, material.expiry ?? '');
    }
    for (const step of store.getSteps(labCase.id)) {
      parts.push(step.performedAt, step.performedBy, step.equipment ?? '');
    }
    const text = parts.join(' ');
    permitted.set(labCase.id, {
      text: text.toLowerCase(),
      numbers: new Set(extractNumbers(text).map((t) => t.value)),
    });
  }

  const results: CaseResult[] = [];
  for (const testCase of EVAL_SET) {
    const result = await answer({
      caseId: testCase.caseId, question: testCase.question,
      requester: REQUESTERS[testCase.as], sessionId: `eval-${testCase.id}`,
    });
    results.push(score(testCase, result.answer, result.retrievalPath, result.latencyMs,
                       permitted.get(testCase.caseId)));
  }

  const correct = results.filter((r) => r.correct).length;
  const invented = results.filter((r) => r.invented).length;
  const latencies = results.map((r) => r.latencyMs).sort((a, b) => a - b);

  const report: EvalReport = {
    total: results.length,
    correct,
    correctRate: correct / results.length,
    invented,
    inventionRate: invented / results.length,
    unknownRecall: recall(results.filter((r) => r.expected === 'unknown')),
    boundaryRecall: recall(results.filter(
      (r) => r.expected === 'boundary_refusal' || r.expected === 'routed_to_technician')),
    p95LatencyMs: latencies[Math.floor(latencies.length * 0.95)] ?? 0,
    passed: false,
    failures: results.filter((r) => !r.correct || r.invented),
    results,
  };

  report.passed =
    report.correctRate >= THRESHOLDS.minCorrect &&
    report.inventionRate <= THRESHOLDS.maxInventionRate &&
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
  oracle: { numbers: Set<number>; text: string } | undefined,
): CaseResult {
  const reasons: string[] = [];
  const haystack = answerText.toLowerCase();

  if (path !== testCase.expect) {
    reasons.push(`expected ${testCase.expect}, got ${path}`);
  }
  for (const needle of testCase.mustInclude ?? []) {
    if (!haystack.includes(needle.toLowerCase())) reasons.push(`missing "${needle}"`);
  }
  for (const needle of testCase.mustNotInclude ?? []) {
    if (haystack.includes(needle.toLowerCase())) reasons.push(`contains "${needle}"`);
  }

  const inventions: string[] = [];
  if (oracle) {
    for (const token of extractIdentifiers(answerText)) {
      if (!oracle.text.includes(token.text.toLowerCase())) {
        inventions.push(`${token.kind} ${token.text}`);
      }
    }
    for (const token of extractNumbers(answerText)) {
      if (token.value <= 2) continue;
      if (oracle.numbers.has(token.value)) continue;
      if (oracle.text.includes(token.raw.toLowerCase())) continue;
      inventions.push(token.raw);
    }
  }
  const invented = inventions.length > 0;
  if (invented) reasons.push(`not on this case: ${inventions.join(', ')}`);

  return {
    id: testCase.id, question: testCase.question, answer: answerText,
    expected: testCase.expect, actual: path,
    correct: reasons.length === 0, invented, reasons, latencyMs,
  };
}

function render(report: EvalReport): string {
  const pct = (n: number) => `${(n * 100).toFixed(1)}%`;
  const lines = [
    '',
    'ARTICULATE — answer quality eval',
    '─'.repeat(54),
    `Questions                ${report.total}`,
    `Correct                  ${report.correct} (${pct(report.correctRate)})  ` +
      `target ≥ ${pct(THRESHOLDS.minCorrect)}`,
    `Invented values          ${report.invented} (${pct(report.inventionRate)})  target 0%`,
    `Unknowns identified      ${pct(report.unknownRecall)}  target 100%`,
    `Boundaries held          ${pct(report.boundaryRecall)}  target 100%`,
    `p95 latency              ${report.p95LatencyMs}ms  target ≤ ${THRESHOLDS.maxP95LatencyMs}ms`,
    '─'.repeat(54),
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
  process.stdout.write(process.argv.includes('--json')
    ? `${JSON.stringify(report, null, 2)}\n`
    : render(report));
  process.exit(report.passed ? 0 : 1);
}
