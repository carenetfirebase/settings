/**
 * Typed analytics events (§13).
 *
 * Events and topics, not surveillance: no device fingerprinting, no
 * cross-property tracking without an account, no third-party analytics on
 * visitor surfaces, and no raw audio, ever.
 */
export type EventName =
  // Session
  | 'session_started' | 'audio_mode_selected' | 'mic_permission_granted'
  | 'mic_permission_denied' | 'tour_mode_selected' | 'pocket_mode_entered'
  | 'pocket_mode_exited' | 'session_paused' | 'session_resumed' | 'session_ended'
  // Navigation
  | 'room_entered' | 'tour_stop_reached' | 'tour_completed' | 'screen_viewed'
  | 'floorplan_opened' | 'gallery_opened'
  // Conversation
  | 'question_asked' | 'answer_delivered' | 'interruption' | 'unknown_answer'
  | 'agent_question_created' | 'source_viewed'
  // Intent
  | 'showing_requested' | 'documents_requested' | 'agent_contact_requested'
  | 'property_saved' | 'property_shared' | 'contact_submitted'
  // Health
  | 'audio_disconnected' | 'reconnect_attempted' | 'degraded_to_text'
  | 'error_shown' | 'validator_blocked';

export type EventProps = {
  room_entered: { method: 'nfc' | 'qr' | 'manual' | 'inferred'; room: string };
  question_asked: {
    category: string; fact_keys: string[]; retrieval_path: string; was_answered: boolean;
  };
  answer_delivered: { verification_level: string | null; latency_ms: number };
  unknown_answer: { fact_key: string | null; reason: string | null };
  validator_blocked: { rules: string[] };
  audio_mode_selected: { mode: 'private' | 'group' | 'silent'; device?: string };
  degraded_to_text: { reason: 'reconnect_failed' | 'tts_unavailable' | 'mic_denied' };
};

export type ClientContext = {
  platform: string;
  browser: string;
  audio_mode: 'private' | 'group' | 'silent' | null;
  connection_quality: 'good' | 'fair' | 'poor' | null;
};

export type AnalyticsEvent<N extends EventName = EventName> = {
  event_id: string;
  session_id: string;
  property_id: string;
  open_house_id?: string;
  name: N;
  ts: string;
  room_id?: string;
  props: N extends keyof EventProps ? EventProps[N] : Record<string, unknown>;
  client: ClientContext;
};

export type EngagementTier = 'casual' | 'engaged' | 'serious';

/**
 * Engagement is shown to the agent as plain language — "8 visitors explored in
 * depth" — never as a lead score. A score implies precision we do not have and
 * creates a discrimination surface we do not want (§13.4).
 */
export function engagementTier(input: {
  durationMs: number; questionCount: number; hasIntentEvent: boolean;
}): EngagementTier {
  const minutes = input.durationMs / 60_000;
  if (input.hasIntentEvent || minutes > 8 || input.questionCount >= 7) return 'serious';
  if (minutes >= 2 || input.questionCount >= 2) return 'engaged';
  return 'casual';
}

export const TIER_LANGUAGE: Record<EngagementTier, string> = {
  casual: 'looked around briefly',
  engaged: 'explored the home',
  serious: 'explored in depth',
};

/**
 * The 95/5 attention target as a measurable number (§3.3). If visitors look at
 * their phones for more than about 15% of a tour, the voice experience is
 * failing and we should know without asking anyone.
 */
export function attentionRatio(screenVisibleMs: number, sessionDurationMs: number): number {
  if (sessionDurationMs <= 0) return 0;
  return Math.min(1, screenVisibleMs / sessionDurationMs);
}

export const ATTENTION_TARGET = 0.15;

/** Retention policy (§13.6), expressed as data so the purge job cannot drift from it. */
export const RETENTION_DAYS = {
  raw_audio: 0,            // never persisted; streamed, not stored
  transcripts: 90,         // PII-scrubbed
  question_text: 730,
  events: 730,
  answer_ledger: 730,
} as const;
