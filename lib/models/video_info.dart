class VideoInfo {
  final String bvid;
  final String title;
  final String coverUrl;
  final String intro;
  final List<VideoPart> parts;

  VideoInfo({
    required this.bvid,
    required this.title,
    required this.coverUrl,
    required this.intro,
    required this.parts,
  });
}

class VideoPart {
  final String cid;
  final String title;
  final int duration;

  VideoPart({
    required this.cid,
    required this.title,
    required this.duration,
  });
}
