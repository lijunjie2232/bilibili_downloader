import 'package:bilibili_downloader/pages/root_page.dart';
import 'package:flutter/material.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bilibili Downloader',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const RootPage(),
    );
  }
}
