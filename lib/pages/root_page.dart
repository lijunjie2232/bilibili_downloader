import 'package:bilibili_downloader/pages/manager_page.dart';
import 'package:bilibili_downloader/pages/login_page.dart';
import 'package:bilibili_downloader/pages/setting_page.dart';
import 'package:bilibili_downloader/pages/analyze_page.dart';
import 'package:bilibili_downloader/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _selectedIndex = 0;

  // Create pages once and keep them alive
  late final List<Widget> _pages = [
    AnalyzePage(),
    DownloadManagerPage(),
    SettingPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('B站视频下载器'),
        actions: const [UserProfile(), SizedBox(width: 16)],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        destinations: const <Widget>[
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library),
            label: '解析',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: '下载',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
      ),
    );
  }
}

class UserProfile extends StatelessWidget {
  const UserProfile({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final isLoggedIn = auth.cookieHeader.isNotEmpty;

    return isLoggedIn
        ? Row(
            children: [
              const CircleAvatar(child: Icon(Icons.person)),
              const SizedBox(width: 8),
              const Text('已登录'),
            ],
          )
        : ElevatedButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const Dialog(child: LoginPage()),
              );
            },
            child: const Text('登录'),
          );
  }
}