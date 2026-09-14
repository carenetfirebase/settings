export type BoundaryKind =
  | 'clinical_judgment'   // diagnosis, treatment planning, prognosis
  | 'clinical_technique'  // how to prep, how much to reduce, how to seat
  | 'rx_deviation'        // asking the lab to change the prescribed device
  | 'patient_direct'      // a patient, not a clinician, asking about their device
  | 'regulatory_opinion'  // "are we compliant?"
  | 'billing_advice'      // what to submit to an insurer
  | 'phi_exposure';       // a request that would expose protected information

export type BoundaryHit = { kind: BoundaryKind; rule: string; matched: string };

export type BoundaryVerdict =
  | { allowed: true }
  | {
      allowed: false;
      hit: BoundaryHit;
      /** A fixed template. Reviewable by the lab's adviser; cannot drift. */
      template: string;
      /** Facts the reply may still offer, so nobody is left with nothing. */
      offerFactKeys: string[];
      /** Whether a person at the lab should see this exchange. */
      escalate: boolean;
    };

export type AnswerCheck = { ok: boolean; flags: BoundaryHit[] };
