import { FACT_BY_KEY } from '../../fact-catalog/src/index.ts';

/**
 * The conversation frame (§11.3).
 *
 * A small structured object in session state, not raw message history. It
 * survives a model swap and it is inspectable in the ledger when something goes
 * wrong, which raw history is not.
 */
export type Frame = {
  room?: string | null;
  /** The dotted key suffix under discussion: 'install_year', 'material'. */
  topic?: string | null;
  lastFactKeys: string[];
};

export const emptyFrame = (): Frame => ({ room: null, topic: null, lastFactKeys: [] });

/** The trailing segment of a fact key is what "what about X?" carries forward. */
export function topicOf(factKey: string): string | null {
  const parts = factKey.split('.');
  return parts.length >= 2 ? parts.at(-1)! : null;
}

export function roomOf(factKey: string): string | null {
  const head = factKey.split('.')[0];
  return ['kitchen', 'basement', 'bathrooms'].includes(head) ? head : null;
}

export function advanceFrame(frame: Frame, resolvedKeys: string[]): Frame {
  if (resolvedKeys.length === 0) return frame;
  const primary = resolvedKeys[0];
  return {
    // The room follows the new fact key. Asking about the furnace after asking
    // about the fridge leaves the kitchen behind, which is what the visitor did.
    room: roomOf(primary),
    topic: topicOf(primary) ?? frame.topic ?? null,
    lastFactKeys: resolvedKeys,
  };
}

const ELLIPTICAL =
  /^(what about|how about|and|what of)\s+(the\s+|a\s+)?([a-z][a-z0-9 '-]*)\??$/i;

/**
 * Resolve an elliptical follow-up against the frame.
 *
 * "What about the dishwasher?" carries topic=install_year from the previous
 * turn, so it resolves to kitchen.appliance.dishwasher.install_year — and, when
 * that fact does not exist, to an honest unknown rather than to the fridge's
 * answer repeated.
 */
export function resolveElliptical(question: string, frame: Frame): string[] {
  const match = question.trim().match(ELLIPTICAL);
  if (!match || !frame.topic) return [];

  const subject = match[3].toLowerCase().trim().replace(/\s+/g, '_').replace(/s$/, '');
  if (subject.length < 3) return [];

  const candidates: string[] = [];
  for (const key of FACT_BY_KEY.keys()) {
    if (!key.endsWith(`.${frame.topic}`)) continue;
    if (!key.includes(subject)) continue;
    candidates.push(key);
  }

  // Prefer a key in the room the visitor was already discussing.
  candidates.sort((a, b) => {
    const aRoom = frame.room && a.startsWith(`${frame.room}.`) ? 0 : 1;
    const bRoom = frame.room && b.startsWith(`${frame.room}.`) ? 0 : 1;
    return aRoom - bRoom || a.length - b.length;
  });
  return candidates.slice(0, 3);
}
