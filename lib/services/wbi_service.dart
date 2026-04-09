import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:bilibili_downloader/services/http_client.dart';

class WbiService {
  static final WbiService _instance = WbiService._internal();
  factory WbiService() => _instance;
  WbiService._internal();

  final Dio _dio = HttpClient.instance;
  
  String? _imgKey;
  String? _subKey;
  String? _mixinKey;
  DateTime? _keyUpdateTime;

  // WBI 重排映射表
  static const List<int> mixinKeyEncTab = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
    27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
    37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
    22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52
  ];

  /// 获取 mixin key（带缓存，每天更新一次）
  Future<String> getMixinKey() async {
    // 检查缓存是否有效（24小时）
    if (_mixinKey != null && 
        _keyUpdateTime != null && 
        DateTime.now().difference(_keyUpdateTime!).inHours < 24) {
      return _mixinKey!;
    }

    await _refreshKeys();
    return _mixinKey!;
  }

  /// 刷新 img_key 和 sub_key
  Future<void> _refreshKeys() async {
    try {
      final response = await _dio.get(
        'https://api.bilibili.com/x/web-interface/nav',
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://www.bilibili.com/',
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data['data'];
        
        // Even if not logged in (code == -101), wbi_img should still be available
        if (data != null && data['wbi_img'] != null) {
          final wbiImg = data['wbi_img'];
          final imgUrl = wbiImg['img_url'] as String;
          final subUrl = wbiImg['sub_url'] as String;
          
          // 提取文件名（不含扩展名）
          _imgKey = imgUrl.split('/').last.split('.').first;
          _subKey = subUrl.split('/').last.split('.').first;
          
          // 生成 mixin key
          _mixinKey = _generateMixinKey(_imgKey! + _subKey!);
          _keyUpdateTime = DateTime.now();
          
          stdout.writeln('WBI keys refreshed: img=$_imgKey, sub=$_subKey');
        } else {
          throw Exception('Failed to get WBI keys from nav API');
        }
      } else {
        throw Exception('Nav API returned error: ${response.data['message']}');
      }
    } catch (e) {
      stdout.writeln('Failed to refresh WBI keys: $e');
      rethrow;
    }
  }

  /// 生成 mixin key
  String _generateMixinKey(String rawKey) {
    final result = StringBuffer();
    for (int i = 0; i < 32; i++) {
      result.write(rawKey[mixinKeyEncTab[i]]);
    }
    return result.toString();
  }

  /// 对参数进行 WBI 签名
  Future<Map<String, dynamic>> encWbi(Map<String, dynamic> params) async {
    stdout.writeln('[WBI] Starting signature process...');
    stdout.writeln('[WBI] Input params: $params');
    
    final mixinKey = await getMixinKey();
    stdout.writeln('[WBI] Mixin key: $mixinKey');
    
    // 添加时间戳
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    params['wts'] = timestamp;
    stdout.writeln('[WBI] Added wts: $timestamp');
    
    // 过滤特殊字符并排序
    final filteredParams = <String, dynamic>{};
    params.forEach((key, value) {
      // 过滤掉 !'()* 字符
      final filteredValue = value.toString().split('').where((char) {
        return !"!'()*".contains(char);
      }).join();
      filteredParams[key] = filteredValue;
    });
    stdout.writeln('[WBI] Filtered params: $filteredParams');
    
    // 按键名排序
    final sortedKeys = filteredParams.keys.toList()..sort();
    stdout.writeln('[WBI] Sorted keys: $sortedKeys');
    
    // 构建查询字符串
    final queryParts = sortedKeys.map((key) {
      final encodedKey = Uri.encodeComponent(key);
      final encodedValue = Uri.encodeComponent(filteredParams[key].toString());
      return '$encodedKey=$encodedValue';
    }).join('&');
    
    stdout.writeln('[WBI] Query string: $queryParts');
    
    // 计算 MD5 签名
    final signString = queryParts + mixinKey;
    stdout.writeln('[WBI] Sign string: $signString');
    
    final wRid = md5.convert(utf8.encode(signString)).toString();
    stdout.writeln('[WBI] W_RID: $wRid');
    
    // 返回包含签名的参数
    final result = Map<String, dynamic>.from(params);
    result['w_rid'] = wRid;
    
    stdout.writeln('[WBI] Final signed params: $result');
    
    return result;
  }

  /// 清除缓存（用于测试或强制刷新）
  void clearCache() {
    _imgKey = null;
    _subKey = null;
    _mixinKey = null;
    _keyUpdateTime = null;
  }
}
