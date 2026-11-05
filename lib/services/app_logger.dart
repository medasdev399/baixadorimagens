import 'package:flutter/foundation.dart';

import 'platform_storage.dart';

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
  String? _logFilePath;
  bool _fileInitialized = false;

  List<LogEntry> get entries => List.unmodifiable(_entries);

  String? get logFilePath => _logFilePath;

  Future<void> initFileLogging() async {
    if (_fileInitialized) return;
    _fileInitialized = true;
    _logFilePath = await PlatformStorage.initPersistentLogFile();
    info(
      'Sistema de log inicializado',
      details: _logFilePath != null
          ? 'Sistema: ${PlatformStorage.systemInfo} | Arquivo: $_logFilePath'
          : 'Sistema: ${PlatformStorage.systemInfo} | Modo em memória (Web)',
    );
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

    final path = _logFilePath;
    if (path != null) {
      PlatformStorage.appendLogLine(path, entry.format());
    }
    notifyListeners();
  }

  void limpar() {
    _entries.clear();
    notifyListeners();
  }

  String gerarRelatorioTexto({LogLevel? filtroNivel}) {
    final buffer = StringBuffer();
    buffer.writeln('=== RELATÓRIO DE LOGS - BAIXADOR DE IMAGENS ===');
    buffer.writeln('Desenvolvedor: Gabriel Moreno (MedasDev) <gabrielmm399@gmail.com>');
    buffer.writeln('Gerado em: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Sistema: ${PlatformStorage.systemInfo}');
    if (_logFilePath != null) {
      buffer.writeln('Arquivo de log: $_logFilePath');
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

  Future<String> exportarParaPasta(
    String directoryPath, {
    LogLevel? filtroNivel,
  }) async {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final fileName = 'baixadorimagens_log_$stamp.log';
    return PlatformStorage.exportLogFile(
      outputPath: directoryPath,
      fileName: fileName,
      content: gerarRelatorioTexto(filtroNivel: filtroNivel),
    );
  }
}

