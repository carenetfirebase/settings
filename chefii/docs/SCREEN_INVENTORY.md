# Screen Inventory

All 80 screens exist and are routed. "Presentation" is a go_router path unless noted (sheet/dialog). Every screen uses the shared loading, empty and error components; the widget smoke test (`test/widget/app_smoke_test.dart`) renders every route without exceptions, and key routes again at 160% text size.

Code lives in `lib/features/<area>/`. Analytics events are defined in `lib/core/services/analytics.dart` (privacy-filtered).

## A. Onboarding — `features/onboarding/onboarding_screens.dart`

| # | Screen | Presentation | Primary action | Data | Notes |
|---|---|---|---|---|---|
| 01 | Welcome | `/welcome` | Get started | — | Illustration, not photography |
| 02 | Meet your chef | `/onboarding/meet` | Continue | curated recipe | Skip available |
| 03 | Account | `/onboarding/account` | Create account / Sign in | AuthService, consents | Apple (iOS/Android), Google, email; demo account in demo mode; terms/privacy consent recorded |
| 04 | Your household | `/onboarding/household` | Continue | HouseholdRepository | Type, portions, name; join by invite code (online mode) |
| 05 | Dietary safety | `/onboarding/dietary` (edit: `/you/dietary`) | Continue | dietary profile | Explicit Yes / None known / Prefer not to say; Continue disabled until answered |
| 06 | Culinary preferences | `/onboarding/culinary` | Continue | profile.culinary | Cuisines, foods, confidence, spice, time, equipment |
| 07 | Wellness preferences | `/onboarding/wellness` | Continue | wellness | Calories off by default |
| 08 | Build your kitchen | `/onboarding/kitchen` | (options) | actions | Receipt, scan, manual, example ingredients |

## B. Today — `features/today/today_screens.dart`

| # | Screen | Presentation | Primary action |
|---|---|---|---|
| 09 | Today dashboard | `/today` (tab) | Start cooking (featured) / Scan a receipt |
| 10 | Daily briefing | `/today/briefing` | Plan today's meals (when empty) |
| 11 | Notification centre | `/today/notifications` | Mark all read |

## C. Receipts — `features/receipts/receipt_screens.dart`

| # | Screen | Presentation | Primary action | Key states |
|---|---|---|---|---|
| 12 | Capture receipt | `/receipt/capture` | Scan receipt | doc scanner → camera fallback; permission denied |
| 13 | Preview | `/receipt/preview` | Analyze receipt | rotate, retake, remove, add page; validation errors; duplicate |
| 14 | Processing | `/receipt/:id/processing` | Cancel | live progress, continue in background, deep-linkable |
| 15 | Review purchases | `/receipt/:id/review` | Continue / Resolve n items | totals check, confidence tags, exclude toggles |
| 16 | Correct item | bottom sheet | Save | name, brand, package, quantity+unit, category, storage, food/non-food |
| 17 | Unknown items | `/receipt/:id/unknown` | Continue | fix / looks right / not food / leave out |
| 18 | Storage assignment | `/receipt/:id/storage` | Add n items to kitchen | idempotent import |
| 19 | Error / duplicate | `/receipt/:id/error` | Retake / Try again / View earlier | quality vs. service errors |
| 20 | Import complete | `/receipt/:id/done` | View kitchen | counts, estimates, Undo import |
| — | Receipts list | `/kitchen/receipts` | Scan a receipt | history, resume any state |

## D. Kitchen — `features/kitchen/`

| # | Screen | Presentation | Primary action |
|---|---|---|---|
| 21 | My kitchen | `/kitchen` (tab) | Scan a receipt |
| 22 | Storage location | `/kitchen/location/:id` | Verify these items |
| 23 | Ingredient details | `/kitchen/item/:id` | Update amount |
| 24 | Quick adjust | sheet (`kitchen_sheets.dart`) | Use / Add / Discard / Set count; Mark finished; voice & text command sheet |
| 25 | Add product | `/kitchen/add` | Add to kitchen (search, barcode) |
| 26 | Fridge/pantry scan | `/kitchen/scan` | Take a photo → Add n items |
| 27 | Freshness centre | `/kitchen/freshness` | Find recipes that use these |
| 28 | Reconciliation | `/kitchen/reconcile` | Confirm all |

## E. AI Chef & cooking — `features/chef/`, `features/cooking/`

| # | Screen | Presentation | Primary action |
|---|---|---|---|
| 29 | Chef home (chat) | `/chef` | Send |
| 30 | Chef preferences | `/chef/preferences` | Show me recipes |
| 31 | Recommendations | `/chef/results` | Try another |
| 32 | Recipe details | `/recipe/:id` | Start cooking (disabled if unsafe) |
| 33 | Smart substitutions | sheet | Use this |
| 34 | Preparation checklist | `/cook/:id/prep` | Begin cooking |
| 35 | Guided cooking | `/cook/:id` | Next step / Finish cooking |
| 36 | Cooking timers | `/cook/timers` (+ strip in 35) | Start timer |
| 37 | Confirm ingredients used | `/cook/:id/confirm` | Confirm and update kitchen |
| 38 | Meal complete | `/cook/:id/done` | Finish |

## F. Mornings — `features/morning/morning_screens.dart`

| # | Screen | Presentation | Primary action |
|---|---|---|---|
| 39 | Morning setup | `/morning/setup` | Continue |
| 40 | Alarm settings | `/morning/alarm` | Save schedule |
| 41 | Evening preview | `/morning/evening` | Sounds good |
| 42 | Morning alarm entry | `/morning/wake` (notification payload) | I'm up / Snooze |
| 43 | Morning checklist | `/morning/checklist` | Make breakfast |
| 44 | Running late | `/morning/late` | Skip breakfast (no inventory change) |

## G. Planning, shopping & nutrition — `features/planning/`, `features/health/`, `features/journal/`

| # | Screen | Presentation | Primary action |
|---|---|---|---|
| 45 | Weekly planner | `/plan` | Build shopping list |
| 46 | Assign meal | `/plan/assign` | Plan |
| 47 | Batch cooking & leftovers | `/plan/leftovers` | (per item) Eat a portion / Freeze |
| 48 | Smart shopping list | `/kitchen/shopping` | Put n away in kitchen |
| 49 | Shopping item details | `/kitchen/shopping/:id` | Save |
| 50 | Nutrition dashboard | `/you/nutrition` | — (period selector) |
| 51 | Food journal | `/journal/history`, `/journal/entry/:id` | Save changes |
| 52 | Spending & waste | `/kitchen/spending` | — |

## H. Discover & rhythm

| # | Screen | Presentation | Primary action |
|---|---|---|---|
| 53 | Discover | `/discover` (tab) | — (filters, search) |
| 54 | Meal journal timeline | `/journal` (tab) | Log a meal |
| 55 | Quick meal entry | `/journal/add` | Log meal |
| 56 | Eating reminders | `/journal/reminders` | Save reminders |
| 57 | Eating patterns | `/journal/patterns` | — |
| 58 | Optional diabetes setup | `/you/diabetes` | Turn on glucose journal (two explicit consents) |
| 59 | Glucose journal | `/you/glucose` | Add reading |
| 60 | Glucose & meal timeline | `/you/glucose/timeline` | — |

## I. Nutrition intelligence & professionals

| # | Screen | Presentation | Primary action |
|---|---|---|---|
| 61 | Nutrition intelligence | `/you/nutrition/intelligence` | — |
| 62 | Hair, skin & nails | `/you/nutrition/hair-skin-nails` | Save note |
| 63 | Scientific evidence | `/you/nutrition/evidence` | (open source) |
| 64 | Nutrient detail | `/you/nutrition/nutrient/:name` | — |
| 65 | Smile & Food | `/you/smile` | (quick log) |
| 66 | Dental exposure history | `/you/smile/history` | — |
| 67 | My nutrition circle | `/you/circle` | Find professional |
| 68 | Sharing permissions | `/you/circle/share/:pro` | Share / Update / Revoke |
| 69 | Professional dashboard | `/pro`, `/pro/client/:grant` | Write assessment |
| 70 | Professional assessment | `/pro/assess/:grant`; client view `/you/circle/review/:id` | Share with client / Accept |

## J. Supporting

| # | Screen | Presentation |
|---|---|---|
| 71 | Profile & account | `/you` (tab) |
| 72 | Household members | `/you/household` |
| 73 | Privacy & data controls | `/you/privacy` |
| 74 | Connected services | `/you/connected` |
| 75 | Subscription & membership | `/you/membership` (informational; no billing yet) |
| 76 | Accessibility & language | `/you/accessibility` |
| 77 | Security & sessions | `/you/security` |
| 78 | Help & support | `/you/help` |
| 79 | Legal & evidence | `/you/legal` |
| 80 | Data export & deletion | `/you/data` |

Reusable states: `EmptyState`, `ErrorState`, `LoadingState`, `PermissionDeniedState`, `DemoBanner`, `ConfirmActionSheet`, undo snackbars (`lib/core/design/components/`).
