import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class RexPlayerTools {
  List<PlaybackComment> comments = [];
  bool commentsEnabled = false;
  String keywords = '';
  double opacity = .76;
  double delay = 0;
  double audioDelay = 0;
  final Map<int, String> marks = {};
  int? segmentStart;

  void loadComments(String raw) {
    final parsed = <PlaybackComment>[];
    for (final match in RegExp(
      r'<d\s+[^>]*p="([^"]+)"[^>]*>([\s\S]*?)</d>',
    ).allMatches(raw)) {
      final seconds = double.tryParse(match.group(1)!.split(',').first);
      final value = match
          .group(2)!
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&amp;', '&')
          .trim();
      if (seconds != null &&
          seconds.isFinite &&
          seconds >= 0 &&
          value.isNotEmpty) {
        parsed.add(PlaybackComment(seconds, value));
      }
      if (parsed.length == 20000) break;
    }
    if (parsed.isEmpty && raw.trimLeft().startsWith('{')) {
      final json = jsonDecode(raw);
      if (json is Map && json['comments'] is List) {
        for (final row in (json['comments'] as List).whereType<Map>().take(
          20000,
        )) {
          final seconds = double.tryParse(
            row['p']?.toString().split(',').first ?? '',
          );
          final value = row['m']?.toString().trim() ?? '';
          if (seconds != null &&
              seconds.isFinite &&
              seconds >= 0 &&
              value.isNotEmpty) {
            parsed.add(PlaybackComment(seconds, value));
          }
        }
      }
    }
    if (parsed.isEmpty) throw const FormatException('没有读到带时间轴的弹幕');
    comments = parsed..sort((a, b) => a.seconds.compareTo(b.seconds));
    commentsEnabled = true;
  }
}

class PlaybackComment {
  const PlaybackComment(this.seconds, this.text);
  final double seconds;
  final String text;
}

class RexComments extends StatelessWidget {
  const RexComments({super.key, required this.tools, required this.position});
  final RexPlayerTools tools;
  final Duration position;

  @override
  Widget build(BuildContext context) {
    final keywords = tools.keywords
        .split(RegExp(r'[,，\n]'))
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty);
    final now = position.inMilliseconds / 1000 - tools.delay;
    final rows = tools.comments
        .where(
          (v) =>
              now >= v.seconds &&
              now - v.seconds < 7 &&
              !keywords.any(v.text.contains),
        )
        .take(8)
        .toList();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) => ClipRect(
          child: Stack(
            children: [
              for (var i = 0; i < rows.length; i++)
                Positioned(
                  top: 7 + i % 3 * 23,
                  left:
                      box.maxWidth -
                      (box.maxWidth +
                              math.min(600, rows[i].text.length * 15.0)) *
                          (now - rows[i].seconds) /
                          7,
                  child: Opacity(
                    opacity: tools.opacity,
                    child: Text(
                      rows[i].text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
