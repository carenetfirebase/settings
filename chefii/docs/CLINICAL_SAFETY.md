# Clinical & Food Safety

Chefii is a **kitchen, cooking and general nutrition education** product. It is **not** a medical device and must not be marketed as diagnosing, treating, mitigating or preventing disease. Under Health Canada's framework, software that only records user-entered data and provides general wellness education is generally outside medical-device regulation; any feature that interprets glucose or recommends therapy would change that. **Regulatory counsel must confirm classification before launch.**

## Hard rules (enforced in code)

| Rule | Where |
|---|---|
| Unknown allergy status is never treated as "no allergies"; recipes show a notice | `AllergenGuard.checkIngredients`, onboarding 05 |
| Every recipe (curated, AI, substituted) is screened for allergies and restrictions; conflicting recipes are hidden, and "Start cooking" is disabled | client `AllergenGuard`, server `safety/allergens.ts`, `recipeSafetyProvider` |
| AI recipes are screened **twice** (server and device) | `screenRecipes`, `FirebaseAiGateway` |
| Product allergen tags supplement name matching (e.g. chocolate → milk) | `catalogAllergens` |
| Household meals respect allergens other members choose to share | `householdDietaryProvider`, `householdDietary()` |
| Labels can't be seen: UI reminds users to check packages; cross-contact reminder when requested | Dietary screen, recipe safety card |
| Freshness is an estimate, never a safety statement; package dates take precedence; status label "Past recorded date", not "expired/unsafe" | `InventoryLot.statusOn`, Freshness centre copy |
| Safe internal temperatures included in curated recipes and required in AI prompts | `curated_recipes.dart`, `prompts.ts` |
| Leftovers default to a 3-day estimate | `CookingRepository.complete` |
| Nutrition always labelled "Estimate", with data completeness | `NutritionSummaryCard` |
| Calories hidden unless the user opts in; no targets, no weight goals | `WellnessPreferences.calorieTracking` |
| Daily Values shown as a label yardstick, not a personal target | Nutrition dashboard copy |
| Glucose: explicit two-step opt-in, consent recorded; journal only; no interpretation, scores, predictions, dosing or alarms; plausibility check catches typos only (1–35 mmol/L) | `DiabetesSetupScreen`, `GlucoseEntry.validate` |
| Eating patterns describe records only; no glucose predictions | `EatingPatternsScreen` |
| Hair/skin/nails: lists non-dietary causes and referral guidance; no supplement recommendations | `HairSkinNailsScreen` |
| Smile & Food: education only; frequency/timing framing; directs to dentist | `SmileAndFoodScreen` |
| AI may rephrase approved evidence claims but may not create health claims | prompts, evidence library design |
| Professional recommendations never change plans or inventory without the client's explicit action | `AssessmentDetailScreen` |

## Evidence governance

`lib/domain/nutrition/evidence_library.dart` holds every nutrition statement with sources, study type, strength, limitations and review status. **All claims are currently `internal_draft`** and the UI says "awaiting professional review". One claim (acid sipping) deliberately has no citation and says so.

Before launch:
1. A registered dietitian reviews every claim, the nutrient reference table (`domain/catalog/catalog.dart`, values rounded from USDA FoodData Central) and the Daily Value table (`nutrition.dart`, Health Canada label DVs — verify against the current regulation).
2. A dental professional reviews Smile & Food copy and the two teeth claims.
3. Re-review annually or when a source guideline changes; record reviewer, credentials and date in each claim.

Known data limitations: catalogue values are generic (not brand-specific); sodium excludes salt added at the table; "total sugars" overstates WHO "free sugars" (stated in the claim).

## Food safety copy

Freshness Centre and item detail say: estimates come from typical storage times; follow package dates; keep the fridge ≤ 4 °C; when in doubt, throw it out; refer to Health Canada guidance.

## Incident handling

A report of an allergen exposure or unsafe recipe is a P0: disable the recipe (curated) or the AI path (`OPENAI_ENABLED=false` / revoke key), add a regression test to the allergen lexicon on both platforms, notify affected users if identifiable.
