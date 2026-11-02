Map<String, dynamic> _object(Object? value) => value is Map
    ? value.cast<String, dynamic>() : const {};
String _text(Object? value) => value?.toString().trim() ?? '';
num? _number(Object? value) => value is num ? value : num.tryParse(_text(value));

class MediaCredit {
  const MediaCredit(this.name, this.role, this.portrait);
  final String name;
  final String role;
  final String? portrait;
}

class EpisodeInfo {
  EpisodeInfo(Map<String, dynamic> json)
      : season = _number(json['season'])?.toInt() ?? 1,
        episode = _number(json['episode'])?.toInt() ?? 0,
        name = _text(json['name']),
        overview = _text(json['overview']),
        still = _text(json['still']),
        airDate = _text(json['airDate']),
        runtimeMinutes = (_number(json['runtimeSeconds']) ?? 0) ~/ 60;
  final int season;
  final int episode;
  final String name;
  final String overview;
  final String still;
  final String airDate;
  final int runtimeMinutes;
}

// Preserve the provider's IDs and episode identity. Never rematch a confirmed
// work on the phone merely because its translated display title changed.
class MediaMetadata {
  const MediaMetadata({this.data = const {}, this.episodeData = const []});
  factory MediaMetadata.fromJson(Object? data, Object? episodes) => MediaMetadata(
    data: Map.unmodifiable(_object(data)),
    episodeData: episodes is List
        ? List.unmodifiable(episodes.whereType<Map>().map(_object)) : const [],
  );
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> episodeData;
  String get originalTitle => _text(data['originalTitle']);
  String get tagline => _text(data['tagline']);
  String get overview => _text(data['overview']);
  String get poster => _text(data['poster']);
  String get backdrop => _text(data['backdrop']);
  String get source => _text(data['source']);
  String get id => _text(data['tmdbId']);
  int? get runtimeMinutes => _number(data['runtimeMinutes'])?.toInt();
  String get score => data['rating'] is num
      ? (data['rating'] as num).toStringAsFixed(1) : '';
  List<String> get genres => _labels(data['genres']);
  List<String> get studios => _labels(data['studios']);
  List<String> _labels(Object? value) => value is List
      ? value.map((v) => _text(v is Map ? v['name'] : v))
          .where((s) => s.isNotEmpty).toList() : const [];

  List<MediaCredit> get credits {
    final result = <MediaCredit>[];
    for (final key in ['directors', 'cast']) {
      final values = data[key];
      if (values is! List) continue;
      for (final value in values.whereType<Map>()) {
        final name = _text(value['name']);
        if (name.isEmpty) continue;
        final role = key == 'directors' ? '导演' : _text(value['character']);
        final profile = _text(value['profile']);
        result.add(MediaCredit(name, role.isEmpty ? '演员' : role,
            profile.isEmpty ? null : profile));
      }
    }
    return result;
  }

  EpisodeInfo? episode(int season, int number) {
    for (final row in episodeData) {
      final info = EpisodeInfo(row);
      if (info.season == season && info.episode == number) return info;
    }
    return null;
  }
}
