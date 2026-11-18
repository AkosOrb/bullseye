import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'blobs.dart';

Future<Blobs> openBlobs({String? dir}) async {
  final base = dir ?? p.join((await getApplicationDocumentsDirectory()).path, 'bullseye');
  await Directory(p.join(base, 'sheets')).create(recursive: true);
  return _FileBlobs(base);
}

class _FileBlobs implements Blobs {
  _FileBlobs(this.base);
  final String base;

  // Korábbi mentésekben abszolút útvonal is lehet.
  File _f(String key) => File(p.isAbsolute(key) ? key : p.join(base, key));

  @override
  Future<String?> readText(String key) async {
    final f = _f(key);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> writeText(String key, String text) async {
    final f = _f(key);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(text);
    await tmp.rename(f.path);
  }

  @override
  Future<Uint8List?> readBytes(String key) async {
    final f = _f(key);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> writeBytes(String key, Uint8List bytes) async {
    final f = _f(key);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _f(key).delete();
    } catch (_) {}
  }
}
