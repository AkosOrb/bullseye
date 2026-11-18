// A lap nevének és lövőjének megadása (versenyhez, több lövő esetén).
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/store.dart';
import 'theme.dart';

Future<bool> editSheetLabel(BuildContext context, Sheet sheet) async {
  final store = StoreScope.of(context);
  final known = store.knownShooters();
  final name = TextEditingController(text: sheet.name);
  final shooter = TextEditingController(text: sheet.shooter);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Lap neve és lövője'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Lap neve', helperText: 'Nem kötelező, pl. „1. sorozat”'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: shooter,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Lövő', helperText: 'Versenyhez: így készül rangsor'),
              onChanged: (_) => set(() {}),
            ),
            if (known.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('korábbi lövők', style: Theme.of(ctx).textTheme.labelMedium?.copyWith(color: kTaupe)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final n in known.take(12))
                  ChoiceChip(
                    label: Text(n),
                    selected: shooter.text.trim() == n,
                    onSelected: (_) => set(() => shooter.text = n),
                  ),
              ]),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mentés')),
        ],
      ),
    ),
  );
  if (ok == true) {
    sheet.name = name.text.trim();
    sheet.shooter = shooter.text.trim();
    await store.changed();
    return true;
  }
  return false;
}
