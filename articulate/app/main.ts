/**
 * ARTICULATE — the working board.
 *
 * This is not a mock. It imports the real Truth Engine, the real boundary
 * layer, the real validator and the real demo lab, and runs them in the
 * browser: every answer below goes through the same pipeline the tests and the
 * eval harness measure.
 */
import { DEMO_PRACTICE_ID, LAB_NAME, buildDemoLab } from '../fixtures/demo-lab.ts';
import { SECTION_LABEL, getDefinition } from '../packages/case-catalog/src/index.ts';
import { createTruthEngine } from '../packages/truth-engine/src/engine.ts';
import { humanize } from '../packages/truth-engine/src/normalize.ts';
import type { CaseFact, LabCase } from '../packages/truth-engine/src/types.ts';
import { buildDeviceHistoryRecord, findByLot }
  from '../packages/traceability/src/index.ts';
import { createAnswerPipeline } from '../packages/answer-pipeline/src/pipeline.ts';
import type { AnswerResult, Requester } from '../packages/answer-pipeline/src/pipeline.ts';

const store = buildDemoLab();
const engine = createTruthEngine(store);
const ask = createAnswerPipeline({
  engine, store, labName: LAB_NAME, technicianName: 'Priya',
});

type View = 'bench' | 'practice';

const state = {
  caseId: 'case-24418',
  view: 'bench' as View,
  transcript: [] as { question: string; result: AnswerResult }[],
  recallLot: '',
  thinking: false,
};

/** Approximate VITA Classical chip colours, so a shade reads as a shade. */
const SHADE_HEX: Record<string, string> = {
  A1: '#E8DFC8', A2: '#E3D7B8', A3: '#DDCFA6', 'A3.5': '#D6C596', A4: '#CDBA86',
  B1: '#EBE5D3', B2: '#E4D9B9', B3: '#DACB9E', B4: '#D2C08C',
  C1: '#DCD6C4', C2: '#D2C9AE', C3: '#C8BD9B', C4: '#BCAF89',
  D2: '#DED6C0', D3: '#D6CCAF', D4: '#CDC29E',
  BL1: '#F6F3EC', BL2: '#F2EDE3', BL3: '#EEE8DA', BL4: '#EAE3D1',
};

const STATUS_TONE: Record<string, 'hold' | 'active' | 'done'> = {
  received: 'active', on_hold_pending_practice: 'hold', in_design: 'active',
  in_production: 'active', in_finishing: 'active', in_qc: 'active',
  ready_to_ship: 'active', shipped: 'done', delivered: 'done', seated: 'done',
  remake_in_progress: 'hold', cancelled: 'done',
};

const el = <K extends keyof HTMLElementTagNameMap>(
  tag: K, className?: string, text?: string,
): HTMLElementTagNameMap[K] => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
};

const pct = (n: number) => `${Math.round(n * 100)}%`;

function currentCase(): LabCase { return store.getCase(state.caseId)!; }

function requester(): Requester {
  const labCase = currentCase();
  return state.view === 'bench'
    ? { kind: 'lab', userId: 'priya', name: 'Priya R.' }
    : { kind: 'practice', practiceId: labCase.practiceId, name: labCase.doctorName };
}

// ------------------------------------------------------------------ render --

function render(): void {
  const root = document.getElementById('app')!;
  root.replaceChildren(header(), board());
}

function header(): HTMLElement {
  const bar = el('header', 'topbar');

  const brand = el('div', 'brand');
  brand.append(el('span', 'mark', 'A'));
  const name = el('div', 'brand-name');
  name.append(el('strong', undefined, 'Articulate'), el('span', 'brand-sub', LAB_NAME));
  brand.append(name);

  const views = el('div', 'segmented');
  views.setAttribute('role', 'tablist');
  for (const [value, label, hint] of [
    ['bench', 'Bench', 'everything on the case'],
    ['practice', 'Practice portal', 'what the dentist sees'],
  ] as const) {
    const button = el('button', state.view === value ? 'seg on' : 'seg', label);
    button.type = 'button';
    button.title = hint;
    button.setAttribute('role', 'tab');
    button.setAttribute('aria-selected', String(state.view === value));
    button.addEventListener('click', () => {
      state.view = value;
      state.transcript = [];
      render();
    });
    views.append(button);
  }

  const recall = el('form', 'recall');
  const input = el('input', 'recall-input');
  input.type = 'search';
  input.id = 'recall-lot';
  input.placeholder = 'Trace a lot — try ZR-24-0881';
  input.value = state.recallLot;
  input.setAttribute('aria-label', 'Trace a material lot');
  const go = el('button', 'recall-go', 'Trace');
  go.type = 'submit';
  recall.append(input, go);
  recall.addEventListener('submit', (event) => {
    event.preventDefault();
    state.recallLot = input.value.trim();
    render();
  });

  bar.append(brand, views, recall);
  return bar;
}

function board(): HTMLElement {
  const wrap = el('div', 'board');
  wrap.append(caseRail(), main());
  return wrap;
}

function caseRail(): HTMLElement {
  const rail = el('aside', 'rail');
  const head = el('div', 'rail-head');
  head.append(el('h2', 'rail-title', 'Open cases'));
  head.append(el('span', 'rail-count', `${store.listCases().length}`));
  rail.append(head);

  const list = el('div', 'case-list');
  for (const labCase of store.listCases()) {
    const holding = engine.blockers(labCase.id).filter((b) => b.phase === 'start');
    const tone = STATUS_TONE[labCase.status] ?? 'active';
    const item = el('button',
      `case-item${labCase.id === state.caseId ? ' on' : ''} tone-${holding.length ? 'hold' : tone}`);
    item.type = 'button';

    const top = el('div', 'case-top');
    top.append(el('span', 'case-no mono', labCase.caseNumber));
    top.append(el('span', 'case-due mono', labCase.dueDate.slice(5)));
    const who = el('div', 'case-who', `${labCase.practiceName} · ${labCase.doctorName}`);
    const foot = el('div', 'case-foot');
    foot.append(el('span', 'case-status', humanize(labCase.status)));
    if (holding.length > 0) {
      foot.append(el('span', 'chip chip-critical', `${holding.length} holding`));
    }

    item.append(top, who, foot);
    item.addEventListener('click', () => {
      state.caseId = labCase.id;
      state.transcript = [];
      render();
    });
    list.append(item);
  }
  rail.append(list);
  return rail;
}

function main(): HTMLElement {
  const pane = el('main', 'pane');
  if (state.recallLot) pane.append(recallPanel());
  pane.append(caseHeader(), meters(), holdingPanel(), askPanel(), recordPanel(), dhrPanel());
  return pane;
}

function caseHeader(): HTMLElement {
  const labCase = currentCase();
  const block = el('section', 'case-header');

  const identity = el('div', 'identity');
  const title = el('h1', 'case-title');
  title.append(el('span', 'mono', labCase.caseNumber));
  identity.append(title);

  const meta = el('div', 'identity-meta');
  meta.append(metaItem('Practice', labCase.practiceName));
  meta.append(metaItem('Prescriber', labCase.doctorName));
  meta.append(metaItem('Patient',
    state.view === 'practice' ? 'held by your office' : labCase.patientInitials,
    state.view === 'practice'));
  meta.append(metaItem('Due', labCase.dueDate, false, true));
  identity.append(meta);

  block.append(identity, archDiagram(labCase));
  return block;
}

function metaItem(label: string, value: string, muted = false, mono = false): HTMLElement {
  const item = el('div', 'meta-item');
  item.append(el('span', 'meta-label', label));
  item.append(el('span', `meta-value${muted ? ' muted' : ''}${mono ? ' mono' : ''}`, value));
  return item;
}

/**
 * The arch, in Universal numbering.
 *
 * Worth drawing rather than listing: a tooth-number disagreement is the thing
 * this product exists to catch, and two teeth lit in opposition says it faster
 * than a sentence can.
 */
function archDiagram(labCase: LabCase): HTMLElement {
  const wrap = el('div', 'arch');
  const prescribed = new Set<number>();
  const disputed = new Set<number>();

  const facts = store.getFacts(labCase.id);
  const tooth = facts.find((f) => f.factKey === 'rx.tooth_numbers');
  if (tooth?.status === 'confirmed') {
    for (const n of readTeeth(tooth)) prescribed.add(n);
  }
  for (const conflict of engine.detectConflicts(labCase.id)) {
    if (conflict.factKey !== 'rx.tooth_numbers') continue;
    for (const claim of conflict.claims) {
      for (const n of toUniversal(claim.value)) disputed.add(n);
    }
  }
  const pontics = new Set(
    readTeeth(facts.find((f) => f.factKey === 'rx.pontic_sites')));

  for (const row of [[1, 16], [17, 32]] as const) {
    const line = el('div', 'arch-row');
    for (let n = row[0]; n <= row[1]; n += 1) {
      const classes = ['tooth'];
      if (disputed.has(n)) classes.push('disputed');
      else if (pontics.has(n)) classes.push('pontic');
      else if (prescribed.has(n)) classes.push('prescribed');
      const cell = el('span', classes.join(' '), String(n));
      cell.title = `Universal #${n}`;
      line.append(cell);
    }
    wrap.append(line);
  }

  const key = el('div', 'arch-key');
  if (disputed.size > 0) key.append(el('span', 'key key-disputed', 'sources disagree'));
  if (prescribed.size > 0) key.append(el('span', 'key key-prescribed', 'prescribed'));
  if (pontics.size > 0) key.append(el('span', 'key key-pontic', 'pontic'));
  key.append(el('span', 'key key-note', 'Universal notation'));
  wrap.append(key);
  return wrap;
}

function readTeeth(fact: CaseFact | undefined): number[] {
  if (!fact || fact.status !== 'confirmed') return [];
  return toUniversal(fact.valueNormalized);
}

function toUniversal(value: unknown): number[] {
  if (!Array.isArray(value)) return [];
  return (value as number[]).map(fdiToUniversal);
}

function fdiToUniversal(fdi: number): number {
  const quadrant = Math.floor(fdi / 10);
  const position = fdi % 10;
  if (quadrant === 1) return 9 - position;
  if (quadrant === 2) return 8 + position;
  if (quadrant === 3) return 25 - position;
  return 24 + position;
}

function meters(): HTMLElement {
  const score = engine.score(state.caseId);
  const row = el('section', 'meters');
  const items: [string, number, string][] = [
    ['Ready to start', score.readiness,
     `${score.blockingOutstanding} intake item(s) outstanding`],
    ['Answerable', score.answerCoverage,
     `${score.resolvedCount} of ${score.applicableCount} applicable facts resolved`],
    ['Device record', score.dhrCompleteness,
     `${score.dhrOutstanding.length} record entries outstanding`],
  ];
  for (const [label, value, hint] of items) {
    const meter = el('div', 'meter');
    const head = el('div', 'meter-head');
    head.append(el('span', 'meter-label', label));
    head.append(el('span', 'meter-value mono', pct(value)));
    const track = el('div', 'meter-track');
    const fill = el('div', `meter-fill ${value >= 1 ? 'full' : value >= 0.6 ? 'mid' : 'low'}`);
    fill.style.width = `${Math.max(2, value * 100)}%`;
    track.append(fill);
    meter.append(head, track, el('span', 'meter-hint', hint));
    row.append(meter);
  }
  return row;
}

function holdingPanel(): HTMLElement {
  const panel = section('What is holding this case',
    'Intake blockers stop the bench. Later phases are the lab’s own work.');
  const blockers = engine.blockers(state.caseId);
  const conflicts = engine.detectConflicts(state.caseId);

  if (blockers.length === 0) {
    panel.append(emptyNote('Nothing is holding this case.'));
    return panel;
  }

  for (const conflict of conflicts) {
    const card = el('div', 'conflict');
    const head = el('div', 'conflict-head');
    head.append(el('span', 'chip chip-critical', 'Sources disagree'));
    head.append(el('strong', undefined, conflict.label));
    if (conflict.stopsProduction) {
      head.append(el('span', 'chip chip-ghost', 'production stopped'));
    }
    card.append(head);
    card.append(el('p', 'conflict-note',
      'Nothing here picks a winner. The case waits for a person.'));

    const options = el('div', 'options');
    for (const claim of conflict.claims) {
      const option = el('div', 'option');
      const value = el('div', 'option-value mono', claim.display);
      const src = el('div', 'option-source', humanize(claim.source));
      option.append(value, src);
      if (claim.snippet) option.append(el('div', 'option-snippet', `“${claim.snippet}”`));
      const confirm = el('button', 'btn btn-primary', 'Confirm this');
      confirm.type = 'button';
      confirm.addEventListener('click', () => {
        store.confirm(state.caseId, claim.claimId, 'Priya R.');
        state.transcript = [];
        render();
      });
      option.append(confirm);
      options.append(option);
    }
    card.append(options);
    panel.append(card);
  }

  const missing = blockers.filter((b) => b.kind === 'missing_blocking_fact');
  if (missing.length > 0) {
    const list = el('ul', 'blocker-list');
    for (const blocker of missing) {
      const item = el('li', `blocker phase-${blocker.phase}`);
      const head = el('div', 'blocker-head');
      head.append(el('span', `chip chip-${blocker.phase === 'start' ? 'critical' : 'quiet'}`,
        blocker.phase));
      head.append(el('strong', undefined, blocker.label));
      item.append(head, el('p', 'blocker-detail', blocker.detail));
      list.append(item);
    }
    panel.append(list);
  }

  const asks = engine.asks(state.caseId, 4);
  if (asks.length > 0) {
    const outbound = el('div', 'outbound');
    outbound.append(el('h4', 'outbound-title', 'Ready to send to the practice'));
    for (const item of asks) {
      const line = el('div', 'outbound-line');
      line.append(el('span', 'outbound-q', item.question));
      line.append(el('span', 'outbound-key mono', item.factKey));
      outbound.append(line);
    }
    panel.append(outbound);
  }
  return panel;
}

function askPanel(): HTMLElement {
  const labCase = currentCase();
  const who = state.view === 'bench' ? 'Priya R. (bench)' : labCase.doctorName;
  const panel = section('Ask the case desk',
    `Answering as ${LAB_NAME} to ${who}. Every answer is checked before it is sent.`);

  const form = el('form', 'ask-form');
  const input = el('input', 'ask-input');
  input.type = 'text';
  input.id = 'ask-input';
  input.placeholder = 'Where is my case?';
  input.autocomplete = 'off';
  input.setAttribute('aria-label', 'Ask about this case');
  const send = el('button', 'btn btn-primary', 'Ask');
  send.type = 'submit';
  form.append(input, send);

  const run = async (question: string) => {
    if (!question.trim() || state.thinking) return;
    state.thinking = true;
    const result = await ask({
      caseId: state.caseId, question, requester: requester(), sessionId: 'ui',
    });
    state.transcript = [{ question, result }, ...state.transcript].slice(0, 6);
    state.thinking = false;
    render();
  };

  form.addEventListener('submit', (event) => {
    event.preventDefault();
    void run(input.value);
  });
  panel.append(form);

  const suggestions = el('div', 'suggestions');
  for (const question of suggestionsFor(labCase)) {
    const chip = el('button', 'suggest', question);
    chip.type = 'button';
    chip.addEventListener('click', () => void run(question));
    suggestions.append(chip);
  }
  panel.append(suggestions);

  if (state.transcript.length === 0) {
    panel.append(emptyNote('Ask anything about this case, or try one of the above.'));
    return panel;
  }

  for (const turn of state.transcript) {
    const exchange = el('div', 'exchange');
    exchange.append(el('div', 'q', turn.question));
    exchange.append(el('div', 'a', turn.result.answer));

    const trace = el('div', 'trace');
    trace.append(el('span', `chip chip-path path-${turn.result.retrievalPath}`,
      humanize(turn.result.retrievalPath)));
    trace.append(el('span', 'trace-item mono', `${turn.result.latencyMs}ms`));
    for (const key of turn.result.resolvedFactKeys.slice(0, 3)) {
      trace.append(el('span', 'trace-item mono', key));
    }
    if (turn.result.escalated) {
      trace.append(el('span', 'chip chip-caution', 'escalated to a person'));
    }
    if (turn.result.blocked) {
      trace.append(el('span', 'chip chip-critical', 'held by the validator'));
    }
    if (turn.result.validatorFlags.length === 0 && !turn.result.blocked) {
      trace.append(el('span', 'trace-item ok', '✓ validator clear'));
    }
    exchange.append(trace);
    panel.append(exchange);
  }
  return panel;
}

function suggestionsFor(labCase: LabCase): string[] {
  const base = ['Where is my case?', 'What do you need from me?'];
  const conflicted = engine.detectConflicts(labCase.id).length > 0;
  const byType: Record<string, string[]> = {
    crown: ['What shade did you use?', 'Which lot went into this case?'],
    veneer: ['What is the stump shade?', 'What material is it?'],
    implant_crown: ['What torque do I use?', 'Which abutment did you use?'],
    bridge: ['Where are the pontics?', 'How big are the connectors?'],
    partial_denture: ['Do I need to prep rest seats?', 'What mould is it?'],
    night_guard: ['How thick is the guard?', 'What resin did you print in?'],
  };
  const type = String(labCase.context.restoration_type ?? '');
  const extra = byType[type] ?? ['What material is it?'];
  const probes = conflicted
    ? ['Which tooth is it?', 'Just use e.max instead, go ahead.']
    : ['Should I do a crown or an onlay?', "What's the patient's name?"];
  return [...base, ...extra, ...probes];
}

function recordPanel(): HTMLElement {
  const panel = section('Case record',
    state.view === 'practice'
      ? 'What your office can see. Patient identifiers and lab costs are never in here.'
      : 'Every resolved fact, with who stood behind it.');

  const facts = store.getFacts(state.caseId)
    .filter((f) => (state.view === 'practice'
      ? f.visibility === 'practice'
      : f.visibility !== 'phi'))
    .filter((f) => f.status === 'confirmed' || f.status === 'unknown');

  const bySection = new Map<string, CaseFact[]>();
  for (const fact of facts) {
    const definition = getDefinition(fact.factKey);
    if (!definition) continue;
    const group = bySection.get(definition.section) ?? [];
    group.push(fact);
    bySection.set(definition.section, group);
  }

  const hiddenCount = store.getFacts(state.caseId).length - facts.length;

  for (const [sectionKey, group] of [...bySection.entries()].sort()) {
    const block = el('div', 'record-section');
    block.append(el('h4', 'record-section-title', SECTION_LABEL[sectionKey] ?? sectionKey));
    const table = el('dl', 'record-list');
    for (const fact of group) {
      const definition = getDefinition(fact.factKey)!;
      const term = el('dt', 'record-term', definition.label);
      const value = el('dd', 'record-value');

      if (fact.status === 'unknown') {
        value.append(el('span', 'unknown-mark', 'not on record'));
        value.append(el('span', 'chip chip-quiet',
          humanize(fact.unknownReason ?? 'unknown')));
      } else {
        const display = fact.valueDisplay ?? String(fact.valueNormalized ?? '');
        if (definition.dataType === 'shade' && SHADE_HEX[display]) {
          const chip = el('span', 'shade-chip');
          chip.style.background = SHADE_HEX[display];
          value.append(chip);
        }
        const exact = ['lot', 'tooth', 'tooth_set', 'shade', 'torque'].includes(
          definition.dataType);
        value.append(el('span', exact ? 'val mono exact' : 'val', display));
        if (fact.confirmationLevel && fact.confirmationLevel !== 'lab_confirmed') {
          value.append(el('span', 'chip chip-quiet', humanize(fact.confirmationLevel)));
        }
      }
      table.append(term, value);
    }
    block.append(table);
    panel.append(block);
  }

  if (hiddenCount > 0 && state.view === 'practice') {
    panel.append(el('p', 'record-note',
      `${hiddenCount} fact(s) on this case are not shown here — patient identifiers ` +
      'and lab-internal costs never enter a practice answer.'));
  }
  return panel;
}

function dhrPanel(): HTMLElement {
  const labCase = currentCase();
  const record = buildDeviceHistoryRecord(store, labCase);
  const panel = section('Device history record',
    'Computed from the record, never asserted. This is what a complaint, a ' +
    'recall or an audit asks for.');

  const status = el('div', 'dhr-status');
  status.append(el('span', `chip ${record.complete ? 'chip-clear' : 'chip-caution'}`,
    record.complete ? 'Complete' : `${record.missing.length} outstanding`));
  status.append(el('span', 'dhr-count mono',
    `${record.entries.length} entries · ${record.materials.length} materials`));
  panel.append(status);

  if (record.materials.length > 0) {
    const materials = el('div', 'materials');
    for (const material of record.materials) {
      const card = el('div', 'material');
      card.append(el('span', 'material-role', humanize(material.role)));
      card.append(el('span', 'material-product', material.product));
      const lot = el('button', 'lot-chip mono', material.lot);
      lot.type = 'button';
      lot.title = 'Trace every case that used this lot';
      lot.addEventListener('click', () => {
        state.recallLot = material.lot;
        render();
        document.querySelector('.recall-result')?.scrollIntoView(
          { behavior: 'smooth', block: 'center' });
      });
      card.append(lot);
      if (material.expiry) {
        card.append(el('span', 'material-expiry mono', `exp ${material.expiry}`));
      }
      materials.append(card);
    }
    panel.append(materials);
  }

  if (record.steps.length > 0) {
    const timeline = el('ol', 'timeline');
    for (const step of record.steps) {
      const item = el('li', 'step');
      item.append(el('span', 'step-when mono', step.at.slice(0, 16).replace('T', ' ')));
      const body = el('div', 'step-body');
      body.append(el('span', 'step-name', step.step));
      const by = el('span', 'step-by', step.by);
      body.append(by);
      if (step.equipment) body.append(el('span', 'step-kit mono', step.equipment));
      if (step.program) body.append(el('span', 'step-kit mono', step.program));
      item.append(body);
      timeline.append(item);
    }
    panel.append(timeline);
  }

  if (record.missing.length > 0 && state.view === 'bench') {
    const missing = el('details', 'missing');
    missing.append(el('summary', undefined,
      `${record.missing.length} entries still outstanding`));
    const list = el('ul', 'missing-list');
    for (const entry of record.missing.slice(0, 12)) {
      list.append(el('li', 'missing-item', entry.label));
    }
    missing.append(list);
    panel.append(missing);
  }
  return panel;
}

function recallPanel(): HTMLElement {
  const result = findByLot(store, state.recallLot);
  const panel = el('section', 'panel recall-result');
  const head = el('div', 'panel-head');
  const title = el('h3', 'panel-title');
  title.append(document.createTextNode('Lot trace '));
  title.append(el('span', 'mono', result.lot));
  head.append(title);
  const close = el('button', 'btn btn-ghost', 'Close');
  close.type = 'button';
  close.addEventListener('click', () => { state.recallLot = ''; render(); });
  head.append(close);
  panel.append(head);

  if (result.matched === 0) {
    panel.append(el('p', 'panel-sub',
      'No case used this lot. An exact match only — a near miss would produce a ' +
      'confident notification of the wrong patients.'));
    return panel;
  }

  panel.append(el('p', 'panel-sub',
    `${result.matched} case${result.matched === 1 ? '' : 's'} · ` +
    `${result.delivered} already with a patient · ${result.inProduction} still in the lab`));

  const hits = el('div', 'hits');
  for (const hit of result.hits) {
    const row = el('button', 'hit');
    row.type = 'button';
    row.append(el('span', 'hit-case mono', hit.caseNumber));
    row.append(el('span', 'hit-where', `${hit.practiceName} · ${hit.doctorName}`));
    row.append(el('span', 'hit-patient mono', hit.patientInitials));
    row.append(el('span', `chip ${hit.delivered ? 'chip-critical' : 'chip-caution'}`,
      hit.delivered ? 'with a patient' : humanize(hit.status)));
    row.addEventListener('click', () => {
      state.caseId = hit.caseId;
      state.transcript = [];
      render();
    });
    hits.append(row);
  }
  panel.append(hits);

  const notify = el('div', 'notify');
  notify.append(el('h4', 'outbound-title', 'Practices to notify'));
  for (const practice of result.practicesToNotify) {
    const line = el('div', 'outbound-line');
    line.append(el('span', 'outbound-q',
      `${practice.practiceName} — ${practice.doctorName}`));
    line.append(el('span', 'outbound-key mono', practice.cases.join(', ')));
    notify.append(line);
  }
  panel.append(notify);
  return panel;
}

function section(title: string, subtitle?: string): HTMLElement {
  const panel = el('section', 'panel');
  const head = el('div', 'panel-head');
  head.append(el('h3', 'panel-title', title));
  panel.append(head);
  if (subtitle) panel.append(el('p', 'panel-sub', subtitle));
  return panel;
}

function emptyNote(text: string): HTMLElement {
  return el('p', 'empty', text);
}

render();
