import 'dart:io';
import 'dart:typed_data';

import 'package:cinema_client/player/subtitle_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('subtitle import preserves exact bytes, contains paths, and cleans only owned copies', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cinema-subtitles-',
    );
    final original = File('${directory.path}/original.srt');
    await original.writeAsString('user original');
    final store = SubtitleFiles(directory);
    final bytes = Uint8List.fromList([65, 83, 83, 13, 10]);
    final file = await store.importFile('../../outside.ass', bytes);
    expect(file.parent.absolute.path, directory.absolute.path);
    expect(await file.readAsBytes(), bytes);
    await store.dispose();
    expect(await file.exists(), false);
    expect(await original.readAsString(), 'user original');
  });
  test(
    'unsupported or empty subtitles are rejected before writing a file',
    () async {
      final store = SubtitleFiles(
        Directory('${Directory.systemTemp.path}/cinema-unused'),
      );
      await expectLater(
        store.importFile('not-a-subtitle.exe', Uint8List.fromList([1])),
        throwsFormatException,
      );
      await expectLater(
        store.importFile('empty.srt', Uint8List(0)),
        throwsFormatException,
      );
    },
  );
}
