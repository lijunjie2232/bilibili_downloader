import 'package:bilibili_downloader/models/qrcode_info.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  QrcodeInfo? _qrcodeInfo;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _getQrcode();
  }

  void _getQrcode() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final qrcodeInfo = await auth.getQrcode();
      setState(() {
        _qrcodeInfo = qrcodeInfo;
      });
      _poll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error getting QR code: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _poll() async {
    if (_qrcodeInfo == null) return;
    final auth = Provider.of<AuthService>(context, listen: false);
    while (true) {
      await Future.delayed(const Duration(seconds: 3));
      final result = await auth.poll(_qrcodeInfo!.qrcodeKey);
      if (result == 1) {
        break;
      } else if (result == 86038) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('QR code expired')));
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : _qrcodeInfo != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: _qrcodeInfo!.url,
                      version: QrVersions.auto,
                      size: 200.0,
                      foregroundColor: Colors.black,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    '使用B站APP扫描二维码登录',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _getQrcode,
        tooltip: 'Refresh QR Code',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
