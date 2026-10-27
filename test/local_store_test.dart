import 'package:cinema_client/core/app_models.dart';
import 'package:cinema_client/data/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seasons share one favorite and one resume record without losing API lookup IDs', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LocalStore.load(prefs);
    const first = VodItem(
      key: 'season-1',
      workId: 'tmdb:tv:2',
      name: 'show',
      mediaType: MediaKind.tv,
    );
    const second = VodItem(
      key: 'season-2',
      workId: 'tmdb:tv:2',
      name: 'show',
      mediaType: MediaKind.tv,
    );
    await store.toggleFavorite(first);
    expect(store.isFavoriteItem(second), true);
    final resource = MediaResource.fromJson({
      'id': 'season-2-episode-1',
      'season': 2,
      'episode': 1,
      'catalogKey': 'season-2',
    });
    await store.saveProgress(
      item: first,
      resource: resource,
      position: const Duration(seconds: 20),
      duration: const Duration(minutes: 40),
      lineGroup: 'A',
    );
    expect(store.history.single.toItem().key, 'season-2');
    await store.saveProgress(
      item: second,
      resource: resource,
      position: const Duration(seconds: 50),
      duration: const Duration(minutes: 40),
      lineGroup: 'B',
    );
    final loaded = LocalStore.load(prefs);
    expect(loaded.history, hasLength(1));
    expect(loaded.recordForItem(first)?.positionMs, 50000);
    expect(loaded.history.single.toItem().key, 'season-2');
    expect(loaded.favorites.single.toItem().key, 'season-1');
    await loaded.toggleFavorite(second);
    expect(loaded.isFavoriteItem(first), false);
  });

  test('favorites and progress survive a new store instance', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LocalStore.load(prefs);
    const item = VodItem(
      key: 'verified__sample_tv',
      name: '测试剧集',
      mediaType: MediaKind.tv,
      year: 2025,
    );
    const resource = MediaResource(
      id: 'resource-1',
      shareUrl: '',
      shareId: '',
      sharePassword: '',
      fileId: '',
      fileName: '',
      filePath: '',
      sizeBytes: 0,
      tier: 'standard',
      season: 1,
      episode: 2,
    );
    await store.toggleFavorite(item);
    await store.saveProgress(
      item: item,
      resource: resource,
      position: const Duration(minutes: 12),
      duration: const Duration(minutes: 45),
      lineGroup: '普通主线',
    );
    final reloaded = LocalStore.load(prefs);
    expect(reloaded.isFavorite(item.key), isTrue);
    expect(reloaded.recordFor(item.key)?.episode, 2);
    expect(reloaded.recordFor(item.key)?.positionMs, 720000);
    await reloaded.removeHistoryRecord(item.key);
    expect(reloaded.history, isEmpty);
  });
}
