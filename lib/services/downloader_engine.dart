import 'dart:convert';

import 'package:dio/dio.dart';

import 'app_logger.dart';
import 'platform_storage.dart';

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
  final AppLogger _logger;
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

  DownloaderEngine({Dio? dio, AppLogger? logger})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              followRedirects: true,
            ),
          ),
      _logger = logger ?? AppLogger.instance;

  void cancelar() {
    _isCancelled = true;
    _logger.warning('Cancelamento da fila solicitado pelo usuário.');
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

    final created = await PlatformStorage.ensureDirectory(outputPath);
    if (created) {
      _logger.info('Diretório de destino criado', details: outputPath);
    }

    final itensParaBaixar = queue.where((item) {
      if (apenasErros) return item.status == DownloadStatus.error;
      return item.status != DownloadStatus.completed;
    }).toList();

    if (itensParaBaixar.isEmpty) {
      _logger.info('Nenhum item pendente para download na fila.');
      return;
    }

    int cursor = 0;
    final workerCount = maxConcurrency.clamp(1, itensParaBaixar.length);

    _logger.info(
      'Iniciando fila de downloads',
      details:
          'Pendentes: ${itensParaBaixar.length}/${queue.length} | Concorrência: $workerCount | Destino: $outputPath | Apenas erros: $apenasErros',
    );

    Future<void> worker() async {
      while (cursor < itensParaBaixar.length && !_isCancelled) {
        final item = itensParaBaixar[cursor++];
        await _processarItem(item, outputPath, onUpdate);
      }
    }

    await Future.wait(List.generate(workerCount, (_) => worker()));

    final concluidos = queue
        .where((e) => e.status == DownloadStatus.completed)
        .length;
    final erros = queue.where((e) => e.status == DownloadStatus.error).length;
    _logger.info(
      _isCancelled
          ? 'Execução da fila interrompida'
          : 'Execução da fila finalizada',
      details: 'Concluídos: $concluidos/${queue.length} | Falhas: $erros',
    );
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

        final response = await _baixarBytesComSuporteWeb(
          item: item,
          referer: referer,
          onUpdate: onUpdate,
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
        rawName = _extrairNomeSeBase64Json(rawName);

        if (rawName.contains('.')) {
          final parts = rawName.split('.');
          if (ext.isEmpty) ext = '.${parts.last.toLowerCase()}';
          rawName = parts.sublist(0, parts.length - 1).join('_');
        }
        if (ext.isEmpty) ext = '.jpg';

        final cleanName = rawName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
        String safeName = cleanName.isEmpty ? 'img' : cleanName;
        if (safeName.length > 60) {
          safeName = safeName.substring(0, 60);
        }
        final fileName =
            '${item.index.toString().padLeft(4, '0')}_$safeName$ext';

        final savedFileName = await PlatformStorage.saveImageBytes(
          outputPath: outputPath,
          fileName: fileName,
          bytes: bytes,
        );

        item.savedFileName = savedFileName;
        item.progress = 1.0;
        item.status = DownloadStatus.completed;
        onUpdate(item);

        final tamanhoKb = (bytes.length / 1024).toStringAsFixed(1);
        _logger.info(
          'Item #${item.index} baixado com sucesso',
          details:
              'Arquivo: $savedFileName ($tamanhoKb KB) | Tipo: ${contentType.isEmpty ? "desconhecido" : contentType} | URL: ${item.url}',
        );
        return;
      } catch (e) {
        if (_isCancelled || (e is DioException && CancelToken.isCancel(e))) {
          _resetarItemCancelado(item, onUpdate);
          return;
        }

        final descricaoErro = _descreverErro(e);

        // Erros de formato de URL ou sistema de arquivos não precisam de novas tentativas de rede
        if (e is FormatException ||
            PlatformStorage.isUnrecoverableStorageError(e)) {
          item.status = DownloadStatus.error;
          item.errorMessage = descricaoErro;
          onUpdate(item);
          _logger.error(
            'Erro não recuperável no item #${item.index}',
            details: 'URL: ${item.url} | Motivo: $descricaoErro',
          );
          return;
        }

        if (tentativa < 3) {
          final esperaSegundos = tentativa * 2;
          _logger.warning(
            'Tentativa $tentativa/3 falhou no item #${item.index} (nova tentativa em ${esperaSegundos}s)',
            details: 'URL: ${item.url} | Erro: $descricaoErro',
          );
          final token = _cancelToken;
          if (token != null) {
            await Future.any([
              Future.delayed(Duration(seconds: esperaSegundos)),
              token.whenCancel.then<void>((_) {}, onError: (_) {}),
            ]);
          } else {
            await Future.delayed(Duration(seconds: esperaSegundos));
          }
        } else {
          item.status = DownloadStatus.error;
          item.errorMessage = descricaoErro;
          onUpdate(item);
          _logger.error(
            'Falha definitiva no item #${item.index} após 3 tentativas',
            details: 'URL: ${item.url} | Erro: $descricaoErro',
          );
        }
      }
    }
  }

  Future<Response<List<int>>> _baixarBytesComSuporteWeb({
    required DownloadItem item,
    required String referer,
    required void Function(DownloadItem item) onUpdate,
  }) async {
    final headers = <String, dynamic>{
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      if (!PlatformStorage.isWeb) ...{
        'User-Agent':
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36',
        'Referer': referer,
      },
    };

    try {
      return await _dio.get<List<int>>(
        item.url,
        cancelToken: _cancelToken,
        options: Options(responseType: ResponseType.bytes, headers: headers),
        onReceiveProgress: (received, total) {
          if (total > 0 && !_isCancelled) {
            item.progress = received / total;
            onUpdate(item);
          }
        },
      );
    } on DioException catch (e) {
      // Na Web, se o servidor remoto bloquear CORS diretamente no navegador,
      // tenta buscar automaticamente via proxy CORS.
      if (PlatformStorage.isWeb &&
          e.type == DioExceptionType.connectionError &&
          !CancelToken.isCancel(e)) {
        final proxyUrl =
            'https://corsproxy.io/?${Uri.encodeComponent(item.url)}';
        _logger.info(
          'Usando fallback de proxy CORS no navegador para o item #${item.index}',
          details: item.url,
        );
        return await _dio.get<List<int>>(
          proxyUrl,
          cancelToken: _cancelToken,
          options: Options(responseType: ResponseType.bytes, headers: headers),
          onReceiveProgress: (received, total) {
            if (total > 0 && !_isCancelled) {
              item.progress = received / total;
              onUpdate(item);
            }
          },
        );
      }
      rethrow;
    }
  }

  String _extrairNomeSeBase64Json(String segment) {
    if (!segment.startsWith('eyJ')) return segment;
    try {
      final normalized = base64Url.normalize(
        segment.replaceAll('-', '+').replaceAll('_', '/'),
      );
      final decoded = utf8.decode(base64.decode(normalized));
      final dynamic jsonMap = jsonDecode(decoded);
      if (jsonMap is Map && jsonMap['key'] is String) {
        final keyPath = jsonMap['key'] as String;
        final parts = keyPath.split('/');
        if (parts.isNotEmpty && parts.last.trim().isNotEmpty) {
          return parts.last.trim();
        }
      }
    } catch (_) {
      // Caso não seja um JSON Base64 válido, mantém o segmento original
    }
    return segment;
  }

  String _descreverErro(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      if (status != null) {
        return 'HTTP $status (${e.response?.statusMessage ?? e.type.name})';
      }
      return '${e.type.name}: ${e.message ?? "Falha de conexão"}';
    }
    return e.toString();
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
