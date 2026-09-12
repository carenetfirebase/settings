import type { FactPack } from '../../truth-engine/src/types.ts';
import type { RealtimeSessionConfig, ToolDefinition } from './interfaces.ts';

/**
 * Tools available to the realtime session (§10.3). Anything the fact pack does
 * not cover goes through one of these, which is what keeps the sealed context
 * small enough to answer in under a second.
 */
export const VOICE_TOOLS: ToolDefinition[] = [
  {
    name: 'lookup_property_fact',
    description:
      'Look up a property fact that is not in PROPERTY_FACTS. Use this instead ' +
      'of guessing, always. Returns verified information or an explicit unknown.',
    parameters: {
      type: 'object',
      properties: { query: { type: 'string', description: "The visitor's question, verbatim" } },
      required: ['query'],
    },
  },
  {
    name: 'ask_the_agent',
    description:
      'Record a question for the listing agent when the answer is not available. ' +
      'Always offer this rather than leaving the visitor with nothing.',
    parameters: {
      type: 'object',
      properties: { question: { type: 'string' } },
      required: ['question'],
    },
  },
  {
    name: 'change_room',
    description: 'Update which room the visitor is standing in.',
    parameters: {
      type: 'object',
      properties: { room: { type: 'string' } },
      required: ['room'],
    },
  },
  {
    name: 'request_action',
    description: 'Record interest: a showing, documents, or contact with the agent.',
    parameters: {
      type: 'object',
      properties: {
        type: { type: 'string', enum: ['showing', 'documents', 'contact'] },
      },
      required: ['type'],
    },
  },
  {
    name: 'show_on_screen',
    description:
      'Put something on the visitor\'s phone: the floor plan, a photo, or the ' +
      'source document behind a fact.',
    parameters: {
      type: 'object',
      properties: {
        what: { type: 'string', enum: ['floor_plan', 'photo', 'source_document', 'gallery'] },
        reference: { type: 'string' },
      },
      required: ['what'],
    },
  },
];

export type InstructionContext = {
  agentName: string;
  brokerage?: string | null;
  roomName?: string | null;
};

/**
 * System instructions for the realtime session (§10.2).
 *
 * This instruction alone is insufficient — models drift — which is why it is
 * backed by the validator in §11.6. It is written to be read aloud in a
 * brokerage compliance review without anyone wincing.
 */
export function buildInstructions(pack: FactPack, ctx: InstructionContext): string {
  const unknownList = pack.unknown_keys.length > 0
    ? pack.unknown_keys.join(', ')
    : '(none)';

  return [
    `You are the AI guide for ${pack.address}, an open house listed by ` +
    `${ctx.agentName}${ctx.brokerage ? ` of ${ctx.brokerage}` : ''}.`,
    '',
    'GROUND RULES',
    '1. You may state a property-specific fact only if it appears in ' +
    'PROPERTY_FACTS below or is returned by a tool call.',
    '2. If a visitor asks something not covered there, say you do not have ' +
    'verified information about it and offer to ask the listing agent.',
    '3. Never estimate, infer, or generalise from typical homes. "Most homes ' +
    'this age have..." is forbidden.',
    '4. Facts listed under UNKNOWN_KEYS are confirmed-unknown. Say so plainly: ' +
    'the seller not having a record is a real answer, not a failure.',
    '5. Never soften, bury, or omit a disclosure. If a disclosed issue is ' +
    'relevant to what was asked, lead with it.',
    '6. Never assess neighbourhood safety, quality, demographics, or school ' +
    'quality. Name the schools that serve the address and stop there.',
    '7. Never advise on price, offers, investment merit, legality, or the ' +
    'condition of anything. Give the verified fact and hand the judgment to ' +
    `${ctx.agentName}.`,
    '8. Two sentences is the target, three the maximum. This is a conversation, ' +
    'not a brochure.',
    pack.is_demo
      ? '9. This is a demonstration property with fictional data. Say so if asked.'
      : '',
    '',
    ctx.roomName ? `The visitor is currently in: ${ctx.roomName}.` : '',
    '',
    `UNKNOWN_KEYS: ${unknownList}`,
  ].filter(Boolean).join('\n');
}

export function buildSessionConfig(
  pack: FactPack,
  ctx: InstructionContext & { propertyId: string; sessionId: string },
): RealtimeSessionConfig {
  return {
    propertyId: ctx.propertyId,
    sessionId: ctx.sessionId,
    instructions: buildInstructions(pack, ctx),
    factPack: pack,
    tools: VOICE_TOOLS,
  };
}

/**
 * Barge-in truncation (§10.4).
 *
 * The assistant turn is truncated at the *playback* position, not the
 * generation position. Truncating at generation leaves the model believing it
 * said things the visitor never heard, and the next turn answers a question
 * nobody asked.
 */
export function truncateAtPlayback(
  assistantText: string, playedMs: number, totalMs: number,
): string {
  if (totalMs <= 0 || playedMs >= totalMs) return assistantText;
  const fraction = Math.max(0, playedMs / totalMs);
  const cut = Math.floor(assistantText.length * fraction);
  const boundary = assistantText.lastIndexOf(' ', cut);
  return assistantText.slice(0, boundary > 0 ? boundary : cut).trimEnd();
}

/** Open-house VAD tuning (§10.4). Not user-configurable — we tune it centrally. */
export const VAD_SETTINGS = {
  threshold: 0.62,
  prefixPaddingMs: 500,
  silenceDurationMs: 700,
};
