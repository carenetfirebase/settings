/* The category-count ring. docs/UI_SPEC.md correction #7.
 *
 * "This is what distinguishes real convergence from one loud source, and it is
 * the most important pixel on the dashboard."
 *
 * Ten segments, one per evidence bucket, filled when that bucket cleared τ. A
 * 94 backed by one category and a 94 backed by five produce the same number
 * and must not produce the same picture — the ring is what makes the
 * difference visible before the number is read.
 *
 * The count is deliberately NOT the number of radar axes. The radar shows six
 * dimensions; the ring counts across all ten buckets. API_CONTRACT is explicit
 * that these are different numbers and the UI must not conflate them.
 *
 * Colour is not the only carrier: the filled count is also printed as text,
 * because red/green sits directly on the most common colour-vision deficiency
 * (UI_SPEC §6).
 */

export interface CategoryCountRingProps {
  cleared: number;
  total: number;
  size?: number;
  /** Rendered in the middle. Usually Research Priority. */
  children?: React.ReactNode;
}

const GAP_DEGREES = 4;

export function CategoryCountRing({
  cleared,
  total,
  size = 180,
  children,
}: CategoryCountRingProps) {
  const radius = size / 2 - 8;
  const centre = size / 2;
  const segment = 360 / total;

  const arc = (index: number) => {
    const start = index * segment - 90 + GAP_DEGREES / 2;
    const end = (index + 1) * segment - 90 - GAP_DEGREES / 2;
    const toXY = (deg: number) => {
      const rad = (deg * Math.PI) / 180;
      return [centre + radius * Math.cos(rad), centre + radius * Math.sin(rad)];
    };
    const [x1, y1] = toXY(start);
    const [x2, y2] = toXY(end);
    return `M ${x1} ${y1} A ${radius} ${radius} 0 0 1 ${x2} ${y2}`;
  };

  return (
    <div
      className="relative inline-flex items-center justify-center"
      style={{ width: size, height: size }}
    >
      <svg
        width={size}
        height={size}
        role="img"
        aria-label={`${cleared} of ${total} evidence categories cleared the convergence threshold`}
      >
        {Array.from({ length: total }, (_, i) => (
          <path
            key={i}
            d={arc(i)}
            fill="none"
            strokeWidth={6}
            strokeLinecap="round"
            stroke={i < cleared ? "var(--positive)" : "var(--border-strong)"}
          />
        ))}
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        {children}
        <span className="mono text-caption" style={{ color: "var(--text-secondary)" }}>
          {cleared} of {total} categories
        </span>
      </div>
    </div>
  );
}
