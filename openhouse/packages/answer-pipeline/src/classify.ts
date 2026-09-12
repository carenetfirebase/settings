export type Intent =
  | 'property_fact' | 'room_info' | 'document_request' | 'agent_request'
  | 'action' | 'boundary' | 'smalltalk' | 'unclear';

export type Classification = {
  intent: Intent;
  /** Set when the question cannot be answered without knowing where the visitor is. */
  needsRoomContext: boolean;
};

/**
 * Step 2 of the pipeline (§11).
 *
 * Rule-based rather than model-based on purpose: it runs on every turn inside
 * the latency budget, it is deterministic in the ledger, and its failure mode
 * ('unclear') is safe. A model classifier can be swapped in behind the same
 * signature when there is evidence it earns its latency.
 */
export function classify(question: string): Classification {
  const text = question.trim().toLowerCase();

  if (/^(hi|hello|hey|thanks|thank you|goodbye|bye|cool|nice|ok|okay)\b/.test(text) ||
      /^(how are you|what'?s your name|are you (a )?(real|human|robot|ai))/.test(text)) {
    return { intent: 'smalltalk', needsRoomContext: false };
  }

  if (/\b(book|schedule|arrange) (a )?(showing|viewing|second look)|come back|see it again/.test(text)) {
    return { intent: 'action', needsRoomContext: false };
  }
  if (/\b(send|email|share|can i (see|get)|do you have) (me )?(the )?(documents?|disclosure|report|floor ?plan|permits?|invoice)/.test(text)) {
    return { intent: 'document_request', needsRoomContext: false };
  }
  if (/\b(ask|tell|talk to|speak (to|with)|contact|get) (the )?(agent|realtor|sarah)|have (them|her|him) (call|contact|email)/.test(text)) {
    return { intent: 'agent_request', needsRoomContext: false };
  }

  // "What's behind this door?" is unanswerable without visual context (§11.4).
  if (/\b(this|that|these|those|here)\b.*\b(door|wall|room|window|switch|thing|fixture|unit)\b/.test(text) ||
      /^what'?s (behind|through|above|under|in) (this|that|here)/.test(text)) {
    return { intent: 'unclear', needsRoomContext: true };
  }

  if (/\b(which room|what room|where am i|how big is this room|what'?s this room)\b/.test(text)) {
    return { intent: 'room_info', needsRoomContext: true };
  }

  return { intent: 'property_fact', needsRoomContext: false };
}
