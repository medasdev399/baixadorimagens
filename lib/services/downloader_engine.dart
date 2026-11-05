import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';

enum DownloadStatus { idle, downloading, completed, error }

class DownloadItem {
  final int index;
  final String url;
  DownloadStatus status;
  double progress;
  String? savedFileName;
  String? errorMessage;

  DownloadItem({
    required this.index,
    required this.url,
    this.status = DownloadStatus.idle,
    this.progress = 0.0,
  });
}

class DownloaderEngine {
  final Dio _dio;
  bool _isCancelled = false;

  static const Map<String, String> mimeToExt = {
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/webp': '.webp',
    'image/gif': '.gif',
    'image/svg+xml': '.svg',
    'image/avif': '.avif',
  };

  DownloaderEngine()
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            followRedirects: true,
          ),
        );

  void cancelar() {
    _isCancelled = true;
  }

  Future<void> executarFila({
    required List<DownloadItem> queue,
    required String outputPath,
    required int maxConcurrency,
    required Function(DownloadItem item) onUpdate,
    bool apenasErros = false,
  }) async {
    _isCancelled = false;
    final dir = Directory(outputPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final itensParaBaixar = queue.where((item) {
      if (apenasErros) return item.status == DownloadStatus.error;
      return item.status != DownloadStatus.completed;
    }).toList();

    int cursor = 0;

    Future<void> worker() async {
      while (cursor < itensParaBaixar.length && !_isCancelled) {
        final item = itensParaBaixar[cursor++];
        await _processarItem(item, dir.path, onUpdate);
      }
    }

    await Future.wait(
      List.generate(maxConcurrency, (_) => worker()),
    );
  }

  Future<void> _processarItem(
    DownloadItem item,
    String outputPath,
    Function(DownloadItem item) onUpdate,
  ) async {
    item.status = DownloadStatus.downloading;
    item.progress = 0.0;
    item.errorMessage = null;
    onUpdate(item);

    final uri = Uri.parse(item.url);
    final referer = '${uri.scheme}://${uri.host}/';

    for (int tentativa = 1; tentativa <= 3; tentativa++) {
      if (_isCancelled) return;
      try {
        final response = await _dio.get<List<int>>(
          item.url,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36',
              'Referer': referer,
              'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
            },
          ),
          onReceiveProgress: (received, total) {
            if (total != -1) {
              item.progress = received / total;
              onUpdate(item);
            }
          },
        );

        final bytes = Uint8List.fromList(response.data!);

        final contentType = response.headers
                .value('content-type')
                ?.split(';')
                .first
                .trim()
                .toLowerCase() ??
            '';
        String ext = mimeToExt[contentType] ?? '';

        String rawName =
            uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'img';
        if (rawName.contains('.')) {
          final parts = rawName.split('.');
          if (ext.isEmpty) ext = '.${parts.last}';
          rawName = parts.sublist(0, parts.length - 1).join('_');
        }
        if (ext.isEmpty) ext = '.jpg';

        final cleanName = rawName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
        final safeName = cleanName.isEmpty ? 'img' : cleanName;
        final fileName =
            '${item.index.toString().padLeft(4, '0')}_$safeName$ext';

        final file = File('$outputPath/$fileName');
        await file.writeAsBytes(bytes);

        item.savedFileName = fileName;
        item.progress = 1.0;
        item.status = DownloadStatus.completed;
        onUpdate(item);
        return;
      } catch (e) {
        if (tentativa < 3) {
          await Future.delayed(Duration(seconds: tentativa * 2));
        } else {
          item.status = DownloadStatus.error;
          item.errorMessage = e.toString();
          onUpdate(item);
        }
      }
    }
  }
}