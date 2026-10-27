enum MediaKind { movie, tv, unknown }

MediaKind parseMediaKind(Object? value) {
  return switch (value) {
    'tv' => MediaKind.tv,
    'movie' => MediaKind.movie,
    _ => MediaKind.unknown,
  };
}

int? _intValue(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().split('.').first);
}

double? _doubleValue(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value.map(_map).toList(growable: false);
}

List<String> _stringList(Object? value) {
  if (value is String) return value.trim().isEmpty ? const [] : [value];
  if (value is! List) return const [];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String? _firstText(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return null;
}

class Coverage {
  const Coverage({
    this.expected = 0,
    this.covered = 0,
    this.standardCovered = 0,
    this.largeCovered = 0,
    this.complete = false,
  });

  final int expected;
  final int covered;
  final int standardCovered;
  final int largeCovered;
  final bool complete;

  factory Coverage.fromJson(Object? value) {
    final json = _map(value);
    return Coverage(
      expected: _intValue(json['expected']) ?? 0,
      covered: _intValue(json['covered']) ?? 0,
      standardCovered: _intValue(json['standardCovered']) ?? 0,
      largeCovered: _intValue(json['largeCovered']) ?? 0,
      complete: json['complete'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'expected': expected,
    'covered': covered,
    'standardCovered': standardCovered,
    'largeCovered': largeCovered,
    'complete': complete,
  };
}

class VodItem {
  const VodItem({
    required this.key,
    required this.name,
    required this.mediaType,
    this.workId = '',
    this.catalogLines = const [],
    this.year,
    this.poster,
    this.backdrop,
    this.genres = const [],
    this.runtimeMinutes,
    this.overview = '',
    this.remarks = const [],
    this.score = '',
    this.actors = '',
    this.directors = '',
    this.area = '',
    this.language = '',
    this.updatedAt = '',
    this.coverage,
  });

  final String key;
  final String workId;
  final List<MediaLine> catalogLines;
  String get identityKey => workId.isEmpty ? key : workId;
  final String name;
  final MediaKind mediaType;
  final int? year;
  final String? poster;
  final String? backdrop;
  final List<String> genres;
  final int? runtimeMinutes;
  final String overview;
  final List<String> remarks;
  final String score;
  final String actors;
  final String directors;
  final String area;
  final String language;
  final String updatedAt;
  final Coverage? coverage;

  bool get isTv => mediaType == MediaKind.tv;
  bool get isResolved => mediaType != MediaKind.unknown;

  String get typeLabel => switch (mediaType) {
    MediaKind.tv => '电视剧',
    MediaKind.movie => '电影',
    MediaKind.unknown => '类型待补齐',
  };

  factory VodItem.fromCatalogJson(Map<String, dynamic> json) {
    final pictures = _stringList(json['pics']);
    final poster = pictures.isEmpty
        ? _firstText(json, const ['pic', 'poster', 'vod_pic'])
        : pictures.first;
    return VodItem(
      key: _firstText(json, const ['key', 'id', 'vod_id']) ?? '',
      workId: _firstText(json, const ['workId', 'work_id']) ?? '',
      catalogLines: [
        for (final source in _mapList(json['sources']))
          for (final line in _mapList(source['lines']))
            MediaLine.fromJson({
              ...line,
              'entries': line['preview'] ?? line['entries'],
            }, catalogKey: _firstText(json, const ['key', 'id', 'vod_id'])),
      ],
      name: _firstText(json, const ['name', 'vod_name']) ?? '未命名作品',
      mediaType: parseMediaKind(json['mediaType'] ?? json['type_name']),
      year: _intValue(json['year'] ?? json['vod_year']),
      poster: poster,
      backdrop: _firstText(json, const [
        'backdrop',
        'backdropUrl',
        'background',
      ]),
      genres: _stringList(json['genres']),
      runtimeMinutes: _intValue(json['runtimeMinutes']),
      overview:
          _firstText(json, const ['content', 'overview', 'vod_content']) ?? '',
      remarks: _stringList(json['remarks']),
      score: _firstText(json, const ['score', 'vod_score']) ?? '',
      actors: _firstText(json, const ['actor', 'actors']) ?? '',
      directors: _firstText(json, const ['director', 'directors']) ?? '',
      updatedAt: _firstText(json, const ['updated', 'vod_time']) ?? '',
      coverage: json['coverage'] == null
          ? null
          : Coverage.fromJson(json['coverage']),
    );
  }

  factory VodItem.fromDetailJson(Map<String, dynamic> json) {
    return VodItem(
      key: _firstText(json, const ['id', 'key']) ?? '',
      workId: _firstText(json, const ['workId', 'work_id']) ?? '',
      name: _firstText(json, const ['name', 'vod_name']) ?? '未命名作品',
      mediaType: parseMediaKind(json['mediaType'] ?? json['type_name']),
      year: _intValue(json['year'] ?? json['vod_year']),
      poster: _firstText(json, const ['pic', 'poster', 'vod_pic']),
      backdrop: _firstText(json, const [
        'backdrop',
        'backdropUrl',
        'background',
      ]),
      genres: _stringList(json['genres']),
      runtimeMinutes: _intValue(json['runtimeMinutes']),
      overview: _firstText(json, const ['content', 'blurb', 'overview']) ?? '',
      remarks: _stringList(json['remarks']),
      score: _firstText(json, const ['score', 'vod_score']) ?? '',
      actors: _firstText(json, const ['actor', 'actors']) ?? '',
      directors: _firstText(json, const ['director', 'directors']) ?? '',
      area: _firstText(json, const ['area']) ?? '',
      language: _firstText(json, const ['lang', 'language']) ?? '',
      updatedAt: _firstText(json, const ['updated', 'vod_time']) ?? '',
      coverage: json['coverage'] == null
          ? null
          : Coverage.fromJson(json['coverage']),
    );
  }

  VodItem copyWith({
    String? key,
    String? workId,
    String? name,
    MediaKind? mediaType,
    int? year,
    String? poster,
    String? backdrop,
    List<String>? genres,
    int? runtimeMinutes,
    String? overview,
    List<String>? remarks,
    String? score,
    String? actors,
    String? directors,
    String? area,
    String? language,
    String? updatedAt,
    Coverage? coverage,
  }) {
    return VodItem(
      key: key ?? this.key,
      workId: workId ?? this.workId,
      catalogLines: catalogLines,
      name: name ?? this.name,
      mediaType: mediaType ?? this.mediaType,
      year: year ?? this.year,
      poster: poster ?? this.poster,
      backdrop: backdrop ?? this.backdrop,
      genres: genres ?? this.genres,
      runtimeMinutes: runtimeMinutes ?? this.runtimeMinutes,
      overview: overview ?? this.overview,
      remarks: remarks ?? this.remarks,
      score: score ?? this.score,
      actors: actors ?? this.actors,
      directors: directors ?? this.directors,
      area: area ?? this.area,
      language: language ?? this.language,
      updatedAt: updatedAt ?? this.updatedAt,
      coverage: coverage ?? this.coverage,
    );
  }

  Map<String, dynamic> toCacheJson() => {
    'key': key,
    'workId': workId,
    'name': name,
    'mediaType': mediaType.name,
    'year': year,
    'poster': poster,
    'backdrop': backdrop,
    'genres': genres,
    'runtimeMinutes': runtimeMinutes,
    'actors': actors,
    'directors': directors,
    'overview': overview,
    'remarks': remarks,
    'score': score,
    'updatedAt': updatedAt,
    'coverage': coverage?.toJson(),
  };

  factory VodItem.fromCacheJson(Map<String, dynamic> json) =>
      VodItem.fromCatalogJson(Map<String, dynamic>.from(json));
}

class MediaResource {
  const MediaResource({
    required this.id,
    required this.shareUrl,
    required this.shareId,
    required this.sharePassword,
    required this.fileId,
    required this.fileName,
    required this.filePath,
    required this.sizeBytes,
    required this.tier,
    this.catalogKey = '',
    this.season,
    this.episode,
    this.width,
    this.height,
    this.codec,
    this.bitrate,
    this.durationSeconds,
    this.bitDepth,
    this.verificationLevel,
  });

  final String id;
  final String catalogKey;
  final String shareUrl;
  final String shareId;
  final String sharePassword;
  final String fileId;
  final String fileName;
  final String filePath;
  final int sizeBytes;
  final String tier;
  final int? season;
  final int? episode;
  final int? width;
  final int? height;
  final String? codec;
  final int? bitrate;
  final double? durationSeconds;
  final int? bitDepth;
  final String? verificationLevel;

  bool get isLarge => tier == 'large';

  String get tierLabel => isLarge ? '大文件线路' : '普通线路';

  String get technicalSummary {
    final parts = <String>[];
    if (width != null && height != null) parts.add('$width×$height');
    if (codec != null && codec!.isNotEmpty) parts.add(codec!.toUpperCase());
    if (bitDepth != null) parts.add('$bitDepth-bit');
    if (bitrate != null && bitrate! > 0) {
      parts.add('${(bitrate! / 1000000).toStringAsFixed(1)} Mbps');
    }
    if (sizeBytes > 0) {
      parts.add('${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB');
    }
    return parts.join(' · ');
  }

  factory MediaResource.fromJson(Map<String, dynamic> json) {
    final share = _map(json['share']);
    final file = _map(json['file']);
    final video = _map(json['video']);
    final verification = _map(json['verification']);
    final shareUrl = _firstText(share, const ['url']) ?? '';
    var shareId = _firstText(share, const ['id']) ?? '';
    if (shareId.isEmpty && shareUrl.isNotEmpty) {
      final segments = Uri.tryParse(shareUrl)?.pathSegments ?? const <String>[];
      if (segments.length >= 2) shareId = segments[1];
    }
    return MediaResource(
      id: _firstText(json, const ['id']) ?? '',
      catalogKey: _firstText(json, const ['catalogKey']) ?? '',
      shareUrl: shareUrl,
      shareId: shareId,
      sharePassword: _firstText(share, const ['password']) ?? '',
      fileId: _firstText(file, const ['id']) ?? '',
      fileName: _firstText(file, const ['name']) ?? '未知文件',
      filePath: _firstText(file, const ['path']) ?? '',
      sizeBytes: _intValue(file['sizeBytes']) ?? 0,
      tier: _firstText(json, const ['tier']) ?? 'standard',
      season: _intValue(json['season']),
      episode: _intValue(json['episode']),
      width: _intValue(video['width']),
      height: _intValue(video['height']),
      codec: _firstText(video, const ['codec']),
      bitrate: _intValue(video['bitrate']),
      durationSeconds: _doubleValue(video['durationSeconds']),
      bitDepth: _intValue(video['bitDepth']),
      verificationLevel: _firstText(verification, const ['level']),
    );
  }
}

class PlayEntry {
  const PlayEntry({
    required this.label,
    required this.apiUrl,
    required this.group,
    this.quality,
    this.resource,
  });

  final String label;
  final String apiUrl;
  final String group;
  final String? quality;
  final MediaResource? resource;

  int? get season => resource?.season;
  int? get episode => resource?.episode;

  factory PlayEntry.fromJson(
    Map<String, dynamic> json, {
    required String group,
    String? catalogKey,
  }) {
    return PlayEntry(
      label: _firstText(json, const ['label']) ?? '正片',
      apiUrl: _firstText(json, const ['url']) ?? '',
      group: group,
      quality: _firstText(json, const ['quality']),
      resource: json['resource'] == null
          ? null
          : MediaResource.fromJson({
              ..._map(json['resource']),
              'catalogKey':
                  catalogKey ?? _map(json['resource'])['catalogKey'] ?? '',
            }),
    );
  }
}

class MediaLine {
  const MediaLine({
    required this.group,
    required this.entries,
    this.has4k = false,
    this.qualities = const [],
  });

  final String group;
  final List<PlayEntry> entries;
  final bool has4k;
  final List<String> qualities;

  factory MediaLine.fromJson(Map<String, dynamic> json, {String? catalogKey}) {
    final group = _firstText(json, const ['group']) ?? '默认线路';
    return MediaLine(
      group: group,
      has4k: json['has4k'] == true,
      qualities: _stringList(json['qualities']),
      entries: _mapList(json['entries'])
          .map(
            (entry) =>
                PlayEntry.fromJson(entry, group: group, catalogKey: catalogKey),
          )
          .toList(growable: false),
    );
  }
}

class VodDetail {
  const VodDetail({
    required this.item,
    required this.lines,
    this.seasonsLoaded = true,
    this.episodeCounts = const {},
  });

  final VodItem item;
  final List<MediaLine> lines;
  final bool seasonsLoaded;
  final Map<int, int> episodeCounts;

  List<PlayEntry> get allEntries =>
      lines.expand((line) => line.entries).toList(growable: false);

  List<MediaLine> get playableLines =>
      lines.where((line) => line.entries.isNotEmpty).toList(growable: false);

  /// Uses measured episode numbers when upstream metadata did not set a type.
  bool get isSeries =>
      item.isTv || allEntries.any((entry) => entry.resource?.episode != null);

  factory VodDetail.fromJson(Map<String, dynamic> json) {
    final itemJson = _map(json['item']);
    final item = VodItem.fromDetailJson(itemJson);
    return VodDetail(
      item: item,
      lines: _mapList(json['lines'])
          .map((line) => MediaLine.fromJson(line, catalogKey: item.key))
          .toList(growable: false),
    );
  }
}

class HomeFeed {
  const HomeFeed({
    required this.fourK,
    required this.latest,
    this.stats = const {},
    this.fromCache = false,
  });

  final List<VodItem> fourK;
  final List<VodItem> latest;
  final Map<String, dynamic> stats;
  final bool fromCache;

  factory HomeFeed.fromJson(
    Map<String, dynamic> json, {
    bool fromCache = false,
  }) {
    return HomeFeed(
      fourK: _mapList(json['fourK'])
          .map(VodItem.fromCatalogJson)
          .where((item) => item.key.isNotEmpty)
          .toList(growable: false),
      latest: _mapList(json['latest'])
          .map(VodItem.fromCatalogJson)
          .where((item) => item.key.isNotEmpty)
          .toList(growable: false),
      stats: _map(json['stats']),
      fromCache: fromCache,
    );
  }

  Map<String, dynamic> toCacheJson() => {
    'fourK': fourK.map((item) => item.toCacheJson()).toList(),
    'latest': latest.map((item) => item.toCacheJson()).toList(),
    'stats': stats,
  };

  List<VodItem> get all {
    return uniqueTitles([...fourK, ...latest]);
  }
}

List<VodItem> uniqueTitles(Iterable<VodItem> items) {
  final seen = <String>{};
  return items
      .where((item) => seen.add(item.identityKey))
      .toList(growable: false);
}

class CatalogPage {
  const CatalogPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageCount,
  });

  final List<VodItem> items;
  final int total;
  final int page;
  final int pageCount;

  factory CatalogPage.fromJson(Map<String, dynamic> json) {
    return CatalogPage(
      items: _mapList(json['items'])
          .map(VodItem.fromCatalogJson)
          .where((item) => item.key.isNotEmpty)
          .toList(growable: false),
      total: _intValue(json['total']) ?? 0,
      page: _intValue(json['page']) ?? 1,
      pageCount: _intValue(json['pagecount']) ?? 1,
    );
  }
}
