import 'package:flutter/cupertino.dart';
import 'download_manager.dart';
import 'screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DownloadManager.instance.init();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => const CupertinoApp(
        title: 'Offline DM',
        debugShowCheckedModeBanner: false,
        theme: CupertinoThemeData(primaryColor: CupertinoColors.activeBlue),
        home: RootTabs(),
      );
}
