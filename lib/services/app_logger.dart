import 'dart:io';
import 'package:flutter/foundation.dart';

enum LogLevel { info, warning, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? details;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.details,
  });

  String get levelLabel {
    switch (level) {
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
    }
  }

  String get formattedTimestamp {
    final y = timestamp.year.toString().padLeft(4, '0');
    final m = timestamp.month.toString().padLeft(2, '0');
    final d = timestamp.day.toString().padLeft(2, '0');
    final h = timestamp.hour.toString().padLeft(2, '0');
    final min = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$y-$m-$d $h:$min:$s.$ms';
  }

  String format() {
    final base = '[$formattedTimestamp] [$levelLabel] $message';
    if (details != null && details!.trim().isNotEmpty) {
      return '$base | Detalhes: ${details!.replaceAll('\n', ' ')}';
    }
    return base;
  }
}

class AppLogger extends ChangeNotifier {
  static final AppLogger instance = AppLogger._internal();

  AppLogger._internal();

  static const int _maxEntries = 2000;
  final List<LogEntry> _entries = [];
  File? _logFile;
  bool _fileInitialized = false;

  List<LogEntry> get entries => List.unmodifiable(_entries);

  String? get logFilePath => _logFile?.path;

  Future<void> initFileLogging() async {
    if (_fileInitialized) return;
    _fileInitialized = true;
    try {
      final logDir = Directory(_defaultLogDirPath());
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      final sep = Platform.pathSeparator;
      _logFile = File('${logDir.path}${sep}app.log');
      info(
        'Sistema de log inicializado',
        details:
            'OS: ${Platform.operatingSystem} (${Platform.operatingSystemVersion}) | Arquivo: ${_logFile!.path}',
      );
    } catch (_) {
      // Se não for possível criar o arquivo (ex.: ambiente de teste restrito),
      // mantém os logs funcionando em memória sem interromper o aplicativo.
      _logFile = null;
    }
  }

  static String _defaultLogDirPath() {
    final sep = Platform.pathSeparator;
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['USERPROFILE'] ??
          '.';
      return '$localAppData${sep}baixadorimagens${sep}logs';
    }
    final home = Platform.environment['HOME'] ?? '.';
    return '$home$sep.local${sep}share${sep}baixadorimagens${sep}logs';
  }

  void info(String message, {String? details}) {
    _add(LogLevel.info, message, details: details);
  }

  void warning(String message, {String? details}) {
    _add(LogLevel.warning, message, details: details);
  }

  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? details,
  }) {
    final buffer = StringBuffer();
    if (details != null && details.isNotEmpty) {
      buffer.write(details);
    }
    if (error != null) {
      if (buffer.isNotEmpty) buffer.write(' | ');
      buffer.write('Exceção: $error');
    }
    if (stackTrace != null) {
      if (buffer.isNotEmpty) buffer.write(' | ');
      buffer.write('StackTrace: $stackTrace');
    }
    _add(
      LogLevel.error,
      message,
      details: buffer.isEmpty ? null : buffer.toString(),
    );
  }

  void _add(LogLevel level, String message, {String? details}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      details: details,
    );

    if (_entries.length >= _maxEntries) {
      _entries.removeAt(0);
    }
    _entries.add(entry);

    _gravarEmArquivoAsync(entry);
    notifyListeners();
  }

  void _gravarEmArquivoAsync(LogEntry entry) {
    final file = _logFile;
    if (file == null) return;
    try {
      file.writeAsStringSync(
        '${entry.format()}\n',
        mode: FileMode.append,
        flush: false,
      );
    } catch (_) {
      // Ignora falhas de I/O secundárias para não afetar o fluxo principal
    }
  }

  void limpar() {
    _entries.clear();
    notifyListeners();
  }

  String gerarRelatorioTexto({LogLevel? filtroNivel}) {
    final buffer = StringBuffer();
    buffer.writeln('=== RELATÓRIO DE LOGS - BAIXADOR DE IMAGENS ===');
    buffer.writeln('Gerado em: ${DateTime.now().toIso8601String()}');
    buffer.writeln(
      'Sistema: ${Platform.operatingSystem} - ${Platform.operatingSystemVersion}',
    );
    if (_logFile != null) {
      buffer.writeln('Arquivo de log: ${_logFile!.path}');
    }
    buffer.writeln('===============================================');
    buffer.writeln();

    final lista = filtroNivel == null
        ? _entries
        : _entries.where((e) => e.level == filtroNivel);

    for (final entry in lista) {
      buffer.writeln(entry.format());
    }
    return buffer.toString();
  }

  Future<File> exportarParaPasta(
    String directoryPath, {
    LogLevel? filtroNivel,
  }) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final sep = Platform.pathSeparator;
    final file = File('${dir.path}${sep}baixadorimagens_log_$stamp.log');
    await file.writeAsString(gerarRelatorioTexto(filtroNivel: filtroNivel));
    return file;
  }
}

