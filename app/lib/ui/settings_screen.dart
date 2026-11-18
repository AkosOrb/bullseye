import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../engine/target.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.settings;
    final t = Theme.of(context);
    void update(AppSettings n) => store.updateSettings(n);
    AppSettings copy({int? shots, String? target, bool? line, double? border}) => AppSettings(
          defaultShots: shots ?? s.defaultShots,
          targetId: target ?? s.targetId,
          lineTouchCountsHigher: line ?? s.lineTouchCountsHigher,
          borderlineMm: border ?? s.borderlineMm,
        );
    return CustomScrollView(slivers: [
      const SliverAppBar(title: Text('Beállítások'), pinned: true),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        sliver: SliverList.list(children: [
          const SectionHeader('Lőlap'),
          Card(
            child: Column(children: [
              ListTile(
                title: const Text('Lőlap formátuma'),
                subtitle: Text(TargetSpec.byId(s.targetId).name),
                trailing: DropdownButton<String>(
                  value: s.targetId,
                  underline: const SizedBox(),
                  items: [for (final ts in TargetSpec.all) DropdownMenuItem(value: ts.id, child: Text(ts.name))],
                  onChanged: (v) => v == null ? null : update(copy(target: v)),
                ),
              ),
              const Divider(),
              ListTile(
                title: const Text('Lövések száma egy lapon'),
                subtitle: const Text('Ennyi lövést vár a felismerés; eltérésnél szól.'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Kevesebb lövés',
                    onPressed: s.defaultShots > 1 ? () => update(copy(shots: s.defaultShots - 1)) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text('${s.defaultShots}', textAlign: TextAlign.center, style: t.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: 'Több lövés',
                    onPressed: s.defaultShots < 60 ? () => update(copy(shots: s.defaultShots + 1)) : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ]),
              ),
            ]),
          ),
          const SectionHeader('Pontozási szabály'),
          Card(
            child: Column(children: [
              SwitchListTile(
                title: const Text('Vonalérintés: a magasabb pont számít'),
                subtitle: const Text('A lövedék szélét vesszük figyelembe, nem a lyuk közepét.'),
                value: s.lineTouchCountsHigher,
                onChanged: (v) => update(copy(line: v)),
              ),
              const Divider(),
              ListTile(
                title: const Text('Határeset jelzése'),
                subtitle: Text('„Nézőkével ellenőrizendő”, ha a lövés ${fmtNum(s.borderlineMm)} mm-en belül van a magasabb gyűrűtől.'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Slider(
                  value: s.borderlineMm,
                  min: 0.5,
                  max: 3,
                  divisions: 10,
                  label: '${fmtNum(s.borderlineMm)} mm',
                  onChanged: (v) => update(copy(border: v)),
                ),
              ),
            ]),
          ),
          const SectionHeader('Az appról'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'A felismerés teljesen a telefonon fut, internet nélkül. Az eredmények és a fotók csak ezen az eszközön tárolódnak. '
                'Gyűrűk: kívülről befelé 1–13 pont; lövedék: 4,5 mm diabolo.',
                style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}
