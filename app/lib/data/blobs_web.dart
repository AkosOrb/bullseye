import 'dart:convert';
import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

import 'blobs.dart';

const _storeName = 'kv';

Future<Blobs> openBlobs({String? dir}) async {
  final db = await idbFactoryBrowser.open('bullseye', version: 1, onUpgradeNeeded: (e) {
    final db = e.database;
    if (!db.objectStoreNames.contains(_storeName)) db.createObjectStore(_storeName);
  });
  return _IdbBlobs(db);
}

/// Minden érték szövegként (a bájtok base64-ben) kerül az IndexedDB-be,
/// így böngészőtől függetlenül megbízhatóan visszaolvasható.
class _IdbBlobs implements Blobs {
  _IdbBlobs(this.db);
  final Database db;

  Future<Object?> _get(String key) async {
    final tx = db.transaction(_storeName, idbModeReadOnly);
    final v = await tx.objectStore(_storeName).getObject(key);
    await tx.completed;
    return v;
  }

  Future<void> _put(String key, String value) async {
    final tx = db.transaction(_storeName, idbModeReadWrite);
    await tx.objectStore(_storeName).put(value, key);
    await tx.completed;
  }

  @override
  Future<String?> readText(String key) async => (await _get(key)) as String?;

  @override
  Future<void> writeText(String key, String text) => _put(key, text);

  @override
  Future<Uint8List?> readBytes(String key) async {
    final v = await _get(key);
    return v == null ? null : base64Decode(v as String);
  }

  @override
  Future<void> writeBytes(String key, Uint8List bytes) => _put(key, base64Encode(bytes));

  @override
  Future<void> delete(String key) async {
    final tx = db.transaction(_storeName, idbModeReadWrite);
    await tx.objectStore(_storeName).delete(key);
    await tx.completed;
  }
}
