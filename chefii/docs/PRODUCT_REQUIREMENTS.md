# Chefii — Product Requirements

**Promise:** *Your kitchen, beautifully taken care of.*
**Platforms:** iOS and Android (Flutter), plus a web build used for the professional portal.
**Initial market:** Canada (English first; French planned).
**Positioning:** premium culinary, nutrition, wellness and household intelligence.

## Who it's for

The launch audience is affluent, time-conscious people who value convenience, good food, wellness, elegant design and an organised home. Marketing leads with women 30–55; the product is usable by any household (single, couple, family) and avoids gendered assumptions.

## The core problem

People don't know what's in their kitchen, so they waste food, repeat shopping, and default to the same meals. Inventory apps fail because keeping counts accurate takes too much typing.

**Chefii's differentiator** is an inventory that stays reasonably accurate with almost no manual work:

| Source of change | How Chefii captures it | User effort |
|---|---|---|
| Groceries in | Receipt photo → AI extraction → one review screen | ~1 minute per shop |
| Cooking | Recipe ingredients → one "what did you use?" confirmation | 1 tap |
| Ad-hoc use | "I used two eggs" (voice/text), or − on an item | Seconds |
| Waste | Discard / mark empty, with Undo | 1 tap |
| Drift | "Quick check" reconciliation of uncertain items | Occasional |

## Product principles (acceptance criteria)

1. **Half-asleep simple** — every screen has one obvious primary action.
2. **Premium** — quiet-luxury visual system (see ARCHITECTURE §Design).
3. **Anticipates** — Today screen suggests the right meal for the time and stock.
4. **Daily useful** — Today, Kitchen and Journal are worth opening every day.
5. **Aspirational** — editorial typography and illustration, never clinical.
6. **Trustworthy** — nutrition is education, always labelled as an estimate, evidence-cited.
7. **Secure** — health data private by default, sharing explicit and revocable.
8. **Fast** — common actions under three taps; offline-first local data.
9. **Respectful** — no body shaming, no forced targets, calories off by default.
10. **One system** — kitchen, cooking, plan, shopping and journal update one another.

## Functional scope

The 80 screens are specified in [SCREEN_INVENTORY.md](SCREEN_INVENTORY.md). Capability areas:

- **Onboarding (01–08):** account, household, dietary safety (explicit "not provided" status), culinary and wellness preferences, kitchen setup.
- **Today (09–11):** greeting, featured meal for current time and available minutes, kitchen summary, reminders, notifications.
- **Receipts (12–20):** capture (platform document scanner where available), preview/rotate, server AI extraction, deterministic validation, review/correct/unknown items, storage assignment, idempotent import, duplicate detection, undo.
- **Kitchen (21–28):** inventory by location, item detail with ledger history, quick adjust, add (search/barcode), fridge scan with confirmation, freshness centre, reconciliation.
- **AI Chef & cooking (29–38):** chat, preferences, recommendations, recipe detail with safety + availability, substitutions, prep checklist, guided steps with read-aloud and timers, single ingredient confirmation, meal completion with leftovers.
- **Mornings (39–44):** routine, alarm, evening preview, wake screen, checklist, running late.
- **Plan, shop, nutrition (45–52):** weekly planner, assign, leftovers, smart shopping list, item detail, nutrition dashboard, food journal, spending & waste.
- **Discover & rhythm (53–60):** discover, journal timeline, quick entry, reminders, patterns, opt-in glucose journal (no interpretation).
- **Nutrition intelligence & professionals (61–70):** insights, hair/skin/nails notebook, evidence library, nutrient detail, Smile & Food, dental history, nutrition circle, sharing permissions, professional dashboard, professional assessment.
- **Account (71–80):** profile, household, privacy, connected services, membership, accessibility, security, help, legal, export & deletion.

## Non-goals (for launch)

- Diagnosis, treatment, dosing, glucose prediction or alarms.
- Grocery ordering/delivery.
- Paid subscriptions (deferred until core is stable — see FEATURE_STATUS).
- Social feeds.

## Success measures

- ≥ 70% of receipt lines import without edits (tracked via `receipt_imported` + edit counts, aggregated).
- Median receipt review under 90 seconds.
- ≥ 60% of cooked meals confirmed with zero ingredient edits.
- Weekly active households, D30 retention, and "to verify" item count trending down per household.
