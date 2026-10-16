import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/l10n.dart';
import '../theme.dart';
import '../tokens.dart';

/// The standard page frame: porcelain background, generous gutters, an
/// optional editorial header, scrollable content and at most one pinned
/// primary action.
class PremiumAppScaffold extends StatelessWidget {
  const PremiumAppScaffold({
    super.key,
    this.title,
    this.header,
    required this.children,
    this.primaryAction,
    this.actions,
    this.showBack = true,
    this.padding = const EdgeInsets.symmetric(horizontal: Space.gutter),
    this.scrollController,
    this.floating,
    this.onRefresh,
    this.banner,
  });

  /// Small app-bar title (used when there is no editorial header).
  final String? title;
  final Widget? header;
  final List<Widget> children;

  /// The single obvious primary action, pinned above the safe area.
  final Widget? primaryAction;
  final List<Widget>? actions;
  final bool showBack;
  final EdgeInsets padding;
  final ScrollController? scrollController;
  final Widget? floating;
  final Future<void> Function()? onRefresh;

  /// Shown above content, e.g. a demo or offline banner.
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    final canPop = showBack && Navigator.of(context).canPop();
    Widget list = ListView(
      controller: scrollController,
      padding: padding.copyWith(top: Space.xs, bottom: Space.xxl + (primaryAction == null ? 0 : 72)),
      children: [
        ?banner,
        ?header,
        ...children,
      ],
    );
    if (onRefresh != null) list = RefreshIndicator(onRefresh: onRefresh!, child: list);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: canPop,
        title: title == null ? null : Text(title!),
        actions: [...?actions, const SizedBox(width: Space.xs)],
      ),
      floatingActionButton: floating,
      body: SafeArea(top: false, bottom: primaryAction == null, child: list),
      bottomNavigationBar: primaryAction == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.m),
              child: primaryAction!,
            ),
    );
  }
}

/// Eyebrow + serif headline + supporting line.
class EditorialPageHeader extends StatelessWidget {
  const EditorialPageHeader({super.key, this.eyebrow, required this.title, this.subtitle, this.trailing, this.bottomSpacing = Space.l});

  final String? eyebrow;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: Space.xs, bottom: bottomSpacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(eyebrow!.toUpperCase(), style: context.text.labelSmall?.copyWith(color: context.palette.accent)),
                  const SizedBox(height: Space.xs),
                ],
                Semantics(header: true, child: Text(title, style: context.text.displaySmall)),
                if (subtitle != null) ...[
                  const SizedBox(height: Space.xs),
                  Text(subtitle!, style: context.text.bodyLarge?.copyWith(color: context.palette.muted)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction, this.topSpacing = Space.l});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topSpacing, bottom: Space.s),
      child: Row(
        children: [
          Expanded(child: Semantics(header: true, child: Text(title, style: context.text.headlineSmall))),
          if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// Honest labelling for sample/demo content.
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key, this.message});

  /// Defaults to "Demo mode — sample data, no AI used." in the current language.
  final String? message;

  /// Store-screenshot builds (`--dart-define=CHEFII_SCREENSHOTS=true`) hide
  /// demo labels. Production builds never run in demo mode.
  static const _screenshots = bool.fromEnvironment('CHEFII_SCREENSHOTS');

  @override
  Widget build(BuildContext context) {
    if (_screenshots) return const SizedBox.shrink();
    final p = context.palette;
    final message = this.message ?? context.l10n.coreDemoBanner;
    return Semantics(
      container: true,
      label: message,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.m),
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
        decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(Radii.m)),
        child: Row(
          children: [
            Icon(Icons.science_outlined, size: 18, color: p.ink),
            const SizedBox(width: Space.xs),
            Expanded(child: ExcludeSemantics(child: Text(message, style: context.text.bodySmall?.copyWith(color: p.ink)))),
          ],
        ),
      ),
    );
  }
}

/// Five primary destinations: Today | Kitchen | Discover | Journal | You.
class BottomNavigationShell extends StatelessWidget {
  const BottomNavigationShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static List<(IconData, IconData, String)> destinations(AppLocalizations l) => [
        (Icons.wb_sunny_outlined, Icons.wb_sunny, l.coreTabToday),
        (Icons.kitchen_outlined, Icons.kitchen, l.coreTabKitchen),
        (Icons.explore_outlined, Icons.explore, l.coreTabDiscover),
        (Icons.menu_book_outlined, Icons.menu_book, l.coreTabJournal),
        (Icons.person_outline, Icons.person, l.coreTabYou),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: context.palette.hairline))),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final (icon, selected, label) in destinations(context.l10n))
              NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
          ],
        ),
      ),
    );
  }
}

/// A soft, rounded surface used for grouped content.
class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(Space.m), this.color, this.semanticLabel});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
    return Semantics(button: onTap != null, label: semanticLabel, child: card);
  }
}
