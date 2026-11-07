/// Adapts vod-web's public verified feed to the existing Cinema data models.
/// Android spider code is not downloaded or executed.
abstract final class TvBoxCatalog {
  static const feedPath = '/api.php/provide/verified/';

  static Map<String, dynamic> item(Map<String, dynamic> raw, Uri origin) {
    final key = raw['vod_id']?.toString() ?? '';
    final lines = <String, List<Map<String, dynamic>>>{};
    final episodeNames = <Object?, Object?>{
      for (final episode in (raw['episodes'] as List? ?? []).whereType<Map>())
        episode['episode']: episode['name'],
    };
    for (final resource in (raw['resources'] as List? ?? []).whereType<Map>()) {
      final id = resource['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final group = resource['group']?.toString() ?? '默认线路';
      final episode = resource['episode'];
      final name = episodeNames[episode]?.toString() ?? '';
      final label = episode == null
          ? '正片'
          : '第$episode集${name.isEmpty ? '' : ' · $name'}';
      lines.putIfAbsent(group, () => []).add({
        'label': label,
        'url': origin
            .replace(path: '/api/resource', queryParameters: {'id': id})
            .toString(),
        'resource': {...resource, 'catalogKey': key},
      });
    }
    final mappedLines = [
      for (final entry in lines.entries)
        {'group': entry.key, 'entries': entry.value, 'has4k': true},
    ];
    return {
      ...raw,
      'key': key,
      'id': key,
      'workId': raw['work_id'],
      'mediaType': raw['media_type'],
      'name': raw['vod_name'],
      'year': raw['vod_year'],
      'poster': raw['vod_pic'],
      'backdrop': raw['vod_backdrop'],
      'genres': raw['vod_class'],
      'runtimeMinutes': raw['vod_duration'],
      'content': raw['vod_content'],
      'score': raw['vod_score'],
      'area': raw['vod_area'],
      'actor': raw['vod_actor'],
      'director': raw['vod_director'],
      'updated': raw['vod_time'],
      'lines': mappedLines,
      'sources': [
        {'lines': mappedLines},
      ],
    };
  }
}
