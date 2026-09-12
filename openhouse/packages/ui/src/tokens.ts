/**
 * Design tokens (§15.1).
 *
 * Photography dominates; the interface recedes. The serif display face is
 * doing real work here — it is the difference between "real estate tech" and
 * "a beautiful home".
 */
export const color = {
  surface: '#0A0A0B',        // near-black, for voice surfaces
  surfaceRaised: '#141416',
  paper: '#FAFAF8',          // warm off-white, for the agent console
  ink: '#111112',
  inkMuted: '#6B6B70',
  line: 'rgba(0,0,0,0.08)',
  lineDark: 'rgba(255,255,255,0.10)',
  accent: '#1B4D3E',         // overridden per agent brand; one accent, used sparingly
  verified: '#1F7A4D',       // never badge-green, always subtle
  unknown: '#8A8A90',
  conflict: '#B4501E',       // warm, not alarm-red
} as const;

export const font = {
  display: "'Instrument Serif', 'Canela', Georgia, serif",
  ui: "'Inter Tight', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
} as const;

export const fontSize = [12, 14, 16, 20, 28, 40, 64] as const;

/**
 * Voice surfaces are read at arm's length by someone walking through a house.
 * Nothing on a visitor surface goes below 16px, and the live session goes no
 * lower than 18.
 */
export const minFontSize = { visitor: 16, voice: 18 } as const;

export const space = [4, 8, 12, 16, 24, 32, 48, 64, 96] as const;

export const radius = { input: 2, card: 8, pill: 999 } as const;

/** One elevation only; prefer lines to shadows. */
export const shadow = { raised: '0 1px 2px rgba(0,0,0,0.06), 0 8px 24px rgba(0,0,0,0.06)' } as const;

export const motion = {
  standard: '180ms cubic-bezier(0.2, 0, 0, 1)',
  surface: '320ms cubic-bezier(0.2, 0, 0, 1)',
} as const;

/** One-handed, moving, distracted. 56px is not generous, it is necessary. */
export const touchTarget = { visitor: 56, console: 40 } as const;

export type VerificationLabel =
  | 'verified' | 'seller_provided' | 'agent_commentary' | 'public' | 'unknown';

/** What the visitor reads under a value (§7.2). Wording is part of the contract. */
export const VERIFICATION_LABELS: Record<VerificationLabel, { text: string; color: string }> = {
  verified:         { text: 'Verified',           color: color.verified },
  seller_provided:  { text: 'Seller provided',    color: color.inkMuted },
  agent_commentary: { text: 'Agent commentary',   color: color.inkMuted },
  public:           { text: 'Public information', color: color.inkMuted },
  unknown:          { text: 'Not verified',       color: color.unknown },
};

export function toCssVariables(): string {
  const lines = [
    ':root {',
    ...Object.entries(color).map(([k, v]) => `  --${kebab(k)}: ${v};`),
    `  --font-display: ${font.display};`,
    `  --font-ui: ${font.ui};`,
    ...space.map((s, i) => `  --space-${i}: ${s}px;`),
    ...fontSize.map((s) => `  --text-${s}: ${s}px;`),
    `  --radius-input: ${radius.input}px;`,
    `  --radius-card: ${radius.card}px;`,
    `  --radius-pill: ${radius.pill}px;`,
    `  --shadow-raised: ${shadow.raised};`,
    `  --motion-standard: ${motion.standard};`,
    `  --motion-surface: ${motion.surface};`,
    `  --target-visitor: ${touchTarget.visitor}px;`,
    '}',
    '',
    '@media (prefers-reduced-motion: reduce) {',
    '  /* The orb is amplitude-reactive; for reduced motion it becomes a static',
    '     state indicator rather than an animation. */',
    '  * { animation-duration: 0.01ms !important; transition-duration: 0.01ms !important; }',
    '}',
  ];
  return lines.join('\n');
}

function kebab(name: string): string {
  return name.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);
}
