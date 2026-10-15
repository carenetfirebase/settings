import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import '../tokens.dart';

/// Search field with a row of single-select filter chips.
class SearchFilterBar extends StatefulWidget {
  const SearchFilterBar({
    super.key,
    required this.hint,
    required this.onQuery,
    this.filters = const [],
    this.selected,
    this.onFilter,
    this.trailing,
  });

  final String hint;
  final ValueChanged<String> onQuery;
  final List<String> filters;
  final String? selected;
  final ValueChanged<String?>? onFilter;
  final Widget? trailing;

  @override
  State<SearchFilterBar> createState() => _SearchFilterBarState();
}

class _SearchFilterBarState extends State<SearchFilterBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: (v) {
                  widget.onQuery(v);
                  setState(() {});
                },
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _controller.clear();
                            widget.onQuery('');
                            setState(() {});
                          },
                        ),
                ),
              ),
            ),
            if (widget.trailing != null) ...[const SizedBox(width: Space.xs), widget.trailing!],
          ],
        ),
        if (widget.filters.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          SizedBox(
            height: kMinTouchTarget,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.xs),
              itemBuilder: (context, i) {
                final f = widget.filters[i];
                final sel = f == widget.selected;
                return ChoiceChip(
                  label: Text(f),
                  selected: sel,
                  onSelected: (v) => widget.onFilter?.call(v ? f : null),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// Framing guide drawn over a camera preview or picked image.
class PhotoCaptureOverlay extends StatelessWidget {
  const PhotoCaptureOverlay({super.key, required this.child, this.hint = 'Fit the whole receipt inside the frame', this.aspectRatio = 0.62});

  final Widget child;
  final String hint;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: CustomPaint(painter: _FramePainter(aspectRatio: aspectRatio, color: ChefiiColors.ivory)),
        ),
        Positioned(
          left: Space.l,
          right: Space.l,
          bottom: Space.l,
          child: Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(Radii.m)),
              child: Text(hint, textAlign: TextAlign.center, style: context.text.bodyMedium?.copyWith(color: Colors.white)),
            ),
          ),
        ),
      ],
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({required this.aspectRatio, required this.color});
  final double aspectRatio;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.8;
    var h = w / aspectRatio;
    if (h > size.height * 0.75) h = size.height * 0.75;
    final rect = Rect.fromCenter(center: size.center(Offset.zero).translate(0, -20), width: w, height: h);
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(Radii.m)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.35));
    final corner = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 28.0;
    for (final (o, dx, dy) in [
      (rect.topLeft, 1.0, 1.0),
      (rect.topRight, -1.0, 1.0),
      (rect.bottomLeft, 1.0, -1.0),
      (rect.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(o, o.translate(l * dx, 0), corner);
      canvas.drawLine(o, o.translate(0, l * dy), corner);
    }
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) => old.aspectRatio != aspectRatio;
}

/// Multi-select chips used throughout onboarding and preferences.
class ChoiceChipGroup extends StatelessWidget {
  const ChoiceChipGroup({super.key, required this.options, required this.selected, required this.onChanged, this.labelOf, this.single = false});

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final String Function(String)? labelOf;
  final bool single;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      children: [
        for (final o in options)
          FilterChip(
            label: Text(labelOf?.call(o) ?? o),
            selected: selected.contains(o),
            onSelected: (v) {
              if (single) {
                onChanged(v ? {o} : {});
              } else {
                onChanged(v ? {...selected, o} : ({...selected}..remove(o)));
              }
            },
          ),
      ],
    );
  }
}

/// A labelled toggle row with explanation (for settings and consents).
class ToggleTile extends StatelessWidget {
  const ToggleTile({super.key, required this.title, this.subtitle, required this.value, required this.onChanged, this.icon});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: Space.xs),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        secondary: icon == null ? null : Icon(icon),
        title: Text(title, style: context.text.titleMedium),
        subtitle: subtitle == null ? null : Text(subtitle!),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.l)),
      ),
    );
  }
}
