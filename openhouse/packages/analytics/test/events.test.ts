import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ATTENTION_TARGET, RETENTION_DAYS, TIER_LANGUAGE, attentionRatio, engagementTier,
} from '../src/events.ts';

test('engagement tiers match the architecture thresholds', () => {
  assert.equal(engagementTier({ durationMs: 60_000, questionCount: 1, hasIntentEvent: false }),
    'casual');
  assert.equal(engagementTier({ durationMs: 4 * 60_000, questionCount: 4, hasIntentEvent: false }),
    'engaged');
  assert.equal(engagementTier({ durationMs: 10 * 60_000, questionCount: 9, hasIntentEvent: false }),
    'serious');
});

test('any intent event makes a session serious regardless of length', () => {
  assert.equal(engagementTier({ durationMs: 30_000, questionCount: 0, hasIntentEvent: true }),
    'serious');
});

test('tiers are reported in plain language, never as a score', () => {
  for (const phrase of Object.values(TIER_LANGUAGE)) {
    assert.ok(!/\d/.test(phrase), `"${phrase}" reads like a score`);
  }
});

test('the attention ratio is measurable against the 95/5 target', () => {
  assert.equal(attentionRatio(60_000, 600_000), 0.1);
  assert.ok(attentionRatio(60_000, 600_000) < ATTENTION_TARGET);
  assert.equal(attentionRatio(0, 0), 0);
});

test('raw audio is never retained', () => {
  assert.equal(RETENTION_DAYS.raw_audio, 0);
  assert.equal(RETENTION_DAYS.transcripts, 90);
});
