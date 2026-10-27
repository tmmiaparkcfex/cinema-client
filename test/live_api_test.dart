import 'dart:io';

import 'package:cinema_client/core/app_models.dart';
import 'package:cinema_client/core/app_settings.dart';
import 'package:cinema_client/data/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _liveBase = String.fromEnvironment('LIVE_VOD_API');

void main() {
  if (_liveBase.isEmpty) {
    test(
      'live API smoke is opt-in',
      () {},
      skip: 'Set --dart-define=LIVE_VOD_API=http://host:port',
    );
    return;
  }

  test('live API home, list, search and detail are readable', () async {
    SharedPreferences.setMockInitialValues({'vod_api_base': _liveBase});
    final settings = AppSettings.load(await SharedPreferences.getInstance());
    final api = VodApi(
      settings: settings,
      timeout: const Duration(seconds: 45),
    );
    final home = await api.fetchHome();
    expect(home.all, isNotEmpty);
    expect(home.stats, isNotEmpty);

    final movies = await api.fetchList(MediaKind.movie);
    final tv = await api.fetchList(MediaKind.tv);
    expect(movies.items, isNotEmpty);
    expect(tv.items, isNotEmpty);

    final detail = await api.fetchDetail(home.all.first.key);
    expect(detail.lines, isNotEmpty);
    expect(detail.allEntries, isNotEmpty);
    final descriptor = detail.allEntries
        .map((entry) => entry.resource)
        .whereType<MediaResource>()
        .first;
    final fetched = await api.fetchResource(descriptor.id);
    expect(fetched.id, descriptor.id);
    expect(fetched.fileId, descriptor.fileId);
    expect(fetched.shareId, descriptor.shareId);

    final search = await api.search(home.all.first.name);
    expect(search.items, isNotEmpty);

    // Keep raw filenames, share IDs and playback data out of test output.
    stdout.writeln(
      'LIVE_API_OK home=${home.all.length} moviePage=${movies.items.length} '
      'tvPage=${tv.items.length} search=${search.items.length} '
      'detailLines=${detail.lines.length} detailEntries=${detail.allEntries.length} resourceMatched=true',
    );
    api.close();
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('live duplicate work rows expand into one multi-season detail', () async {
    SharedPreferences.setMockInitialValues({'vod_api_base': _liveBase});
    final api = VodApi(
      settings: AppSettings.load(await SharedPreferences.getInstance()),
      timeout: const Duration(seconds: 45),
    );
    final tv = await api.fetchList(MediaKind.tv);
    final groups = <String, List<VodItem>>{};
    for (final item in tv.items) {
      if (item.workId.isNotEmpty) {
        groups.putIfAbsent(item.workId, () => []).add(item);
      }
    }
    final repeats = groups.values.where((items) => items.length > 1);
    if (repeats.isEmpty) {
      api.close();
      markTestSkipped(
        'Current TV page has no repeated work IDs to exercise multi-season merging',
      );
      return;
    }
    final detail = await api.fetchDetail(repeats.first.first.key);
    final seasons = detail.allEntries
        .map((entry) => entry.season)
        .whereType<int>()
        .toSet();
    expect(detail.seasonsLoaded, true);
    expect(seasons.length, greaterThan(1));
    expect(uniqueTitles(repeats.first), hasLength(1));
    stdout.writeln(
      'LIVE_SERIES_OK inputRows=${repeats.first.length} seasons=${seasons.length} entries=${detail.allEntries.length}',
    );
    api.close();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
