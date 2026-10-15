import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../core/services/analytics.dart';
import '../../data/paths.dart';
import '../../domain/models/professional.dart';

final grantAccessLogProvider = StreamProvider.family<List<Map<String, dynamic>>, String>(
  (ref, grantId) => ref.watch(sharingRepoProvider).watchAccessLog(grantId),
);

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
        setState(() => _error = 'No verified professional has that code. Check it with them.');
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
    return PremiumAppScaffold(
      header: const EditorialPageHeader(
        eyebrow: 'Professionals',
        title: 'My nutrition circle',
        subtitle: 'Share exactly what you choose, for as long as you choose, with verified dietitians and dental professionals.',
      ),
      children: [
        Text('Invite a professional', style: context.text.titleMedium),
        const SizedBox(height: Space.xs),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(hintText: 'Their Chefii code', errorText: _error),
                onSubmitted: (_) => _find(),
              ),
            ),
            const SizedBox(width: Space.xs),
            FilledButton(onPressed: _busy ? null : _find, child: const Text('Find')),
          ],
        ),
        if (isDemo)
          TextButton(
            onPressed: () async {
              // Demo only: creates a clearly labelled sample professional.
              await ref.read(docStoreProvider).set('$professionalsCollection/demo-pro', {
                ...const ProfessionalProfile(
                  uid: 'demo-pro',
                  displayName: 'Sample Dietitian (demo)',
                  kind: ProfessionalKind.dietitian,
                  regulatoryBody: 'Demo regulatory college',
                  registrationNumber: 'DEMO-0000',
                  province: 'ON',
                  status: VerificationStatus.verified,
                ).toMap(),
                'inviteCode': 'DEMO-RD',
              });
              _code.text = 'DEMO-RD';
              await _find();
            },
            child: const Text('Demo: use a sample dietitian'),
          ),
        const SectionHeader('Who can see what'),
        if (grants.isEmpty) Text('You haven\'t shared anything. Nothing is visible to anyone.', style: context.text.bodyMedium),
        for (final g in grants)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: ListTile(
              title: Text(g.professionalName),
              subtitle: Text(
                g.isActiveAt(now)
                    ? '${g.categories.map((c) => c.label).join(', ')}\nUntil ${formatDay(g.expiresAt)}'
                    : g.status == GrantStatus.revoked
                    ? 'Access revoked ${g.revokedAt == null ? '' : formatDay(g.revokedAt!)}'
                    : 'Access expired',
              ),
              isThreeLine: g.isActiveAt(now),
              trailing: TagPill(
                g.isActiveAt(now) ? 'Active' : 'Ended',
                color: g.isActiveAt(now) ? context.palette.success : context.palette.muted,
                background: g.isActiveAt(now) ? context.palette.successSoft : context.palette.hairline,
              ),
              onTap: () => context.push('/you/circle/share/${g.professionalUid}'),
            ),
          ),
        if (assessments.isNotEmpty) ...[
          const SectionHeader('Reviews'),
          for (final a in assessments)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: ProfessionalReviewCard(assessment: a, onTap: () => context.push('/you/circle/review/${a.id}')),
            ),
        ],
        const SizedBox(height: Space.m),
        Text('Professionals see read-only copies of what you share. They can\'t change your meals, kitchen or plans.', style: context.text.bodySmall),
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
    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: pro.kind.label,
        title: pro.displayName,
        subtitle: '${pro.regulatoryBody} · #${pro.registrationNumber}${pro.isVerified ? ' · verified' : ' · not verified'}',
      ),
      primaryAction: PrimaryActionButton(
        label: active ? 'Update sharing' : 'Share with ${pro.displayName.split(' ').first}',
        loading: _busy,
        onPressed: cats.isEmpty || !pro.isVerified
            ? null
            : () async {
                final ok = await showConfirmActionSheet(
                  context,
                  title: 'Share with ${pro.displayName}?',
                  message:
                      '${cats.map((c) => c.label).join(', ')} from the last $_historyDays days, until ${formatDay(DateTime.now().add(Duration(days: _durationDays)))}. You can revoke any time.',
                  confirmLabel: 'Share',
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
                        text: 'Share ${cats.map((c) => c.name).join(',')} with ${pro.uid} for $_durationDays days',
                      );
                  ref.read(analyticsProvider).log(AnalyticsEvents.shareGranted, {'count': cats.length});
                  if (context.mounted) showMessage(context, 'Shared with ${pro.displayName}');
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
      ),
      children: [
        Text('What to share', style: context.text.titleMedium),
        const SizedBox(height: Space.xs),
        PermissionSelector(selected: cats, available: available, onChanged: (s) => setState(() => _categories = s)),
        const SectionHeader('How far back'),
        Wrap(
          spacing: Space.xs,
          children: [
            for (final d in [7, 30, 90, 365])
              ChoiceChip(label: Text(d == 365 ? '1 year' : '$d days'), selected: _historyDays == d, onSelected: (_) => setState(() => _historyDays = d)),
          ],
        ),
        const SectionHeader('Access ends after'),
        Wrap(
          spacing: Space.xs,
          children: [
            for (final d in [7, 30, 90]) ChoiceChip(label: Text('$d days'), selected: _durationDays == d, onSelected: (_) => setState(() => _durationDays = d)),
          ],
        ),
        if (active) ...[
          const SizedBox(height: Space.l),
          SecondaryActionButton(
            icon: Icons.block,
            label: 'Revoke access now',
            onPressed: () async {
              final ok = await showConfirmActionSheet(
                context,
                title: 'Revoke access?',
                message: '${pro.displayName} will immediately lose access to everything you shared.',
                confirmLabel: 'Revoke',
                destructive: true,
              );
              if (!ok) return;
              await ref.read(sharingRepoProvider).revoke(grant!);
              await ref.read(profileRepoProvider).recordConsent(uid!, purpose: 'share:${grant.id}', granted: false);
              ref.read(analyticsProvider).log(AnalyticsEvents.shareRevoked);
              if (context.mounted) showMessage(context, 'Access revoked');
            },
          ),
        ],
        const SectionHeader('Access history'),
        if (log.isEmpty) Text('${pro.displayName} hasn\'t viewed anything yet.', style: context.text.bodySmall),
        for (final e in log.take(20))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.visibility_outlined, size: 20),
            title: Text('Viewed ${e['what']}'),
            subtitle: Text(e['at'] is DateTime ? '${formatDay(e['at'] as DateTime)} ${formatTime(context, e['at'] as DateTime)}' : ''),
          ),
      ],
    );
  }
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
    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: 'Professional review',
        title: a.professionalName,
        subtitle: '${a.professionalCredentials} · ${formatDay(a.createdAt)}',
      ),
      primaryAction: pending ? PrimaryActionButton(label: 'Accept recommendations', onPressed: () => ref.read(sharingRepoProvider).respond(a, true)) : null,
      children: [
        Text(a.summary, style: context.text.bodyLarge),
        if (a.recommendations.isNotEmpty) ...[
          const SectionHeader('Recommendations'),
          for (final r in a.recommendations) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.check_circle_outline), title: Text(r)),
        ],
        const SizedBox(height: Space.m),
        Text('Accepting keeps these on your profile. Nothing in your plan or kitchen changes unless you change it.', style: context.text.bodySmall),
        if (pending) TextButton(onPressed: () => ref.read(sharingRepoProvider).respond(a, false), child: const Text('Decline')),
        if (a.status == AssessmentStatus.accepted)
          SecondaryActionButton(icon: Icons.calendar_month_outlined, label: 'Open meal planner', onPressed: () => context.push('/plan')),
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
    if (!profile.isVerified) {
      return PremiumAppScaffold(
        header: const EditorialPageHeader(eyebrow: 'Professional portal', title: 'Verification pending'),
        children: [
          Text(
            'We\'re confirming your registration with ${profile.regulatoryBody}. You\'ll be able to see clients\' shared records once verified.',
            style: context.text.bodyLarge,
          ),
          if (ref.watch(appConfigProvider).isDemo)
            TextButton(
              onPressed: () => ref.read(docStoreProvider).set('$professionalsCollection/${profile.uid}', {
                'status': 'verified',
                'inviteCode': 'DEMO-${profile.uid.hashCode.abs() % 9999}',
              }, merge: true),
              child: const Text('Demo: simulate verification'),
            ),
        ],
      );
    }
    final now = DateTime.now().toUtc();
    final grants = (ref.watch(proGrantsProvider).value ?? const <ShareGrant>[]).where((g) => g.isActiveAt(now)).toList();
    final inviteCode = ref.watch(_proCodeProvider(profile.uid)).value;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: 'Professional portal', title: 'Clients', subtitle: '${profile.displayName} · ${profile.kind.label}'),
      children: [
        if (inviteCode != null) SoftCard(child: Text('Your client code: $inviteCode', style: context.text.titleMedium)),
        const SizedBox(height: Space.m),
        if (grants.isEmpty)
          const EmptyState(
            icon: Icons.group_outlined,
            title: 'No active clients',
            message: 'Clients who share with you appear here while their access is active.',
          ),
        for (final g in grants)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: ListTile(
              title: Text(g.ownerName),
              subtitle: Text('${g.categories.map((c) => c.label).join(', ')}\nAccess until ${formatDay(g.expiresAt)}'),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/pro/client/${g.id}'),
            ),
          ),
        const SizedBox(height: Space.m),
        Text('Records are read-only and every view is logged for your client to see.', style: context.text.bodySmall),
      ],
    );
  }
}

final _proCodeProvider = StreamProvider.family<String?, String>(
  (ref, uid) => ref.watch(docStoreProvider).watch('$professionalsCollection/$uid').map((d) => d?.data['inviteCode'] as String?),
);

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
    return PremiumAppScaffold(
      header: const EditorialPageHeader(
        eyebrow: 'Professional portal',
        title: 'Join as a professional',
        subtitle: 'For regulated health professionals. We verify every registration.',
      ),
      primaryAction: PrimaryActionButton(
        label: 'Submit for verification',
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
          decoration: const InputDecoration(labelText: 'Profession'),
          items: [for (final k in ProfessionalKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
          onChanged: (k) => setState(() => _kind = k!),
        ),
        const SizedBox(height: Space.s),
        TextField(
          controller: _body,
          decoration: const InputDecoration(labelText: 'Regulatory college', hintText: 'e.g. College of Dietitians of Ontario'),
        ),
        const SizedBox(height: Space.s),
        TextField(
          controller: _number,
          decoration: const InputDecoration(labelText: 'Registration number'),
        ),
        const SizedBox(height: Space.s),
        TextField(
          controller: _province,
          decoration: const InputDecoration(labelText: 'Province'),
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
        await ref.read(sharingRepoProvider).logAccess(g, viewerUid: uid, what: c.label);
        return r;
      });
    });
  }

  String _describe(ShareCategory c, Map<String, dynamic> r) => switch (c) {
    ShareCategory.journal || ShareCategory.nutrition =>
      '${r['title']} · ${r['mealType']} · ${r['portions']} portion(s)${c == ShareCategory.nutrition ? ' · ≈ ${((r['nutrition'] as Map?)?['values'] as Map?)?['energyKcal'] ?? '—'} kcal' : ''}',
    ShareCategory.glucose => '${(r['valueMmolL'] as num).toStringAsFixed(1)} mmol/L · ${r['context']}',
    ShareCategory.oral => '${r['kind']}',
    ShareCategory.concerns => '${r['area']}: ${r['description']} (${r['severity']}/5)',
    ShareCategory.dietary => 'Allergies: ${(r['allergies'] as List?)?.join(', ') ?? '—'} · Restrictions: ${(r['restrictions'] as List?)?.join(', ') ?? '—'}',
  };

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(shareGrantProvider(widget.grantId)).value;
    if (g == null) return const Scaffold(body: LoadingState());
    if (!g.isActiveAt(DateTime.now().toUtc())) {
      return PremiumAppScaffold(
        children: [const EmptyState(icon: Icons.lock_outline, title: 'Access has ended', message: 'This client\'s sharing has expired or been revoked.')],
      );
    }
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: 'Client', title: g.ownerName, subtitle: 'Shared since ${formatDay(g.rangeStart)} · read-only'),
      primaryAction: PrimaryActionButton(label: 'Write assessment', onPressed: () => context.push('/pro/assess/${g.id}')),
      children: [
        Wrap(
          spacing: Space.xs,
          children: [for (final c in g.categories) ChoiceChip(label: Text(c.label), selected: _cat == c, onSelected: (_) => _load(g, c))],
        ),
        const SizedBox(height: Space.m),
        if (_records == null) Text('Choose a category to view.', style: context.text.bodyMedium),
        if (_records != null)
          FutureBuilder(
            future: _records,
            builder: (context, snap) {
              if (snap.hasError) return ErrorState(message: ErrorState.describe(snap.error!));
              if (!snap.hasData) return const LoadingState();
              final rows = snap.data!;
              if (rows.isEmpty) return Text('No records in the shared range.', style: context.text.bodyMedium);
              return Column(
                children: [
                  for (final r in rows)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_describe(_cat!, r)),
                      subtitle: Text(
                        [
                          r['eatenAt'],
                          r['measuredAt'],
                          r['occurredAt'],
                          r['recordedAt'],
                        ].whereType<DateTime>().map((t) => '${formatDay(t)} ${formatTime(context, t)}').join(),
                      ),
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
    try {
      final repo = ref.read(sharingRepoProvider);
      await repo.saveAssessment(
        ProfessionalAssessment(
          id: repo.newAssessmentId(),
          grantId: g.id,
          clientUid: g.ownerUid,
          professionalUid: me.uid,
          professionalName: me.displayName,
          professionalCredentials: '${me.kind.label}, ${me.regulatoryBody} #${me.registrationNumber}',
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
        showMessage(context, share ? 'Shared with ${g.ownerName}' : 'Draft saved');
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
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: 'Assessment', title: g.ownerName, subtitle: 'Reviewing ${formatDay(g.rangeStart)} – today'),
      primaryAction: PrimaryActionButton(label: 'Share with client', loading: _busy, onPressed: () => _save(g, me, share: true)),
      children: [
        TextField(
          controller: _summary,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(labelText: 'Summary', alignLabelWithHint: true),
        ),
        const SectionHeader('Recommendations'),
        for (final r in _recs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(r),
            trailing: IconButton(tooltip: 'Remove', icon: const Icon(Icons.close), onPressed: () => setState(() => _recs.remove(r))),
          ),
        TextField(
          controller: _rec,
          decoration: InputDecoration(
            hintText: 'Add a recommendation',
            suffixIcon: IconButton(
              tooltip: 'Add',
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
        Text('Your client must accept before anything changes. Signed as ${me.displayName}, ${me.kind.label}.', style: context.text.bodySmall),
        TextButton(onPressed: _busy ? null : () => _save(g, me, share: false), child: const Text('Save as draft')),
      ],
    );
  }
}
