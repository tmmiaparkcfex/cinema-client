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
      final seasonCompare = (a.season ?? 1).compareTo(b.season ?? 1);
      if (seasonCompare != 0) return seasonCompare;
      final episodeCompare = (a.episode ?? 0).compareTo(b.episode ?? 0);
      if (episodeCompare != 0) return episodeCompare;
      return a.entry.label.compareTo(b.entry.label);
    });
    return choices;
  }

  static List<EpisodeChoice> allFor(VodDetail detail) {
    return detail.lines.expand(EpisodeChoice.forLine).toList(growable: false);
  }

  static List<int> seasonsForLine(MediaLine line) {
    final seasons = EpisodeChoice.forLine(
      line,
    ).map((choice) => choice.season ?? 1).toSet().toList()..sort();
    return seasons;
  }

  static bool isSameEpisode(EpisodeChoice a, EpisodeChoice b) {
    return (a.season ?? 1) == (b.season ?? 1) && a.episode == b.episode;
  }

  static Duration resumeWithinResource(
    Duration position,
    MediaResource resource,
  ) {
    final seconds = resource.durationSeconds;
    if (seconds == null || seconds <= 0) {
      return position.isNegative ? Duration.zero : position;
    }
    final milliseconds = position.inMilliseconds.clamp(
      0,
      (seconds * 1000).round(),
    );
    return Duration(milliseconds: milliseconds);
  }

  static EpisodeChoice? nextEpisode(VodDetail detail, EpisodeChoice current) {
    if (!detail.isSeries || current.episode == null) return null;
    final currentSeason = current.season ?? 1;
    final following =
        allFor(detail).where((choice) {
          final season = choice.season ?? 1;
          final episode = choice.episode;
          if (episode == null) return false;
          return season > currentSeason ||
              (season == currentSeason && episode > current.episode!);
        }).toList()..sort((a, b) {
          final season = (a.season ?? 1).compareTo(b.season ?? 1);
          if (season != 0) return season;
          final episode = (a.episode ?? 0).compareTo(b.episode ?? 0);
          if (episode != 0) return episode;
          return (a.line.group == current.line.group ? 0 : 1).compareTo(
            b.line.group == current.line.group ? 0 : 1,
          );
        });
    final sequential = allFor(detail).where(
      (choice) =>
          (choice.season ?? 1) == currentSeason &&
          choice.episode == current.episode! + 1,
    );
    if (sequential.isNotEmpty) {
      final sameLine = sequential.where(
        (choice) => choice.line.group == current.line.group,
      );
      return sameLine.isEmpty ? sequential.first : sameLine.first;
    }
    if (following.isEmpty) return null;
    final next = following.first;
    if ((next.season ?? 1) == currentSeason) return null;
    final expected = detail.episodeCounts[currentSeason];
    if (expected == null || current.episode! < expected || next.episode != 1) {
      return null;
    }
    return next;
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

  static EpisodeChoice? choiceForEpisode(
    VodDetail detail, {
    required int? season,
    required int? episode,
    String? lineGroup,
  }) {
    final lines = detail.playableLines.toList()
      ..sort((a, b) {
        if (a.group == lineGroup) return -1;
        if (b.group == lineGroup) return 1;
        return 0;
      });
    for (final line in lines) {
      for (final choice in forLine(line)) {
        if ((choice.season ?? 1) == (season ?? 1) &&
            choice.episode == episode) {
          return choice;
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
    final matches = EpisodeChoice.forLine(line)
        .where((choice) => isSameEpisode(choice, current));
    return matches.isEmpty ? null : matches.first;
  }
}
