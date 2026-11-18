// Platformfüggetlen tároló: szöveg (JSON) és bájtok (lapfotók) kulcs szerint.
// Telefonon fájlok az app mappájában, böngészőben IndexedDB.
import 'dart:typed_data';

import 'blobs_io.dart' if (dart.library.js_interop) 'blobs_web.dart' as impl;

abstract class Blobs {
  Future<String?> readText(String key);
  Future<void> writeText(String key, String text);
  Future<Uint8List?> readBytes(String key);
  Future<void> writeBytes(String key, Uint8List bytes);
  Future<void> delete(String key);
}

/// [dir]: csak teszthez/telefonon, a tároló mappája.
Future<Blobs> openBlobs({String? dir}) => impl.openBlobs(dir: dir);
