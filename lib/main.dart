import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'services/downloader_engine.dart';

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

class DownloaderScreen extends StatefulWidget {
  const DownloaderScreen({super.key});

  @override
  State<DownloaderScreen> createState() => _DownloaderScreenState();
}

class _DownloaderScreenState extends State<DownloaderScreen> {
  final TextEditingController _urlsController = TextEditingController();
  late final TextEditingController _dirController = TextEditingController(
    text: _defaultDownloadDir(),
  );

  final DownloaderEngine _engine = DownloaderEngine();

  List<DownloadItem> _queue = [];
  bool _isRunning = false;
  bool _updateScheduled = false;
  int _maxConcurrency = 8;

  static String _defaultDownloadDir() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final sep = Platform.pathSeparator;
    return '$home${sep}Downloads${sep}baixadorimagens';
  }

  @override
  void dispose() {
    _engine.cancelar();
    _urlsController.dispose();
    _dirController.dispose();
    super.dispose();
  }

  void _agendarAtualizacaoUI() {
    if (!mounted || _updateScheduled) return;
    _updateScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (mounted) {
        setState(() {});
      }
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  Future<void> _selecionarPasta() async {
    String? selectedDirectory = await FilePicker.getDirectoryPath(
      dialogTitle: 'Selecione a pasta para salvar as imagens',
    );
    if (selectedDirectory != null && mounted) {
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

    // Preserva itens já existentes na fila (ex.: downloads já concluídos ou com erro)
    final Map<String, List<DownloadItem>> existentesPorUrl = {};
    for (final item in _queue) {
      existentesPorUrl.putIfAbsent(item.url, () => []).add(item);
    }

    setState(() {
      _queue = List.generate(lines.length, (i) {
        final url = lines[i];
        final listaExistente = existentesPorUrl[url];
        if (listaExistente != null && listaExistente.isNotEmpty) {
          final antigo = listaExistente.removeAt(0);
          return DownloadItem(
            index: i + 1,
            url: url,
            status: antigo.status,
            progress: antigo.progress,
            savedFileName: antigo.savedFileName,
            errorMessage: antigo.errorMessage,
          );
        }
        return DownloadItem(index: i + 1, url: url);
      });
    });
  }

  Future<void> _iniciarDownloads({bool apenasErros = false}) async {
    if (_queue.isEmpty) {
      _carregarFila();
    }
    if (_queue.isEmpty) return;

    setState(() => _isRunning = true);

    try {
      await _engine.executarFila(
        queue: _queue,
        outputPath: _dirController.text.trim(),
        maxConcurrency: _maxConcurrency,
        apenasErros: apenasErros,
        onUpdate: (_) => _agendarAtualizacaoUI(),
      );
    } finally {
      if (mounted) {
        setState(() => _isRunning = false);
      }
    }
  }

  void _pararDownloads() {
    _engine.cancelar();
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
                      enabled: !_isRunning,
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
                          enabled: !_isRunning,
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
                              ? _pararDownloads
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