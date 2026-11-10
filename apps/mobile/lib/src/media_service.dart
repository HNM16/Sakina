import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'api_client.dart';

/// Choosing, uploading and caching attachments.
///
/// The upload is three steps and the order is the point: ask the server where
/// to put it, PUT the bytes straight to storage, then send a message carrying
/// the key. The bytes never pass through the API, so a 40MB video on a slow
/// uplink does not occupy a request for two minutes.
///
/// Downloads are cached on disk by key, forever. Object keys are immutable —
/// the same key always names the same bytes — so there is no invalidation
/// problem, and on Tajik mobile data re-downloading a photo because someone
/// scrolled past it twice is real money.
class MediaService {
  MediaService(this._api);

  final ApiClient _api;
  final _picker = ImagePicker();
  Directory? _cacheDir;

  /// Anything larger than this gets a "you are on mobile data" confirmation
  /// before it is sent. Deliberately low: `docs/UX.md` notes that data costs
  /// real money in this market, and a silent 30MB upload is a bill.
  static const int confirmAboveBytes = 5 * 1024 * 1024;

  /// Mirrors the server's allowlist in `packages/core/src/media.ts`. Kept in
  /// step by hand, like the rest of the protocol mirror — the server is the
  /// authority and will refuse anything this gets wrong, so the cost of drift
  /// is a clear error rather than a bad upload.
  static const _mimeByExtension = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'avif': 'image/avif',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
    '3gp': 'video/3gpp',
    'mkv': 'video/x-matroska',
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'zip': 'application/zip',
    'txt': 'text/plain',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'ogg': 'audio/ogg',
  };

  static String mimeFor(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    return _mimeByExtension[ext] ?? 'application/octet-stream';
  }

  // -------------------------------------------------------------------------
  // Choosing
  // -------------------------------------------------------------------------

  Future<PickedMedia?> pickImage({required bool fromCamera}) async {
    final file = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      // Downscaled on the way in rather than on the way out. The target device
      // is a cheap Android and the target network is metered; a 12MP original
      // helps nobody at the size it will be looked at.
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 82,
    );
    return file == null ? null : _describe(File(file.path), file.name);
  }

  Future<PickedMedia?> pickVideo({required bool fromCamera}) async {
    final file = await _picker.pickVideo(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxDuration: const Duration(minutes: 3),
    );
    return file == null ? null : _describe(File(file.path), file.name);
  }

  Future<PickedMedia?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(withReadStream: false);
    final picked = result?.files.singleOrNull;
    final path = picked?.path;
    if (picked == null || path == null) return null;
    return _describe(File(path), picked.name);
  }

  Future<PickedMedia> _describe(File file, String name) async {
    return PickedMedia(
      file: file,
      name: name,
      mime: mimeFor(name),
      size: await file.length(),
    );
  }

  // -------------------------------------------------------------------------
  // Uploading
  // -------------------------------------------------------------------------

  /// Uploads the bytes and returns the message payload to send.
  ///
  /// Throws [ApiException] if the server refuses the type or the size — which
  /// it does before any bytes move, so a refusal costs one small request rather
  /// than an upload.
  Future<Map<String, dynamic>> upload({
    required String chatId,
    required PickedMedia media,
    String? caption,
    void Function(double progress)? onProgress,
  }) async {
    final ticket = await _api.requestUpload(
      chatId: chatId,
      name: media.name,
      mime: media.mime,
      size: media.size,
    );

    onProgress?.call(0);
    final bytes = await media.file.readAsBytes();

    final response = await http.put(
      Uri.parse(ticket.url),
      headers: ticket.headers,
      body: bytes,
    );
    if (response.statusCode >= 400) {
      throw ApiException('upload_failed', 'storage rejected the upload (${response.statusCode})');
    }
    onProgress?.call(1);

    return <String, dynamic>{
      'type': 'media',
      // The server's classification, not ours.
      'kind': ticket.kind,
      'key': ticket.key,
      'mime': media.mime,
      'size': media.size,
      // Only meaningful for documents, but harmless to carry: it is what the
      // recipient sees in the bubble and what the file is saved as.
      'name': media.name,
      if (caption != null && caption.isNotEmpty) 'caption': caption,
    };
  }

  // -------------------------------------------------------------------------
  // Reading back
  // -------------------------------------------------------------------------

  Future<Directory> _cache() async {
    final existing = _cacheDir;
    if (existing != null) return existing;
    final base = await getApplicationCacheDirectory();
    final dir = Directory(p.join(base.path, 'media'));
    await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  /// The local file for a key, downloading it once if it is not already there.
  ///
  /// The cache filename is derived from the key with the slashes flattened, so
  /// two chats cannot collide and nothing escapes the cache directory.
  Future<File> localFile({required String chatId, required String key}) async {
    final dir = await _cache();
    final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File(p.join(dir.path, safe));

    if (await file.exists() && await file.length() > 0) return file;

    final url = await _api.mediaUrl(chatId: chatId, key: key);
    final response = await http.get(Uri.parse(url));
    if (response.statusCode >= 400) {
      throw ApiException('download_failed', 'could not fetch attachment (${response.statusCode})');
    }

    // Written to a temporary name and renamed, so a download interrupted
    // half-way cannot leave a truncated file that looks complete on the next
    // open. Rename is atomic within a directory.
    final temp = File('${file.path}.part');
    await temp.writeAsBytes(response.bodyBytes);
    await temp.rename(file.path);
    return file;
  }

  /// Whether a key is already on disk. Used to decide between showing an image
  /// straight away and showing a placeholder while it downloads.
  Future<bool> isCached(String key) async {
    final dir = await _cache();
    final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File(p.join(dir.path, safe));
    return await file.exists() && await file.length() > 0;
  }
}

@immutable
class PickedMedia {
  const PickedMedia({
    required this.file,
    required this.name,
    required this.mime,
    required this.size,
  });

  final File file;
  final String name;
  final String mime;
  final int size;

  bool get isLarge => size > MediaService.confirmAboveBytes;

  String get humanSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).round()} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

extension _SingleOrNull<T> on List<T> {
  /// `singleOrNull` lives in package:collection, which is not a dependency —
  /// and adding a package for one getter is not the trade this project makes.
  T? get singleOrNull => length == 1 ? this[0] : null;
}
