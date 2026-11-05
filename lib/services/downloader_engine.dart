import 'dart:io';

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
    this.savedFileName,
    this.errorMessage,
  });
}

class DownloaderEngine {
  final Dio _dio;
  bool _isCancelled = false;
  CancelToken? _cancelToken;

  static const Map<String, String> mimeToExt = {
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/webp': '.webp',
    'image/gif': '.gif',
    'image/svg+xml': '.svg',
    'image/avif': '.avif',
  };

  DownloaderEngine({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              followRedirects: true,
            ),
          );

  void cancelar() {
    _isCancelled = true;
    final token = _cancelToken;
    if (token != null && !token.isCancelled) {
      token.cancel('Download cancelado pelo usuário.');
    }
  }

  Future<void> executarFila({
    required List<DownloadItem> queue,
    required String outputPath,
    required int maxConcurrency,
    required void Function(DownloadItem item) onUpdate,
    bool apenasErros = false,
  }) async {
    _isCancelled = false;
    _cancelToken = CancelToken();

    final dir = Directory(outputPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final itensParaBaixar = queue.where((item) {
      if (apenasErros) return item.status == DownloadStatus.error;
      return item.status != DownloadStatus.completed;
    }).toList();

    if (itensParaBaixar.isEmpty) return;

    int cursor = 0;
    final workerCount = maxConcurrency.clamp(1, itensParaBaixar.length);

    Future<void> worker() async {
      while (cursor < itensParaBaixar.length && !_isCancelled) {
        final item = itensParaBaixar[cursor++];
        await _processarItem(item, dir.path, onUpdate);
      }
    }

    await Future.wait(List.generate(workerCount, (_) => worker()));
  }

  Future<void> _processarItem(
    DownloadItem item,
    String outputPath,
    void Function(DownloadItem item) onUpdate,
  ) async {
    if (_isCancelled) return;

    item.status = DownloadStatus.downloading;
    item.progress = 0.0;
    item.errorMessage = null;
    onUpdate(item);

    for (int tentativa = 1; tentativa <= 3; tentativa++) {
      if (_isCancelled) {
        _resetarItemCancelado(item, onUpdate);
        return;
      }

      try {
        final uri = Uri.tryParse(item.url);
        if (uri == null ||
            !uri.hasScheme ||
            (uri.scheme != 'http' && uri.scheme != 'https') ||
            uri.host.isEmpty) {
          throw FormatException('URL inválida: ${item.url}');
        }

        final referer = '${uri.scheme}://${uri.host}/';

        final response = await _dio.get<List<int>>(
          item.url,
          cancelToken: _cancelToken,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {
              'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36',
              'Referer': referer,
              'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
            },
          ),
          onReceiveProgress: (received, total) {
            if (total > 0 && !_isCancelled) {
              item.progress = received / total;
              onUpdate(item);
            }
          },
        );

        if (_isCancelled) {
          _resetarItemCancelado(item, onUpdate);
          return;
        }

        final bytes = response.data;
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Resposta vazia recebida do servidor.');
        }

        final contentType =
            response.headers
                .value('content-type')
                ?.split(';')
                .first
                .trim()
                .toLowerCase() ??
            '';
        String ext = mimeToExt[contentType] ?? '';

        String rawName = uri.pathSegments.isNotEmpty
            ? uri.pathSegments.last
            : 'img';
        if (rawName.contains('.')) {
          final parts = rawName.split('.');
          if (ext.isEmpty) ext = '.${parts.last.toLowerCase()}';
          rawName = parts.sublist(0, parts.length - 1).join('_');
        }
        if (ext.isEmpty) ext = '.jpg';

        final cleanName = rawName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
        final safeName = cleanName.isEmpty ? 'img' : cleanName;
        final fileName =
            '${item.index.toString().padLeft(4, '0')}_$safeName$ext';

        final file = File('$outputPath${Platform.pathSeparator}$fileName');
        await file.writeAsBytes(bytes);

        item.savedFileName = fileName;
        item.progress = 1.0;
        item.status = DownloadStatus.completed;
        onUpdate(item);
        return;
      } catch (e) {
        if (_isCancelled || (e is DioException && CancelToken.isCancel(e))) {
          _resetarItemCancelado(item, onUpdate);
          return;
        }

        // Erros de formato de URL não precisam de novas tentativas
        if (e is FormatException) {
          item.status = DownloadStatus.error;
          item.errorMessage = e.message;
          onUpdate(item);
          return;
        }

        if (tentativa < 3) {
          final token = _cancelToken;
          if (token != null) {
            await Future.any([
              Future.delayed(Duration(seconds: tentativa * 2)),
              // ignore: invalid_return_type_for_catch_error
              token.whenCancel.catchError(
                (_) => Response(requestOptions: RequestOptions()),
              ),
            ]);
          } else {
            await Future.delayed(Duration(seconds: tentativa * 2));
          }
        } else {
          item.status = DownloadStatus.error;
          item.errorMessage = e.toString();
          onUpdate(item);
        }
      }
    }
  }

  void _resetarItemCancelado(
    DownloadItem item,
    void Function(DownloadItem item) onUpdate,
  ) {
    item.status = DownloadStatus.idle;
    item.progress = 0.0;
    item.errorMessage = null;
    onUpdate(item);
  }
}
