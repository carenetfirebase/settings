import test from 'node:test';
import assert from 'node:assert/strict';
import { buildDemoProperty, DEMO_PROPERTY_ID }
  from '../../../fixtures/demo-property/maple-crescent.ts';
import { createTruthEngine } from '../../truth-engine/src/engine.ts';
import {
  VAD_SETTINGS, VOICE_TOOLS, buildInstructions, buildSessionConfig, truncateAtPlayback,
} from '../src/voice-session.ts';

const pack = createTruthEngine(buildDemoProperty()).buildFactPack(DEMO_PROPERTY_ID);
const ctx = { agentName: 'Sarah Thompson', brokerage: 'Thompson Real Estate Group' };

test('the instructions name the rules the validator enforces', () => {
  const text = buildInstructions(pack, ctx);
  assert.match(text, /only if it appears in PROPERTY_FACTS/);
  assert.match(text, /Never estimate, infer, or generalise/);
  assert.match(text, /Never soften, bury, or omit a disclosure/);
  assert.match(text, /Never assess neighbourhood safety/);
  assert.match(text, /Sarah Thompson/);
});

test('confirmed unknowns are listed explicitly in the session context', () => {
  const text = buildInstructions(pack, ctx);
  assert.match(text, /UNKNOWN_KEYS:/);
  assert.match(text, /exterior\.windows\.replacement_year/);
});

test('a demo property tells the visitor it is a demo', () => {
  assert.match(buildInstructions(pack, ctx), /demonstration property with fictional data/);
});

test('the session config seals the fact pack and exposes the five tools', () => {
  const config = buildSessionConfig(pack, {
    ...ctx, propertyId: DEMO_PROPERTY_ID, sessionId: 'session-1',
  });
  assert.equal(config.factPack, pack);
  assert.deepEqual(config.tools.map((t) => t.name).sort(), [
    'ask_the_agent', 'change_room', 'lookup_property_fact', 'request_action',
    'show_on_screen',
  ]);
  assert.equal(VOICE_TOOLS.length, 5);
});

test('barge-in truncates at what the visitor actually heard', () => {
  const spoken = 'The furnace was installed in 2019 and it was serviced last October.';
  const heard = truncateAtPlayback(spoken, 1200, 4000);
  assert.ok(spoken.startsWith(heard));
  assert.ok(heard.length < spoken.length);
  assert.ok(!heard.endsWith(' '), 'truncation lands on a word boundary');
  assert.equal(truncateAtPlayback(spoken, 4000, 4000), spoken);
});

test('VAD is tuned for a room full of people, not a quiet office', () => {
  assert.ok(VAD_SETTINGS.threshold > 0.5);
  assert.ok(VAD_SETTINGS.prefixPaddingMs >= 400);
  assert.ok(VAD_SETTINGS.silenceDurationMs >= 600);
});
