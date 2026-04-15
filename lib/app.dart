import 'package:bilibili_downloader/pages/root_page.dart';
import 'package:bilibili_downloader/services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return MaterialApp(
          title: 'B站视频下载器',
          themeMode: themeService.materialThemeMode,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              elevation: 0,
              centerTitle: true,
            ),
            navigationBarTheme: const NavigationBarThemeData(
              elevation: 0,
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
            useMaterial3: true,
          ),
          home: const RootPage(),
        );
      },
    );
  }
}
