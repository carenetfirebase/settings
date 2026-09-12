import test from 'node:test';
import assert from 'node:assert/strict';
import {
  VERIFICATION_LABELS, minFontSize, toCssVariables, touchTarget,
} from '../src/tokens.ts';

test('visitor surfaces meet the one-handed, moving, distracted minimums', () => {
  assert.ok(touchTarget.visitor >= 56);
  assert.ok(minFontSize.visitor >= 16);
  assert.ok(minFontSize.voice >= 18);
});

test('every verification level has visitor-facing wording', () => {
  assert.equal(VERIFICATION_LABELS.verified.text, 'Verified');
  assert.equal(VERIFICATION_LABELS.unknown.text, 'Not verified');
  for (const label of Object.values(VERIFICATION_LABELS)) {
    assert.ok(label.text.length > 0 && /^#|rgb/.test(label.color));
  }
});

test('tokens emit as CSS custom properties, including reduced motion', () => {
  const css = toCssVariables();
  assert.match(css, /--surface: #0A0A0B;/);
  assert.match(css, /--conflict: #B4501E;/);
  assert.match(css, /prefers-reduced-motion/);
});
