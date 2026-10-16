import 'package:material_ui/material_ui.dart';

import '../../../domain/models/health.dart';
import '../../../domain/models/professional.dart';
import '../../../domain/models/recipe.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/labels.dart';
import '../../format.dart';
import '../theme.dart';
import '../tokens.dart';
import 'food.dart';

class ChefConversationBubble extends StatelessWidget {
  const ChefConversationBubble({super.key, required this.fromUser, required this.text, this.recipes = const [], this.onRecipeTap, this.isDemo = false});

  final bool fromUser;
  final String text;
  final List<Recipe> recipes;
  final ValueChanged<Recipe>? onRecipeTap;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
      decoration: BoxDecoration(
        color: fromUser ? context.colors.primary : p.surface,
        border: fromUser ? null : Border.all(color: p.hairline),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(Radii.l),
          topRight: const Radius.circular(Radii.l),
          bottomLeft: Radius.circular(fromUser ? Radii.l : 6),
          bottomRight: Radius.circular(fromUser ? 6 : Radii.l),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: context.text.bodyMedium?.copyWith(color: fromUser ? context.colors.onPrimary : p.ink)),
          if (isDemo && !fromUser) ...[
            const SizedBox(height: 4),
            Text(context.l10n.coreChefDemoNote, style: context.text.bodySmall?.copyWith(fontSize: 11)),
          ],
        ],
      ),
    );
    return Semantics(
      label: fromUser ? context.l10n.coreSaidByYou(text) : context.l10n.coreSaidByChef(text),
      excludeSemantics: recipes.isEmpty,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xxs),
        child: Column(
          crossAxisAlignment: fromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            bubble,
            for (final r in recipes)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: SizedBox(
                  width: MediaQuery.sizeOf(context).width * 0.82,
                  child: LuxuryRecipeCard(recipe: r, compact: true, onTap: onRecipeTap == null ? null : () => onRecipeTap!(r)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class EvidenceReferenceCard extends StatelessWidget {
  const EvidenceReferenceCard({super.key, required this.claim, required this.sources, this.onTap});

  final EvidenceClaim claim;
  final List<EvidenceSource> sources;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (Color fg, Color bg) = switch (claim.strength) {
      EvidenceStrength.strong => (p.success, p.successSoft),
      EvidenceStrength.moderate => (p.info, p.infoSoft),
      EvidenceStrength.limited => (p.warning, p.warningSoft),
      EvidenceStrength.insufficient => (p.muted, p.hairline),
    };
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.l),
        child: Padding(
          padding: const EdgeInsets.all(Space.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(claim.topic.toUpperCase(), style: context.text.labelSmall?.copyWith(color: p.accent))),
                  TagPill(context.l10n.coreEvidenceStrength(context.labelOf(claim.strength)), icon: Icons.fact_check_outlined, color: fg, background: bg),
                ],
              ),
              const SizedBox(height: Space.xs),
              Text(claim.statement, style: context.text.bodyLarge),
              const SizedBox(height: Space.s),
              for (final s in sources)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text([s.publisher, context.labelOf(s.studyType), '${s.year}'].join(' · '), style: context.text.bodySmall),
                ),
              Text(
                claim.professionallyReviewed
                    ? context.l10n.coreReviewed(claim.reviewedOn.toIso())
                    : context.l10n.coreInternalSummary(claim.reviewedOn.toIso()),
                style: context.text.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DentalExposureCard extends StatelessWidget {
  const DentalExposureCard({super.key, required this.event, this.onDelete});

  final OralExposureEvent event;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final protective = event.kind.isProtective;
    return Card(
      child: ListTile(
        leading: Icon(protective ? Icons.water_drop_outlined : Icons.local_drink_outlined, color: protective ? p.success : p.warning),
        title: Text(context.labelOf(event.kind)),
        subtitle: Text([
          formatTime(context, event.occurredAt),
          if (event.durationMinutes != null) context.l10n.coreOverMinutes(event.durationMinutes!),
          if (protective) context.l10n.coreHelpfulHabit,
        ].join(' · ')),
        trailing: onDelete == null ? null : IconButton(tooltip: context.l10n.coreDelete, onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
      ),
    );
  }
}

/// Selects which data categories to share. Nothing is preselected.
class PermissionSelector extends StatelessWidget {
  const PermissionSelector({super.key, required this.selected, required this.onChanged, this.available = ShareCategory.values});

  final Set<ShareCategory> selected;
  final ValueChanged<Set<ShareCategory>> onChanged;
  final List<ShareCategory> available;

  static String describe(AppLocalizations l, ShareCategory c) => switch (c) {
        ShareCategory.journal => l.coreShareJournal,
        ShareCategory.nutrition => l.coreShareNutrition,
        ShareCategory.glucose => l.coreShareGlucose,
        ShareCategory.oral => l.coreShareOral,
        ShareCategory.concerns => l.coreShareConcerns,
        ShareCategory.dietary => l.coreShareDietary,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final c in available)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: CheckboxListTile(
              value: selected.contains(c),
              onChanged: (v) => onChanged(v == true ? {...selected, c} : ({...selected}..remove(c))),
              title: Text(context.labelOf(c)),
              subtitle: Text(describe(context.l10n, c)),
              controlAffinity: ListTileControlAffinity.trailing,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.l)),
            ),
          ),
      ],
    );
  }
}

class ProfessionalReviewCard extends StatelessWidget {
  const ProfessionalReviewCard({super.key, required this.assessment, this.onTap});

  final ProfessionalAssessment assessment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final status = switch (assessment.status) {
      AssessmentStatus.sharedWithClient => (l.coreAssessmentNew, p.info, p.infoSoft),
      AssessmentStatus.acknowledged => (l.coreAssessmentRead, p.muted, p.hairline),
      AssessmentStatus.accepted => (l.coreAssessmentAccepted, p.success, p.successSoft),
      AssessmentStatus.declined => (l.coreAssessmentDeclined, p.muted, p.hairline),
      AssessmentStatus.draft => (l.coreAssessmentDraft, p.warning, p.warningSoft),
    };
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.l),
        child: Padding(
          padding: const EdgeInsets.all(Space.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: p.surfaceSoft,
                    child: Text(assessment.professionalName.isEmpty ? '?' : assessment.professionalName[0], style: context.text.titleMedium),
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(assessment.professionalName, style: context.text.titleMedium),
                        Text(assessment.professionalCredentials, style: context.text.bodySmall),
                      ],
                    ),
                  ),
                  TagPill(status.$1, color: status.$2, background: status.$3),
                ],
              ),
              const SizedBox(height: Space.s),
              Text(assessment.summary, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
              const SizedBox(height: Space.xs),
              Text(l.coreReviewed(formatDay(context, assessment.createdAt)), style: context.text.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
