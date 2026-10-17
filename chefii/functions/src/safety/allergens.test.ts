import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { checkIngredients, detectAllergens, isBlocked } from './allergens';

/** Same red-team set as test/domain/allergen_redteam_test.dart. Recall must be 100%. */
interface Fixture {
  mustDetect: Array<{ text: string; allergens: string[] }>;
  mustNotDetect: Array<{ text: string; allergens: string[] }>;
  restrictions: Array<{ text: string; restriction: string; blocked: boolean }>;
}
const fixture = JSON.parse(readFileSync(join(__dirname, '../../../test/fixtures/allergen_redteam.json'), 'utf8')) as Fixture;

describe('allergen red-team set', () => {
  it.each(fixture.mustDetect)('detects $allergens in "$text"', ({ text, allergens }) => {
    const found = detectAllergens(text);
    for (const a of allergens) expect([...found], `"${text}" should contain ${a}`).toContain(a);
  });
  it.each(fixture.mustNotDetect)('does not flag $allergens in "$text"', ({ text, allergens }) => {
    const found = detectAllergens(text);
    for (const a of allergens) expect([...found], `"${text}" flagged as ${a}`).not.toContain(a);
  });
  it.each(fixture.restrictions)('$restriction: "$text" blocked=$blocked', ({ text, restriction, blocked }) => {
    const conflicts = checkIngredients([{ name: text }], { allergies: [], intolerances: [], restrictions: [restriction], dislikes: [] });
    expect(isBlocked(conflicts)).toBe(blocked);
  });
});
