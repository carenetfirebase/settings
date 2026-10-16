# French (Canada) review list

Chefii's interface is fully translated into Canadian French (≈1,600 strings in
`lib/l10n/parts/*_fr.arb`), plus food names (`lib/domain/catalog/catalog_fr.dart`),
recipes and evidence notes. The translation was done carefully, but **a
bilingual reviewer from Québec should read the items below before launch** —
especially the health and allergy wording, which also needs clinical review
(CLINICAL_SAFETY.md).

How to review: switch the app to *Vous › Accessibilité et langue › Français
(Canada)* and walk through each screen, or read the ARB files side by side
(`lib/l10n/parts/<area>_en.arb` and `<area>_fr.arb`).

## Product names to confirm

| English | French chosen | Alternatives |
|---|---|---|
| Smile & Food | Sourire et alimentation | Sourire et assiette |
| Insights | Constats | Aperçus, Observations |
| Dietary safety | Allergies et restrictions alimentaires | (avoid "sécurité alimentaire": it means food security) |
| Meet your chef | Votre chef personnel | Faites connaissance avec votre chef |
| Membership | Abonnement | Adhésion |
| My nutrition circle | Mon cercle nutrition | |

## Health, allergy and food-safety wording (also for clinical review)

- Allergy screen: "M'avertir des risques de contact croisé"; "Non sécuritaire pour votre foyer"; "Aucune substitution sécuritaire dont nous sommes sûrs".
- Disclaimer: "Il ne s'agit pas d'un avis médical, et Chefii ne diagnostique ni ne traite aucun problème de santé."
- "Use by" → « date limite d'utilisation »; "best before" → « meilleur avant ». Canada has no official "use by" date; confirm the wording.
- Glucose: « glycémie », « lectures », « glucomètre »; CGM kept as "CGM" with « capteur de glucose en continu » spelled out (alternatives: SGC, lecteur de glucose en continu).
- "registered dietitian" → « diététiste-nutritionniste » (a regulated title), in some places « membre d'un ordre professionnel ».
- AI rules in Privacy: « n'ont pas le droit d'entraîner » / « n'est pas autorisée à créer » (prohibitions, as in English).
- PIPEDA → LPRPDE, worded as « préparée en vue de respecter » (no compliance claim).
- Food safety card keeps 4 °C (40 °F), « en cas de doute, jetez l'aliment », Santé Canada.
- Leftovers: « à consommer d'ici ~N jours ».

## Language-dependent behaviour to know about

- **Typed confirmation to delete an account** is SUPPRIMER in French (DELETE in English).
- **Voice and typed kitchen commands** understand Québec French (« J'ai utilisé deux œufs », « On n'a plus de lait », « 250 ml de lait »). Test with real speech on a device.
- **Some stored records keep the language they were created in**: inventory history summaries, consent records, the default household name ("Cuisine de {nom}"), leftovers journal titles, scheduled notification texts.
- **AI replies** (chef, chat, meal titles) are requested in Canadian French; receipt and fridge item names stay in English internally for catalogue matching, but catalogue foods are shown in French.
- **Fallback display name** "Friend" → « Ami » is masculine; consider a neutral alternative.

## Not yet in French

- Text inside AI-generated content that the model returns in English despite the instruction (rare; re-check on device).
- Nutrient reference source names in a few detail rows.

## Evidence sources: French links to verify

These French titles and URLs were written without internet access; open each and confirm it resolves to the right page (`lib/domain/nutrition/evidence_library_fr.dart`):

- Guide alimentaire canadien — https://guide-alimentaire.canada.ca/fr/
- Tableaux des apports nutritionnels de référence — https://www.canada.ca/fr/sante-canada/services/aliments-nutrition/saine-alimentation/apports-nutritionnels-reference/tableaux.html
- OMS, Directive : apport en sucres chez l'adulte et l'enfant — https://www.who.int/fr/publications/i/item/9789241549028
- OMS, Sucres et caries dentaires — https://www.who.int/fr/news-room/fact-sheets/detail/sugars-and-dental-caries
- NIH Office of Dietary Supplements (biotin, iron): English only; no official French version.
- "CDRR" reference term has no French entry yet (shows in English if used).
