# Operating Costs

Pricing changes often; **verify every unit price against current provider pricing pages** before budgeting. This document gives the cost model and the levers. The numbers below are placeholders for planning, not quotes.

## Cost drivers per active household per month (model)

| Driver | Assumed volume | Unit cost (verify) | Notes |
|---|---|---|---|
| Receipt extraction (vision) | 6 receipts × 1–2 pages | provider $/image + $/token | Largest AI cost; one call per receipt |
| Fridge scans | 2 | as above | |
| Chef recommendations | 15 | $/1k tokens | about 2–4k input tokens (inventory context) + 2k output |
| Chat turns | 20 | $/1k tokens | history capped at 20 messages |
| Meal estimates | 10 | $/1k tokens | small |
| Firestore | ~3k reads, ~600 writes | Firestore pricing | Streams scoped to active lots and recent docs |
| Storage | ~10 MB of receipt images | per GB-month + egress | Lifecycle rule recommended: delete receipt images after 90 days |
| Functions | ~60 invocations | per invocation and GB-s | 1 GiB memory for image calls |

Formula: `monthly AI cost ≈ Σ_tasks calls × (input_tokens × in_price + output_tokens × out_price + images × image_price)`. The `aiUsage` collection records the token counts needed to compute this from real usage.

## Guardrails in code

- Per-user daily quotas (`functions/src/config.ts › DAILY_LIMITS`): receipt 40, scan 60, chef 80, chat 200, meal estimate 120.
- Images routed only to the primary provider; no duplicate calls across providers.
- Inventory context capped at 80 items; chat history at 20 turns; recipes at 5 per request.
- No speculative AI calls: every AI call is triggered by a user action.
- Optional provider off by default (`OPENAI_ENABLED=false`).

## Recommended operations

- GCP budget alerts at 50/90/100% of the monthly budget; a daily cost dashboard from `aiUsage` (BigQuery export).
- Storage lifecycle: delete `households/*/receipts/*` images 90 days after import (extracted lines are kept).
- Cache identical receipt images by hash (already deduplicated client-side before upload).
- Re-evaluate models quarterly on the receipt evaluation set for cost and accuracy.
