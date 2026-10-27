import 'package:cinema_client/quark/quark_account_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  const store = QuarkAccountStore();
  test(
    'cookie refresh and process restart preserve session cleanup scope',
    () async {
      await store.saveCookie('__puus=synthetic-A');
      final scope = await store.readSessionId();
      await store.saveCookie(
        '__puus=synthetic-A-rotated',
        preserveSession: true,
      );
      const restarted = QuarkAccountStore();
      expect(await restarted.readSessionId(), scope);
      expect(await restarted.readCookie(), '__puus=synthetic-A-rotated');
    },
  );
  test(
    'explicit account login changes scope even if only auth cookies exist',
    () async {
      await store.saveCookie('__puus=synthetic-A');
      final a = await store.readSessionId();
      await store.saveCookie('__puus=synthetic-B');
      expect(await store.readSessionId(), isNot(a));
      await store.clear();
      expect(await store.readCookie(), isNull);
      expect(await store.readSessionId(), isNull);
    },
  );
  test(
    'legacy raw cookie is readable and malformed storage requests a new login',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'quark_session_cookie_v1': '__puus=legacy-synthetic',
      });
      expect(await store.readCookie(), '__puus=legacy-synthetic');
      final scope = await store.readSessionId();
      await store.saveCookie(
        '__puus=refreshed-synthetic',
        preserveSession: true,
      );
      expect(await store.readSessionId(), scope);
      FlutterSecureStorage.setMockInitialValues({
        'quark_session_cookie_v1': '{malformed',
      });
      expect(await store.readCookie(), isNull);
    },
  );
}
