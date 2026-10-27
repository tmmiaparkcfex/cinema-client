import 'package:cinema_client/core/app_models.dart';
import 'package:cinema_client/data/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
