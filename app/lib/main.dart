import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'data/store.dart';
import 'ui/home.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('hu');
  Intl.defaultLocale = 'hu';
  final store = await AppStore.open();
  runApp(BullseyeApp(store: store));
}

class BullseyeApp extends StatelessWidget {
  const BullseyeApp({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: store,
      child: MaterialApp(
        title: 'Lőlap kiértékelő',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.dark,
        locale: const Locale('hu'),
        home: const HomeShell(),
      ),
    );
  }
}
