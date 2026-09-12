export type BoundaryKind =
  | 'fair_housing'
  | 'valuation'
  | 'investment_advice'
  | 'offer_strategy'
  | 'legal_conclusion'
  | 'inspection_conclusion'
  | 'permit_assertion';

export type BoundaryHit = {
  kind: BoundaryKind;
  /** The specific rule that fired, for the ledger and for counsel's review. */
  rule: string;
  matched: string;
};

export type BoundaryVerdict =
  | { allowed: true }
  | {
      allowed: false;
      hit: BoundaryHit;
      /**
       * A fixed template, not a generated response. Templates are reviewable by
       * counsel and cannot drift (§12.2).
       */
      template: string;
      /** Facts the answer may still offer alongside the refusal. */
      offerFactKeys: string[];
    };

export type AnswerCheck = {
  ok: boolean;
  flags: BoundaryHit[];
};
