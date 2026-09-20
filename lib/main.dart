import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'utils/theme.dart';
import 'screens/splash_screen.dart';

// Shared by any screen that needs to know when it's become visible again
// after a screen pushed on top of it was popped — HomeScreen uses this to
// refresh its activation/trial/progress state every time the user comes
// back to it, instead of only ever loading it once on first launch.
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadSavedDarkMode();

  // Lock to portrait on mobile; allow landscape on tablet/desktop
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const SjActApp());
}

class SjActApp extends StatelessWidget {
  const SjActApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: darkModeNotifier,
      builder: (context, isDark, _) {
        return MaterialApp(
          title: 'SJ ACT',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          navigatorObservers: [routeObserver],
          home: const SplashScreen(),
        );
      },
    );
  }
}
