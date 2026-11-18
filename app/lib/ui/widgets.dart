// Közös felületi elemek és formázók.
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/store.dart';

String fmtDate(DateTime d) => DateFormat('y. MMMM d., EEEE', 'hu').format(d);
String fmtShortDate(DateTime d) => DateFormat('y. MM. dd.', 'hu').format(d);
String fmtTime(DateTime d) => DateFormat('HH:mm', 'hu').format(d);
String fmtNum(double v, [int digits = 1]) => v.toStringAsFixed(digits).replaceAll('.', ',');

/// Üres állapot: mi kerül ide, miért jó, és egy elsődleges művelet.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: t.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(title, style: t.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(body,
                  style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
              if (actionLabel != null) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: Icon(actionIcon ?? Icons.add),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Kis statisztikai csempe: címke + érték.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.sub});
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(value,
                style: t.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
            if (sub != null)
              Text(sub!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Figyelmeztető sáv (pl. lövésszám-eltérés).
class NoticeCard extends StatelessWidget {
  const NoticeCard({super.key, required this.text, this.actionLabel, this.onAction, this.icon = Icons.info_outline});
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.colorScheme.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.colorScheme.tertiary.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: t.colorScheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onTertiaryContainer))),
          if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// Szakaszcím a listákban.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(children: [
        Expanded(child: Text(text, style: t.textTheme.titleSmall?.copyWith(color: t.colorScheme.onSurfaceVariant))),
        ?trailing,
      ]),
    );
  }
}

/// Statisztikai csempék két oszlopban, a tartalomhoz igazodó magassággal.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: children[i]),
          const SizedBox(width: 8),
          Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
        ]),
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}


/// A lap fotója a tárolóból (telefonon fájl, böngészőben IndexedDB).
class SheetImage extends StatefulWidget {
  const SheetImage({super.key, required this.sheet, this.fit = BoxFit.cover, this.cacheWidth, this.placeholder});
  final Sheet sheet;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget? placeholder;

  @override
  State<SheetImage> createState() => _SheetImageState();
}

class _SheetImageState extends State<SheetImage> {
  Future<Uint8List?>? _future;
  String? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(SheetImage old) {
    super.didUpdateWidget(old);
    _load();
  }

  void _load() {
    if (_key == widget.sheet.imagePath && _future != null) return;
    _key = widget.sheet.imagePath;
    _future = StoreScope.of(context).imageBytes(widget.sheet);
  }

  @override
  Widget build(BuildContext context) {
    final ph = widget.placeholder ?? const SizedBox.shrink();
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        final b = snap.data;
        if (b == null) return ph;
        return Image.memory(b,
            fit: widget.fit, cacheWidth: widget.cacheWidth, gaplessPlayback: true, errorBuilder: (_, _, _) => ph);
      },
    );
  }
}
