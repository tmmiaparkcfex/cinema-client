import 'app_models.dart';

class EpisodeChoice {
  const EpisodeChoice({required this.line, required this.entry});

  final MediaLine line;
  final PlayEntry entry;

  MediaResource? get resource => entry.resource;
  int? get season => resource?.season;
  int? get episode => resource?.episode;
  bool get isPlayable => resource != null && entry.apiUrl.isNotEmpty;

  String get episodeLabel {
    if (episode != null) return '第$episode集';
    return entry.label;
  }

  String get fullLabel {
    if (season != null && episode != null) return '第$season季 第$episode集';
    return episodeLabel;
  }

  static List<EpisodeChoice> forLine(MediaLine line) {
    final choices = line.entries
        .where((entry) => entry.resource != null)
        .map((entry) => EpisodeChoice(line: line, entry: entry))
        .toList();
    choices.sort((a, b) {
      final seasonCompare = (a.season ?? 0).compareTo(b.season ?? 0);
      if (seasonCompare != 0) return seasonCompare;
      final episodeCompare = (a.episode ?? 0).compareTo(b.episode ?? 0);
      if (episodeCompare != 0) return episodeCompare;
      return a.entry.label.compareTo(b.entry.label);
    });
    return choices;
  }

  static List<EpisodeChoice> allFor(VodDetail detail) {
    return detail.lines
        .expand(EpisodeChoice.forLine)
        .toList(growable: false);
  }

  static List<int> seasonsForLine(MediaLine line) {
    final seasons = EpisodeChoice.forLine(line)
        .map((choice) => choice.season ?? 1)
        .toSet()
        .toList()
      ..sort();
    return seasons;
  }

  static EpisodeChoice? nextEpisode(VodDetail detail, EpisodeChoice current) {
    if (!detail.isSeries) return null;
    final choices = forLine(current.line)
        .where((choice) => choice.episode != null)
        .toList();
    final index = choices.indexWhere((choice) =>
        choice.season == current.season && choice.episode == current.episode);
    if (index < 0 || index + 1 >= choices.length) return null;
    return choices[index + 1];
  }

  static EpisodeChoice? choiceForResource(VodDetail detail, String resourceId) {
    for (final line in detail.lines) {
      for (final entry in line.entries) {
        if (entry.resource?.id == resourceId) {
          return EpisodeChoice(line: line, entry: entry);
        }
      }
    }
    return null;
  }

  static EpisodeChoice? sameEpisodeInLine(
    VodDetail detail,
    MediaLine line,
    EpisodeChoice current,
  ) {
    final matches = EpisodeChoice.forLine(line).where((choice) =>
        choice.season == current.season && choice.episode == current.episode);
    if (matches.isNotEmpty) return matches.first;
    final choices = EpisodeChoice.forLine(line);
    return choices.isEmpty ? null : choices.first;
  }
}
