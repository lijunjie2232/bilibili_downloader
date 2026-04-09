class QrcodeInfo {
  final String url;
  final String qrcodeKey;

  QrcodeInfo({
    required this.url,
    required this.qrcodeKey,
  });

  factory QrcodeInfo.fromJson(Map<String, dynamic> json) {
    return QrcodeInfo(
      url: json['data']['url'],
      qrcodeKey: json['data']['qrcode_key'],
    );
  }
}
