import 'dart:io';
import 'dart:typed_data';

class SubtitleFiles {
  SubtitleFiles(this.directory);

  final Directory directory;
  final List<File> _imported = [];
  static const maxBytes = 16 * 1024 * 1024;
  static const extensions = ['srt', 'ass', 'ssa', 'vtt'];
  int _counter = 0;

  Future<File> importFile(String name, Uint8List bytes) async {
    final extension = name.split('.').last.toLowerCase();
    if (!extensions.contains(extension)) {
      throw const FormatException('请选择 SRT、ASS、SSA 或 VTT 字幕文件。');
    }
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('字幕文件为空或超过 16 MB。');
    }
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}/${DateTime.now().microsecondsSinceEpoch}-${++_counter}.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    _imported.add(file);
    return file;
  }

  Future<void> dispose() async {
    for (final file in _imported) {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        /* Retry is unnecessary for a small local subtitle copy. */
      }
    }
    _imported.clear();
  }
}
