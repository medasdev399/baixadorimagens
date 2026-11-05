import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const BaixadorImagensApp());
}

class BaixadorImagensApp extends StatelessWidget {
  const BaixadorImagensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Baixador de Imagens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.tealAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const DownloaderScreen(),
    );
  }
}

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

class DownloaderScreen extends StatefulWidget {
  const DownloaderScreen({super.key});

  @override
  State<DownloaderScreen> createState() => _DownloaderScreenState();
}

class _DownloaderScreenState extends State<DownloaderScreen> {
  final TextEditingController _urlsController = TextEditingController();
  final TextEditingController _dirController = TextEditingController(
    text: '${Platform.environment['HOME'] ?? '.'}/Downloads/baixadorimagens',
  );

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
    ),
  );

  List<DownloadItem> _queue = [];
  bool _isRunning = false;
  int _maxConcurrency = 8;

  static const Map<String, String> _mimeToExt = {
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/webp': '.webp',
    'image/gif': '.gif',
    'image/svg+xml': '.svg',
    'image/avif': '.avif',
  };

  Future<void> _selecionarPasta() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Selecione a pasta para salvar as imagens',
    );
    if (selectedDirectory != null) {
      setState(() {
        _dirController.text = selectedDirectory;
      });
    }
  }

  void _carregarFila() {
    final lines = _urlsController.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e.startsWith('http'))
        .toList();

    setState(() {
      _queue = List.generate(
        lines.length,
        (i) => DownloadItem(index: i + 1, url: lines[i]),
      );
    });
  }

  Future<void> _iniciarDownloads({bool apenasErros = false}) async {
    if (_queue.isEmpty) {
      _carregarFila();
    }
    if (_queue.isEmpty) return;

    final dir = Directory(_dirController.text.trim());
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    setState(() => _isRunning = true);

    final itensParaBaixar = _queue.where((item) {
      if (apenasErros) return item.status == DownloadStatus.error;
      return item.status != DownloadStatus.completed;
    }).toList();

    int cursor = 0;

    Future<void> worker() async {
      while (cursor < itensParaBaixar.length && _isRunning) {
        final item = itensParaBaixar[cursor++];
        await _processarItem(item, dir.path);
      }
    }

    await Future.wait(
      List.generate(_maxConcurrency, (_) => worker()),
    );

    if (mounted) {
      setState(() => _isRunning = false);
    }
  }

  Future<void> _processarItem(DownloadItem item, String outputPath) async {
    setState(() {
      item.status = DownloadStatus.downloading;
      item.progress = 0.0;
      item.errorMessage = null;
    });

    final uri = Uri.parse(item.url);
    final referer = '${uri.scheme}://${uri.host}/';

    for (int tentativa = 1; tentativa <= 3; tentativa++) {
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
            if (total != -1 && mounted) {
              setState(() {
                item.progress = received / total;
              });
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
        String ext = _mimeToExt[contentType] ?? '';

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

        if (mounted) {
          setState(() {
            item.savedFileName = fileName;
            item.progress = 1.0;
            item.status = DownloadStatus.completed;
          });
        }
        return;
      } catch (e) {
        if (tentativa < 3) {
          await Future.delayed(Duration(seconds: tentativa * 2));
        } else {
          if (mounted) {
            setState(() {
              item.status = DownloadStatus.error;
              item.errorMessage = e.toString();
            });
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final concluidos =
        _queue.where((e) => e.status == DownloadStatus.completed).length;
    final erros = _queue.where((e) => e.status == DownloadStatus.error).length;
    final progressoGeral = _queue.isEmpty ? 0.0 : concluidos / _queue.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Baixador de Imagens'),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                'Concluídos: $concluidos / ${_queue.length}  |  Falhas: $erros',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Lista de URLs (uma por linha):',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TextField(
                      controller: _urlsController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText:
                            'https://site1.com/foto.jpg\nhttps://site2.com/imagem.png',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        if (!_isRunning) _carregarFila();
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _dirController,
                          decoration: const InputDecoration(
                            labelText: 'Pasta de Destino',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: _isRunning ? null : _selecionarPasta,
                        icon: const Icon(Icons.folder_open),
                        tooltip: 'Escolher pasta',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Downloads simultâneos:'),
                      Expanded(
                        child: Slider(
                          value: _maxConcurrency.toDouble(),
                          min: 1,
                          max: 20,
                          divisions: 19,
                          label: '$_maxConcurrency',
                          onChanged: _isRunning
                              ? null
                              : (val) =>
                                  setState(() => _maxConcurrency = val.toInt()),
                        ),
                      ),
                      Text('$_maxConcurrency'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isRunning
                              ? () => setState(() => _isRunning = false)
                              : () => _iniciarDownloads(),
                          icon: Icon(_isRunning ? Icons.stop : Icons.download),
                          label: Text(_isRunning ? 'Parar' : 'Baixar Tudo'),
                        ),
                      ),
                      if (erros > 0 && !_isRunning) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _iniciarDownloads(apenasErros: true),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar Erros'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            flex: 3,
            child: Column(
              children: [
                LinearProgressIndicator(value: progressoGeral, minHeight: 6),
                Expanded(
                  child: _queue.isEmpty
                      ? const Center(
                          child:
                              Text('Cole as URLs ao lado para montar a fila.'),
                        )
                      : ListView.separated(
                          itemCount: _queue.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = _queue[index];
                            return ListTile(
                              dense: true,
                              leading: _buildStatusIcon(item.status),
                              title: Text(
                                item.savedFileName ?? item.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: item.status == DownloadStatus.error
                                  ? Text(
                                      item.errorMessage ?? 'Erro desconhecido',
                                      style: const TextStyle(
                                          color: Colors.redAccent),
                                      maxLines: 1,
                                    )
                                  : item.status == DownloadStatus.downloading
                                      ? LinearProgressIndicator(
                                          value: item.progress)
                                      : null,
                              trailing: Text('#${item.index}'),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.idle:
        return const Icon(Icons.schedule, color: Colors.grey);
      case DownloadStatus.downloading:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case DownloadStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.tealAccent);
      case DownloadStatus.error:
        return const Icon(Icons.error_outline, color: Colors.redAccent);
    }
  }
}