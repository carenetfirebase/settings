/**
 * Response shapes of the research API, mirroring src/invest/api/schemas.py.
 *
 * `null` always means "could not be computed or retrieved", never zero. The
 * UI must keep that distinction visible (see lib/format.ts).
 */

export interface Meta {
  as_of: string | null;
  generated_at: string;
  model_version: string | null;
  note: string | null;
}

export interface HealthResponse {
  status: string;
  database: string;
  version: string;
  read_only: boolean;
}

export interface SecuritySummary {
  ticker: string;
  name: string;
  cik: string | null;
  exchange: string | null;
  sector: string | null;
  currency: string;
  is_financial: boolean;
  entity_id: number;
  security_id: number;
  data_quality_flag: string;
}

export interface UniverseResponse {
  meta: Meta;
  count: number;
  securities: SecuritySummary[];
}

export interface PriceBar {
  obs_date: string;
  open: number | null;
  high: number | null;
  low: number | null;
  close: number | null;
  volume: number | null;
  source: string;
}

export interface PriceResponse {
  meta: Meta;
  ticker: string;
  count: number;
  adjustment_note: string;
  bars: PriceBar[];
}

export interface Fundamental {
  metric_name: string;
  value: number | null;
  unit: string;
  period_start: string | null;
  period_end: string;
  fiscal_year: number | null;
  fiscal_period: string | null;
  filed_date: string;
  form_type: string | null;
  accession_number: string | null;
  data_quality_flag: string;
  value_type: string;
}

export interface FundamentalsResponse {
  meta: Meta;
  ticker: string;
  metrics_available: Record<string, number>;
  metrics_missing: string[];
  series: Record<string, Fundamental[]>;
}

export interface ScoreComponent {
  name: string;
  value: number | null;
  weight: number;
  detail: string;
  unavailable_reason: string | null;
}

export interface Score {
  name: string;
  value: number | null;
  coverage: number;
  reliable: boolean;
  warnings: string[];
  components: ScoreComponent[];
}

export interface AnalysisResponse {
  meta: Meta;
  ticker: string;
  name: string;
  cik: string | null;
  price: number | null;
  investment_quality: Score;
  trade_setup: Score;
  confidence: Score;
  components: Record<string, unknown>;
  inputs: Record<string, unknown>;
  warnings: string[];
  premium_data_dependent: string[];
}

export interface ReportResponse {
  ticker: string;
  as_of: string;
  report_text: string;
}

export interface Snapshot {
  id: number;
  ticker: string | null;
  snapshot_date: string;
  as_of_date: string;
  model_version: string;
  investment_quality_score: number | null;
  trade_setup_score: number | null;
  confidence_score: number | null;
  created_at: string;
}

export interface SnapshotsResponse {
  meta: Meta;
  count: number;
  snapshots: Snapshot[];
}

export interface Conflict {
  id: number;
  table_name: string;
  metric_name: string | null;
  obs_date: string | null;
  conflict_type: string;
  severity: string;
  source_a: string | null;
  value_a: number | null;
  source_b: string | null;
  value_b: number | null;
  detail: string | null;
  resolved: boolean;
  detected_at: string;
}

export interface ConflictsResponse {
  meta: Meta;
  count: number;
  conflicts: Conflict[];
}

export interface InsiderTransaction {
  insider_name: string;
  officer_title: string | null;
  is_director: boolean | null;
  is_officer: boolean | null;
  transaction_date: string;
  filed_date: string;
  disclosure_lag_days: number;
  transaction_code: string | null;
  code_meaning: string;
  is_discretionary: boolean;
  acquired_disposed: string | null;
  shares: number | null;
  price_per_share: number | null;
  is_derivative: boolean;
}

export interface InsiderResponse {
  meta: Meta;
  ticker: string;
  total_filings: number;
  discretionary_trades: number;
  buys: number;
  sells: number;
  buy_value: number;
  sell_value: number;
  net_buy_ratio: number | null;
  interpretation_note: string;
  transactions: InsiderTransaction[];
}

export interface Disclosure {
  politician_name: string;
  chamber: string | null;
  transaction_type: string | null;
  transaction_date: string;
  disclosure_date: string;
  disclosure_lag_days: number;
  amount_range_low: number | null;
  amount_range_high: number | null;
  ticker_raw: string | null;
  asset_description: string | null;
}

export interface DisclosuresResponse {
  meta: Meta;
  ticker: string;
  firewall_status: string;
  firewall_note: string;
  count: number;
  median_disclosure_lag_days: number | null;
  disclosures: Disclosure[];
}

export interface RegimeSignal {
  name: string;
  value: number | null;
  direction: number | null;
  detail: string;
  unavailable_reason: string | null;
}

export interface RegimeResponse {
  meta: Meta;
  regime: string;
  risk_score: number | null;
  coverage: number;
  reliable: boolean;
  signals: RegimeSignal[];
  note: string;
}

export interface StatsResponse {
  tables: Record<string, number>;
  generated_at: string;
}
