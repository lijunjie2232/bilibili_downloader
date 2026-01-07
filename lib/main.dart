import 'package:bilibili_downloader/app.dart';
import 'package:bilibili_downloader/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final authService = AuthService();
  await authService.loadCookie();
  runApp(ChangeNotifierProvider.value(value: authService, child: const App()));
}
