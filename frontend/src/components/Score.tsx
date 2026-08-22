/* Every 0-100 value on screen. docs/UI_SPEC.md §4.11, correction #6.
 *
 * A score without its provenance is indistinguishable from a magic number, so
 * provenance is a required prop rather than an optional embellishment. There
 * is no way to render a bare number through this component.
 *
 * A threshold-normalized score carries a dotted underline meaning
 * "unvalidated -- weights not yet backtested". For the whole of V1 that is
 * every score, which is the honest state of the system until Phase 8 produces
 * evidence (SPEC §6.8).
 */

export type NormalizationMethod = "percentile" | "fallback_threshold";

export interface ScoreProvenance {
  normalization: NormalizationMethod;
  weightsVersion: string;
  asOf: string;
  /** Up to three contributing features with raw values and units. */
  drivers?: { label: string; value: string }[];
}

export interface ScoreProps {
  value: number;
  provenance: ScoreProvenance;
  size?: "sm" | "md" | "lg";
  label?: string;
}

/** UI_SPEC §4.4: banded >=85 positive, 65-84 warning, <65 muted.
 *  These are research-priority bands, not trading bands. */
function band(value: number): string {
  if (value >= 85) return "var(--positive)";
  if (value >= 65) return "var(--warning)";
  return "var(--text-muted)";
}

const SIZES = { sm: 28, md: 36, lg: 44 } as const;

export function Score({ value, provenance, size = "md", label }: ScoreProps) {
  const px = SIZES[size];
  const validated = provenance.normalization === "percentile";
  // Integer for a normal 0-100 score, but one decimal below 10. V1 Research
  // Priority sits in the low single digits because DataQuality multiplies it
  // (SPEC §6.7), and rounding 0.14 to "0" next to rank #1 reads as a bug
  // rather than as the small number it honestly is.
  const rounded = value < 10 ? value.toFixed(1) : String(Math.round(value));

  const tooltip = [
    `${rounded} / 100`,
    `Normalization: ${validated ? "percentile" : "threshold fallback (unvalidated)"}`,
    `Weights: ${provenance.weightsVersion}`,
    `As of: ${provenance.asOf}`,
    ...(provenance.drivers ?? []).map((d) => `${d.label}: ${d.value}`),
  ].join("\n");

  return (
    <span
      className="inline-flex items-center gap-2"
      title={tooltip}
      tabIndex={0}
      role="img"
      aria-label={`${label ? label + " " : ""}${rounded} out of 100. ${
        validated ? "Percentile normalized." : "Threshold normalized, unvalidated."
      } Weights version ${provenance.weightsVersion}, as of ${provenance.asOf}.`}
    >
      <span
        className="mono inline-flex items-center justify-center rounded-full"
        style={{
          width: px,
          height: px,
          color: band(value),
          border: `2px solid ${band(value)}`,
          fontSize: size === "lg" ? "var(--text-value)" : "var(--text-body)",
          // Threshold-normalized scores are hypotheses. The dotted underline
          // is the visual marker UI_SPEC §4.11 defines as "unvalidated".
          borderBottomStyle: validated ? "solid" : "dotted",
        }}
      >
        {rounded}
      </span>
      {label ? <span className="text-caption text-secondary">{label}</span> : null}
    </span>
  );
}
