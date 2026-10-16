import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../core/services/analytics.dart';
import '../../data/paths.dart';
import '../../domain/models/health.dart';
import '../../domain/models/recipe.dart';
import '../../domain/models/professional.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';

/// Comma-separated, translated names of shared categories.
String _categoryList(BuildContext context, Iterable<ShareCategory> cats) => cats.map(context.labelOf).join(', ');

final grantAccessLogProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, grantId) => ref.watch(sharingRepoProvider).watchAccessLog(grantId));

// ---------------------------------------------------------------- 67 My nutrition circle

class NutritionCircleScreen extends ConsumerStatefulWidget {
  const NutritionCircleScreen({super.key});

  @override
  ConsumerState<NutritionCircleScreen> createState() => _NutritionCircleScreenState();
}

class _NutritionCircleScreenState extends ConsumerState<NutritionCircleScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await ref.read(sharingRepoProvider).findProfessionalByCode(_code.text);
      if (p == null) {
        setState(() => _error = context.l10n.prosNoMatch);
      } else if (mounted) {
        context.push('/you/circle/share/${p.uid}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grants = ref.watch(myGrantsProvider).value ?? const <ShareGrant>[];
    final assessments = ref.watch(myAssessmentsProvider).value ?? const <ProfessionalAssessment>[];
    final isDemo = ref.watch(appConfigProvider).isDemo;
    final now = DateTime.now().toUtc();
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.prosEyebrow, title: l.prosCircleTitle, subtitle: l.prosCircleSubtitle),
      children: [
        Text(l.prosInvite, style: context.text.titleMedium),
        const SizedBox(height: Space.xs),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(hintText: l.prosCodeHint, errorText: _error),
                onSubmitted: (_) => _find(),
              ),
            ),
            const SizedBox(width: Space.xs),
            FilledButton(onPressed: _busy ? null : _find, child: Text(l.prosFind)),
          ],
        ),
        if (isDemo)
          TextButton(
            onPressed: () async {
              // Demo only: creates a clearly labelled sample professional.
              await ref.read(docStoreProvider).set('$professionalsCollection/demo-pro', {
                ...const ProfessionalProfile(
                  uid: 'demo-pro',
                  displayName: 'Sample Dietitian (demo)', // l10n-ignore: demo data
                  kind: ProfessionalKind.dietitian,
                  regulatoryBody: 'Demo regulatory college', // l10n-ignore: demo data
                  registrationNumber: 'DEMO-0000',
                  province: 'ON',
                  status: VerificationStatus.verified,
                ).toMap(),
                'inviteCode': 'DEMO-RD',
              });
              _code.text = 'DEMO-RD';
              await _find();
            },
            child: Text(l.prosDemoSample),
          ),
        SectionHeader(l.prosWhoCanSee),
        if (grants.isEmpty) Text(l.prosNothingShared, style: context.text.bodyMedium),
        for (final g in grants)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: ListTile(
              title: Text(g.professionalName),
              subtitle: Text(
                g.isActiveAt(now)
                    ? l.prosGrantUntil(_categoryList(context, g.categories), formatDay(context, g.expiresAt))
                    : g.status == GrantStatus.revoked
                    ? (g.revokedAt == null ? l.prosRevoked : l.prosRevokedOn(formatDay(context, g.revokedAt!)))
                    : l.prosExpired,
              ),
              isThreeLine: g.isActiveAt(now),
              trailing: TagPill(
                g.isActiveAt(now) ? l.prosActive : l.prosEnded,
                color: g.isActiveAt(now) ? context.palette.success : context.palette.muted,
                background: g.isActiveAt(now) ? context.palette.successSoft : context.palette.hairline,
              ),
              onTap: () => context.push('/you/circle/share/${g.professionalUid}'),
            ),
          ),
        if (assessments.isNotEmpty) ...[
          SectionHeader(l.prosReviews),
          for (final a in assessments)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: ProfessionalReviewCard(assessment: a, onTap: () => context.push('/you/circle/review/${a.id}')),
            ),
        ],
        const SizedBox(height: Space.m),
        Text(l.prosReadOnlyNote, style: context.text.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------- 68 Sharing permissions

class SharingPermissionsScreen extends ConsumerStatefulWidget {
  const SharingPermissionsScreen({super.key, required this.professionalUid});
  final String professionalUid;

  @override
  ConsumerState<SharingPermissionsScreen> createState() => _SharingPermissionsScreenState();
}

class _SharingPermissionsScreenState extends ConsumerState<SharingPermissionsScreen> {
  Set<ShareCategory>? _categories;
  int _historyDays = 30;
  int _durationDays = 30;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(uidProvider);
    final grantId = uid == null ? '' : shareGrantId(uid, widget.professionalUid);
    final grant = ref.watch(shareGrantProvider(grantId)).value;
    final pro = ref.watch(_proProvider(widget.professionalUid)).value;
    final log = ref.watch(grantAccessLogProvider(grantId)).value ?? const [];
    final active = grant?.isActiveAt(DateTime.now().toUtc()) ?? false;
    final cats = _categories ??= active ? grant!.categories.toSet() : <ShareCategory>{};
    final glucoseOn = ref.watch(wellnessProvider).value?.diabetesFeatures ?? false;
    final available = ShareCategory.values.where((c) => c != ShareCategory.glucose || glucoseOn).toList();

    if (pro == null) return const Scaffold(body: LoadingState());
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: context.labelOf(pro.kind),
        title: pro.displayName,
        subtitle: pro.isVerified ? l.prosCredentialsVerified(pro.regulatoryBody, pro.registrationNumber) : l.prosCredentialsNotVerified(pro.regulatoryBody, pro.registrationNumber),
      ),
      primaryAction: PrimaryActionButton(
        label: active ? l.prosUpdateSharing : l.prosShareWith(pro.displayName.split(' ').first),
        loading: _busy,
        onPressed: cats.isEmpty || !pro.isVerified
            ? null
            : () async {
                final ok = await showConfirmActionSheet(
                  context,
                  title: l.prosShareWithQuestion(pro.displayName),
                  message: l.prosShareConfirm(_categoryList(context, cats), _historyDays, formatDay(context, DateTime.now().add(Duration(days: _durationDays)))),
                  confirmLabel: l.prosShare,
                );
                if (!ok) return;
                setState(() => _busy = true);
                try {
                  final profile = ref.read(profileProvider).value!;
                  final g = await ref
                      .read(sharingRepoProvider)
                      .grant(
                        ownerUid: profile.uid,
                        ownerName: profile.displayName,
                        professional: pro,
                        categories: cats.toList(),
                        rangeStart: DateTime.now().subtract(Duration(days: _historyDays)),
                        duration: Duration(days: _durationDays),
                      );
                  await ref
                      .read(profileRepoProvider)
                      .recordConsent(
                        profile.uid,
                        purpose: 'share:${g.id}',
                        granted: true,
                        text: 'Share ${cats.map((c) => c.name).join(',')} with ${pro.uid} for $_durationDays days', // l10n-ignore: consent record, not shown
                      );
                  ref.read(analyticsProvider).log(AnalyticsEvents.shareGranted, {'count': cats.length});
                  if (context.mounted) showMessage(context, l.prosSharedWith(pro.displayName));
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
      ),
      children: [
        Text(l.prosWhatToShare, style: context.text.titleMedium),
        const SizedBox(height: Space.xs),
        PermissionSelector(selected: cats, available: available, onChanged: (s) => setState(() => _categories = s)),
        SectionHeader(l.prosHowFarBack),
        Wrap(
          spacing: Space.xs,
          children: [
            for (final d in [7, 30, 90, 365]) ChoiceChip(label: Text(d == 365 ? l.prosOneYear : l.prosDays(d)), selected: _historyDays == d, onSelected: (_) => setState(() => _historyDays = d)),
          ],
        ),
        SectionHeader(l.prosAccessEndsAfter),
        Wrap(
          spacing: Space.xs,
          children: [
            for (final d in [7, 30, 90]) ChoiceChip(label: Text(l.prosDays(d)), selected: _durationDays == d, onSelected: (_) => setState(() => _durationDays = d)),
          ],
        ),
        if (active) ...[
          const SizedBox(height: Space.l),
          SecondaryActionButton(
            icon: Icons.block,
            label: l.prosRevokeNow,
            onPressed: () async {
              final ok = await showConfirmActionSheet(context, title: l.prosRevokeQuestion, message: l.prosRevokeMessage(pro.displayName), confirmLabel: l.prosRevoke, destructive: true);
              if (!ok) return;
              await ref.read(sharingRepoProvider).revoke(grant!);
              await ref.read(profileRepoProvider).recordConsent(uid!, purpose: 'share:${grant.id}', granted: false);
              ref.read(analyticsProvider).log(AnalyticsEvents.shareRevoked);
              if (context.mounted) showMessage(context, l.prosRevoked);
            },
          ),
        ],
        SectionHeader(l.prosAccessHistory),
        if (log.isEmpty) Text(l.prosNotViewedYet(pro.displayName), style: context.text.bodySmall),
        for (final e in log.take(20))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.visibility_outlined, size: 20),
            title: Text(l.prosViewed(_viewedWhat(context, e['what']))),
            subtitle: Text(e['at'] is DateTime ? '${formatDay(context, e['at'] as DateTime)} ${formatTime(context, e['at'] as DateTime)}' : ''),
          ),
      ],
    );
  }
}

/// The access log stores the English category label; show it translated.
String _viewedWhat(BuildContext context, Object? what) {
  final c = ShareCategory.values.where((c) => c.label == what || c.name == what).firstOrNull;
  return c == null ? '${what ?? ''}' : context.labelOf(c);
}

final _proProvider = StreamProvider.family<ProfessionalProfile?, String>((ref, uid) => ref.watch(sharingRepoProvider).watchProfessional(uid));

/// Client view of one assessment; accepting never edits plans automatically.
class AssessmentDetailScreen extends ConsumerWidget {
  const AssessmentDetailScreen({super.key, required this.assessmentId});
  final String assessmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = (ref.watch(myAssessmentsProvider).value ?? const <ProfessionalAssessment>[]).where((a) => a.id == assessmentId).firstOrNull;
    if (a == null) return const Scaffold(body: LoadingState());
    final pending = a.status == AssessmentStatus.sharedWithClient || a.status == AssessmentStatus.acknowledged;
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: l.prosProfessionalReview,
        title: a.professionalName,
        subtitle: '${a.professionalCredentials} · ${formatDay(context, a.createdAt)}', // l10n-ignore: data and separators only
      ),
      primaryAction: pending ? PrimaryActionButton(label: l.prosAcceptRecommendations, onPressed: () => ref.read(sharingRepoProvider).respond(a, true)) : null,
      children: [
        Text(a.summary, style: context.text.bodyLarge),
        if (a.recommendations.isNotEmpty) ...[
          SectionHeader(l.prosRecommendations),
          for (final r in a.recommendations) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.check_circle_outline), title: Text(r)),
        ],
        const SizedBox(height: Space.m),
        Text(l.prosAcceptNote, style: context.text.bodySmall),
        if (pending) TextButton(onPressed: () => ref.read(sharingRepoProvider).respond(a, false), child: Text(l.prosDecline)),
        if (a.status == AssessmentStatus.accepted) SecondaryActionButton(icon: Icons.calendar_month_outlined, label: l.prosOpenPlanner, onPressed: () => context.push('/plan')),
      ],
    );
  }
}

// ---------------------------------------------------------------- 69 Professional dashboard

class ProfessionalDashboardScreen extends ConsumerWidget {
  const ProfessionalDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myProfessionalProfileProvider);
    final profile = me.value;
    if (me.isLoading) return const Scaffold(body: LoadingState());
    if (profile == null) return const ProfessionalApplicationScreen();
    final l = context.l10n;
    if (!profile.isVerified) {
      return PremiumAppScaffold(
        header: EditorialPageHeader(eyebrow: l.prosPortal, title: l.prosVerificationPending),
        children: [
          Text(l.prosVerificationPendingBody(profile.regulatoryBody), style: context.text.bodyLarge),
          if (ref.watch(appConfigProvider).isDemo)
            TextButton(
              onPressed: () =>
                  ref.read(docStoreProvider).set('$professionalsCollection/${profile.uid}', {'status': 'verified', 'inviteCode': 'DEMO-${profile.uid.hashCode.abs() % 9999}'}, merge: true),
              child: Text(l.prosDemoVerify),
            ),
        ],
      );
    }
    final now = DateTime.now().toUtc();
    final grants = (ref.watch(proGrantsProvider).value ?? const <ShareGrant>[]).where((g) => g.isActiveAt(now)).toList();
    final inviteCode = ref.watch(_proCodeProvider(profile.uid)).value;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.prosPortal, title: l.prosClients, subtitle: '${profile.displayName} · ${context.labelOf(profile.kind)}'), // l10n-ignore: data and separators only
      children: [
        if (inviteCode != null) SoftCard(child: Text(l.prosClientCode(inviteCode), style: context.text.titleMedium)),
        const SizedBox(height: Space.m),
        if (grants.isEmpty) EmptyState(icon: Icons.group_outlined, title: l.prosNoClients, message: l.prosNoClientsMessage),
        for (final g in grants)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: ListTile(
              title: Text(g.ownerName),
              subtitle: Text(l.prosClientAccessUntil(_categoryList(context, g.categories), formatDay(context, g.expiresAt))),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/pro/client/${g.id}'),
            ),
          ),
        const SizedBox(height: Space.m),
        Text(l.prosRecordsNote, style: context.text.bodySmall),
      ],
    );
  }
}

final _proCodeProvider = StreamProvider.family<String?, String>((ref, uid) => ref.watch(docStoreProvider).watch('$professionalsCollection/$uid').map((d) => d?.data['inviteCode'] as String?));

class ProfessionalApplicationScreen extends ConsumerStatefulWidget {
  const ProfessionalApplicationScreen({super.key});

  @override
  ConsumerState<ProfessionalApplicationScreen> createState() => _ProfessionalApplicationScreenState();
}

class _ProfessionalApplicationScreenState extends ConsumerState<ProfessionalApplicationScreen> {
  ProfessionalKind _kind = ProfessionalKind.dietitian;
  final _body = TextEditingController();
  final _number = TextEditingController();
  final _province = TextEditingController(text: 'ON');

  @override
  void dispose() {
    _body.dispose();
    _number.dispose();
    _province.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.prosPortal, title: l.prosJoinTitle, subtitle: l.prosJoinSubtitle),
      primaryAction: PrimaryActionButton(
        label: l.prosSubmit,
        onPressed: () async {
          if (_body.text.trim().isEmpty || _number.text.trim().isEmpty) return;
          final p = ref.read(profileProvider).value!;
          await ref
              .read(sharingRepoProvider)
              .applyAsProfessional(
                ProfessionalProfile(
                  uid: p.uid,
                  displayName: p.displayName,
                  kind: _kind,
                  regulatoryBody: _body.text.trim(),
                  registrationNumber: _number.text.trim(),
                  province: _province.text.trim().toUpperCase(),
                  status: VerificationStatus.pending,
                  email: p.email,
                ),
              );
        },
      ),
      children: [
        DropdownButtonFormField<ProfessionalKind>(
          isExpanded: true,
          initialValue: _kind,
          decoration: InputDecoration(labelText: l.prosProfession),
          items: [for (final k in ProfessionalKind.values) DropdownMenuItem(value: k, child: Text(context.labelOf(k)))],
          onChanged: (k) => setState(() => _kind = k!),
        ),
        const SizedBox(height: Space.s),
        TextField(
          controller: _body,
          decoration: InputDecoration(labelText: l.prosRegulatoryCollege, hintText: l.prosRegulatoryCollegeHint),
        ),
        const SizedBox(height: Space.s),
        TextField(
          controller: _number,
          decoration: InputDecoration(labelText: l.prosRegistrationNumber),
        ),
        const SizedBox(height: Space.s),
        TextField(
          controller: _province,
          decoration: InputDecoration(labelText: l.prosProvince),
        ),
      ],
    );
  }
}

class ClientRecordsScreen extends ConsumerStatefulWidget {
  const ClientRecordsScreen({super.key, required this.grantId});
  final String grantId;

  @override
  ConsumerState<ClientRecordsScreen> createState() => _ClientRecordsScreenState();
}

class _ClientRecordsScreenState extends ConsumerState<ClientRecordsScreen> {
  ShareCategory? _cat;
  Future<List<Map<String, dynamic>>>? _records;

  void _load(ShareGrant g, ShareCategory c) {
    final uid = ref.read(uidProvider)!;
    setState(() {
      _cat = c;
      _records = ref.read(sharingRepoProvider).readClientCategory(g, c, viewerUid: uid).then((r) async {
        await ref.read(sharingRepoProvider).logAccess(g, viewerUid: uid, what: c.label); // stored; translated on display
        return r;
      });
    });
  }

  String _describe(BuildContext context, ShareCategory c, Map<String, dynamic> r) {
    final l = context.l10n;
    final fr = Localizations.localeOf(context).languageCode == 'fr';
    String meal() {
      final m = MealType.values.where((m) => m.name == r['mealType']).firstOrNull;
      return m == null ? '${r['mealType']}' : context.labelOf(m);
    }

    String oral() {
      final k = OralExposureKind.values.where((k) => k.name == r['kind']).firstOrNull;
      return k == null ? '${r['kind']}' : context.labelOf(k);
    }

    return switch (c) {
      ShareCategory.journal => l.prosRecordMeal('${r['title']}', meal(), '${r['portions']}'),
      ShareCategory.nutrition => l.prosRecordMealKcal('${r['title']}', meal(), '${r['portions']}', '${((r['nutrition'] as Map?)?['values'] as Map?)?['energyKcal'] ?? '—'}'),
      ShareCategory.glucose => l.prosRecordGlucose(
        fr ? (r['valueMmolL'] as num).toStringAsFixed(1).replaceAll('.', ',') : (r['valueMmolL'] as num).toStringAsFixed(1),
        l.prosGlucoseContext('${r['context']}'),
      ),
      ShareCategory.oral => oral(),
      ShareCategory.concerns => l.prosRecordConcern(l.prosConcernArea('${r['area']}'), '${r['description']}', '${r['severity']}'),
      ShareCategory.dietary => l.prosRecordDietary(
        (r['allergies'] as List?)?.map((a) => context.allergenLabel('$a')).join(', ') ?? '—',
        (r['restrictions'] as List?)?.map((x) => context.restrictionLabel('$x')).join(', ') ?? '—',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(shareGrantProvider(widget.grantId)).value;
    if (g == null) return const Scaffold(body: LoadingState());
    final l = context.l10n;
    if (!g.isActiveAt(DateTime.now().toUtc())) {
      return PremiumAppScaffold(
        children: [EmptyState(icon: Icons.lock_outline, title: l.prosAccessEnded, message: l.prosAccessEndedMessage)],
      );
    }
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.prosClient, title: g.ownerName, subtitle: l.prosSharedSince(formatDay(context, g.rangeStart))),
      primaryAction: PrimaryActionButton(label: l.prosWriteAssessment, onPressed: () => context.push('/pro/assess/${g.id}')),
      children: [
        Wrap(
          spacing: Space.xs,
          children: [for (final c in g.categories) ChoiceChip(label: Text(context.labelOf(c)), selected: _cat == c, onSelected: (_) => _load(g, c))],
        ),
        const SizedBox(height: Space.m),
        if (_records == null) Text(l.prosChooseCategory, style: context.text.bodyMedium),
        if (_records != null)
          FutureBuilder(
            future: _records,
            builder: (context, snap) {
              if (snap.hasError) return ErrorState(message: ErrorState.describe(snap.error!));
              if (!snap.hasData) return const LoadingState();
              final rows = snap.data!;
              if (rows.isEmpty) return Text(l.prosNoRecords, style: context.text.bodyMedium);
              return Column(
                children: [
                  for (final r in rows)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_describe(context, _cat!, r)),
                      subtitle: Text([r['eatenAt'], r['measuredAt'], r['occurredAt'], r['recordedAt']].whereType<DateTime>().map((t) => '${formatDay(context, t)} ${formatTime(context, t)}').join()),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 70 Professional assessment

class ProfessionalAssessmentScreen extends ConsumerStatefulWidget {
  const ProfessionalAssessmentScreen({super.key, required this.grantId});
  final String grantId;

  @override
  ConsumerState<ProfessionalAssessmentScreen> createState() => _ProfessionalAssessmentScreenState();
}

class _ProfessionalAssessmentScreenState extends ConsumerState<ProfessionalAssessmentScreen> {
  final _summary = TextEditingController();
  final _rec = TextEditingController();
  final _recs = <String>[];
  bool _busy = false;

  @override
  void dispose() {
    _summary.dispose();
    _rec.dispose();
    super.dispose();
  }

  Future<void> _save(ShareGrant g, ProfessionalProfile me, {required bool share}) async {
    if (_summary.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final l = context.l10n;
    try {
      final repo = ref.read(sharingRepoProvider);
      await repo.saveAssessment(
        ProfessionalAssessment(
          id: repo.newAssessmentId(),
          grantId: g.id,
          clientUid: g.ownerUid,
          professionalUid: me.uid,
          professionalName: me.displayName,
          professionalCredentials: '${context.labelOf(me.kind)}, ${me.regulatoryBody} #${me.registrationNumber}',
          summary: _summary.text.trim(),
          recommendations: List.of(_recs),
          status: share ? AssessmentStatus.sharedWithClient : AssessmentStatus.draft,
          createdAt: DateTime.now().toUtc(),
          reviewedRangeStart: g.rangeStart,
          reviewedRangeEnd: DateTime.now().toUtc(),
        ),
      );
      if (mounted) {
        context.pop();
        showMessage(context, share ? l.prosSharedWith(g.ownerName) : l.prosDraftSaved);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(shareGrantProvider(widget.grantId)).value;
    final me = ref.watch(myProfessionalProfileProvider).value;
    if (g == null || me == null) return const Scaffold(body: LoadingState());
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.prosAssessment, title: g.ownerName, subtitle: l.prosReviewing(formatDay(context, g.rangeStart))),
      primaryAction: PrimaryActionButton(label: l.prosShareWithClient, loading: _busy, onPressed: () => _save(g, me, share: true)),
      children: [
        TextField(
          controller: _summary,
          minLines: 4,
          maxLines: 10,
          decoration: InputDecoration(labelText: l.prosSummary, alignLabelWithHint: true),
        ),
        SectionHeader(l.prosRecommendations),
        for (final r in _recs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(r),
            trailing: IconButton(tooltip: l.commonRemove, icon: const Icon(Icons.close), onPressed: () => setState(() => _recs.remove(r))),
          ),
        TextField(
          controller: _rec,
          decoration: InputDecoration(
            hintText: l.prosAddRecommendation,
            suffixIcon: IconButton(
              tooltip: l.prosAdd,
              icon: const Icon(Icons.add),
              onPressed: () {
                if (_rec.text.trim().isEmpty) return;
                setState(() => _recs.add(_rec.text.trim()));
                _rec.clear();
              },
            ),
          ),
        ),
        const SizedBox(height: Space.m),
        Text(l.prosSignedNote(me.displayName, context.labelOf(me.kind)), style: context.text.bodySmall),
        TextButton(onPressed: _busy ? null : () => _save(g, me, share: false), child: Text(l.prosSaveDraft)),
      ],
    );
  }
}
