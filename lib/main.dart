import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'services/app_logger.dart';
import 'services/downloader_engine.dart';
import 'services/platform_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final logger = AppLogger.instance;
  await logger.initFileLogging();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    logger.error(
      'Erro de interface do Flutter',
      error: details.exception,
      stackTrace: details.stack,
      details: details.context?.toDescription(),
    );
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    logger.error(
      'Exceção assíncrona não tratada',
      error: error,
      stackTrace: stack,
    );
    return true;
  };

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
    text: PlatformStorage.defaultDownloadDir,
  );

  final DownloaderEngine _engine = DownloaderEngine();
  final AppLogger _logger = AppLogger.instance;

  List<DownloadItem> _queue = [];
  bool _isRunning = false;
  bool _updateScheduled = false;
  int _maxConcurrency = 8;

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
      _logger.info(
        'Pasta de destino selecionada pelo usuário',
        details: selectedDirectory,
      );
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
    } catch (e, stack) {
      _logger.error(
        'Erro inesperado ao executar a fila de downloads',
        error: e,
        stackTrace: stack,
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

  void _abrirVisualizadorLogs() {
    showDialog<void>(
      context: context,
      builder: (context) => LogViewerDialog(
        logger: _logger,
        outputDirectory: _dirController.text.trim(),
      ),
    );
  }

  void _abrirSobre() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.tealAccent),
            SizedBox(width: 10),
            Text('Sobre o Aplicativo'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Baixador de Imagens',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Aplicativo multiplataforma (Desktop & Web) para download automatizado de imagens em lote.',
            ),
            const Divider(height: 24),
            const Text(
              'Desenvolvedor:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SelectableText('Gabriel Moreno (MedasDev)'),
            const SizedBox(height: 12),
            const Text(
              'Contato / Suporte:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SelectableText('gabrielmm399@gmail.com'),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copiar e-mail',
                  onPressed: () {
                    Clipboard.setData(
                      const ClipboardData(text: 'gabrielmm399@gmail.com'),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('E-mail copiado para a área de transferência.'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
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
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                'Concluídos: $concluidos / ${_queue.length}  |  Falhas: $erros',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          IconButton(
            onPressed: _abrirVisualizadorLogs,
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Visualizar Logs da Aplicação',
          ),
          IconButton(
            onPressed: _abrirSobre,
            icon: const Icon(Icons.info_outline),
            tooltip: 'Sobre o Desenvolvedor',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 750;
          final painelControle = _buildPainelControle(erros);
          final painelFila = _buildPainelFila(progressoGeral);

          if (isWide) {
            return Row(
              children: [
                Expanded(flex: 2, child: painelControle),
                const VerticalDivider(width: 1),
                Expanded(flex: 3, child: painelFila),
              ],
            );
          }

          return Column(
            children: [
              Expanded(flex: 1, child: painelControle),
              const Divider(height: 1),
              Expanded(flex: 1, child: painelFila),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPainelControle(int erros) {
    return Padding(
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
                  enabled: !_isRunning && !PlatformStorage.isWeb,
                  readOnly: PlatformStorage.isWeb,
                  decoration: InputDecoration(
                    labelText: PlatformStorage.isWeb
                        ? 'Destino no Navegador'
                        : 'Pasta de Destino',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              if (!PlatformStorage.isWeb) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _isRunning ? null : _selecionarPasta,
                  icon: const Icon(Icons.folder_open),
                  tooltip: 'Escolher pasta',
                ),
              ],
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
                      : (val) => setState(() => _maxConcurrency = val.toInt()),
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
                  onPressed: () => _iniciarDownloads(apenasErros: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar Erros'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPainelFila(double progressoGeral) {
    return Column(
      children: [
        LinearProgressIndicator(value: progressoGeral, minHeight: 6),
        Expanded(
          child: _queue.isEmpty
              ? const Center(
                  child: Text('Cole as URLs para montar a fila.'),
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
                              style: const TextStyle(color: Colors.redAccent),
                              maxLines: 1,
                            )
                          : item.status == DownloadStatus.downloading
                              ? LinearProgressIndicator(value: item.progress)
                              : null,
                      trailing: Text('#${item.index}'),
                    );
                  },
                ),
        ),
      ],
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

class LogViewerDialog extends StatefulWidget {
  final AppLogger logger;
  final String outputDirectory;

  const LogViewerDialog({
    super.key,
    required this.logger,
    required this.outputDirectory,
  });

  @override
  State<LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<LogViewerDialog> {
  LogLevel? _filtroNivel;

  Future<void> _copiarLogs() async {
    final texto = widget.logger.gerarRelatorioTexto(filtroNivel: _filtroNivel);
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs copiados para a área de transferência.'),
      ),
    );
  }

  Future<void> _exportarLogs() async {
    try {
      final destino = await widget.logger.exportarParaPasta(
        widget.outputDirectory,
        filtroNivel: _filtroNivel,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Log exportado em: $destino'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao exportar log: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Color _corNivel(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return Colors.tealAccent;
      case LogLevel.warning:
        return Colors.amberAccent;
      case LogLevel.error:
        return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 860,
        height: 540,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListenableBuilder(
            listenable: widget.logger,
            builder: (context, _) {
              final todas = widget.logger.entries;
              final filtradas = _filtroNivel == null
                  ? todas
                  : todas.where((e) => e.level == _filtroNivel).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.receipt_long),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Logs da Aplicação',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SegmentedButton<LogLevel?>(
                        segments: const [
                          ButtonSegment(value: null, label: Text('Todos')),
                          ButtonSegment(
                            value: LogLevel.error,
                            label: Text('Erros'),
                          ),
                          ButtonSegment(
                            value: LogLevel.warning,
                            label: Text('Avisos'),
                          ),
                          ButtonSegment(
                            value: LogLevel.info,
                            label: Text('Info'),
                          ),
                        ],
                        selected: {_filtroNivel},
                        onSelectionChanged: (selecao) {
                          setState(() => _filtroNivel = selecao.first);
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Fechar',
                      ),
                    ],
                  ),
                  if (widget.logger.logFilePath != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Arquivo persistente: ${widget.logger.logFilePath}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                  const Divider(height: 16),
                  Expanded(
                    child: filtradas.isEmpty
                        ? const Center(
                            child: Text('Nenhum registro encontrado.'),
                          )
                        : ListView.separated(
                            itemCount: filtradas.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              // Exibe os mais recentes no topo
                              final entry =
                                  filtradas[filtradas.length - 1 - index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6.0,
                                  horizontal: 4.0,
                                ),
                                child: SelectableText.rich(
                                  TextSpan(
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12.5,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: '[${entry.formattedTimestamp}] ',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                        ),
                                      ),
                                      TextSpan(
                                        text: '[${entry.levelLabel}] ',
                                        style: TextStyle(
                                          color: _corNivel(entry.level),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextSpan(text: entry.message),
                                      if (entry.details != null &&
                                          entry.details!.isNotEmpty)
                                        TextSpan(
                                          text: '\n  ↳ ${entry.details}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: todas.isEmpty ? null : widget.logger.limpar,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Limpar Memória'),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: filtradas.isEmpty ? null : _copiarLogs,
                        icon: const Icon(Icons.copy),
                        label: const Text('Copiar'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: filtradas.isEmpty ? null : _exportarLogs,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('Exportar .log'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}