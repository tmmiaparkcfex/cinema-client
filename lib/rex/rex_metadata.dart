import '../core/app_models.dart';

extension RexMetadata on VodItem {
  String? get heroImage => _text(metadata['backdrop']) ?? backdrop ?? poster;
  String? get posterImage => poster ?? _text(metadata['poster']);
  String? get titleLogo {
    final artwork = metadata['artwork'];
    final logos = artwork is Map ? artwork['logos'] : null;
    return logos is List && logos.isNotEmpty && logos.first is Map
        ? _text(logos.first['url'])
        : null;
  }

  String get synopsis =>
      overview.isNotEmpty ? overview : _text(metadata['overview']) ?? '';
  DateTime? get releaseDate =>
      DateTime.tryParse(_text(metadata['releaseDate']) ?? '');
  List<String> get categories => genres.isNotEmpty
      ? genres
            .expand((v) => v.split(RegExp(r'\s*[/、,|]\s*')))
            .where((v) => v.isNotEmpty)
            .toList()
      : _strings(metadata['genres']);
  List<String> get studios => _strings(metadata['studios']);
  List<String> get countries =>
      area.isNotEmpty ? [area] : _strings(metadata['countries']);
  List<Map<String, dynamic>> get people {
    final value = metadata['cast'];
    if (value is List) {
      return value
          .whereType<Map>()
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
    }
    return actors
        .split(RegExp(r'[/、,]'))
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .map((v) => <String, dynamic>{'name': v})
        .toList();
  }

  List<String> get stillImages {
    final artwork = metadata['artwork'];
    final rows = artwork is Map ? artwork['backdrops'] : null;
    return rows is List
        ? rows
              .whereType<Map>()
              .map((v) => _text(v['url']))
              .whereType<String>()
              .toList()
        : [];
  }

  List<Map<String, dynamic>> get seasons => metadata['seasons'] is List
      ? (metadata['seasons'] as List)
            .whereType<Map>()
            .map((v) => Map<String, dynamic>.from(v))
            .toList()
      : [];
  int countForSeason(int season) {
    final row = seasons.where((v) => v['season'] == season).firstOrNull;
    return (row?['episodeCount'] as num?)?.toInt() ??
        episodes.where((v) => v['season'] == season).length;
  }

  Map<String, dynamic>? episodeInfo(int season, int episode) => episodes
      .where((v) => v['season'] == season && v['episode'] == episode)
      .firstOrNull;
}

String? _text(Object? v) =>
    v is String && v.trim().isNotEmpty ? v.trim() : null;
List<String> _strings(Object? v) =>
    v is List ? v.whereType<String>().where((v) => v.isNotEmpty).toList() : [];
