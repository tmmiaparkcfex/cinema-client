import 'dart:io';

import 'package:cinema_client/core/app_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'logs strip the complete cookie header, authorization and private URLs',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cinema-log-regression-',
      );
      await AppLog.initialize(directory);
      AppLog.error(
        'test',
        'Cookie: __puus=synthetic-first; __pus=synthetic-second\nAuthorization: Bearer synthetic-bearer\nhttps://example.invalid/private?token=synthetic-query',
      );
      final content = await File(AppLog.filePath).readAsString();
      for (final secret in [
        'synthetic-first',
        'synthetic-second',
        'synthetic-bearer',
        'synthetic-query',
      ]) {
        expect(content, isNot(contains(secret)));
      }
    },
  );
}
