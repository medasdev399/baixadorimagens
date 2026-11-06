import 'dart:io';

class PlatformStorage {
  static bool get isWeb => false;

  static String get systemInfo =>
      '${Platform.operatingSystem} (${Platform.operatingSystemVersion})';

  static String get defaultDownloadDir {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final sep = Platform.pathSeparator;
    return '$home${sep}Downloads${sep}baixadorimagens';
  }

  static Future<String?> initPersistentLogFile() async {
    try {
      final sep = Platform.pathSeparator;
      final String basePath;
      if (Platform.isWindows) {
        final localAppData = Platform.environment['LOCALAPPDATA'] ??
            Platform.environment['USERPROFILE'] ??
            '.';
        basePath = '$localAppData${sep}baixadorimagens${sep}logs';
      } else {
        final home = Platform.environment['HOME'] ?? '.';
        basePath = '$home$sep.local${sep}share${sep}baixadorimagens${sep}logs';
      }

      final logDir = Directory(basePath);
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      return '${logDir.path}${sep}app.log';
    } catch (_) {
      return null;
    }
  }

  static void appendLogLine(String filePath, String line) {
    try {
      File(filePath).writeAsStringSync(
        '$line\n',
        mode: FileMode.append,
        flush: false,
      );
    } catch (_) {
      // Ignora falhas de I/O secundárias para não afetar o fluxo principal
    }
  }

  static Future<bool> ensureDirectory(String outputPath) async {
    final dir = Directory(outputPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      return true;
    }
    return false;
  }

  static final Set<String> _pendingFilePaths = {};

  static Future<String> saveImageBytes({
    required String outputPath,
    required String fileName,
    required List<int> bytes,
  }) async {
    final sep = Platform.pathSeparator;
    final dotIndex = fileName.lastIndexOf('.');
    final baseName =
        dotIndex != -1 ? fileName.substring(0, dotIndex) : fileName;
    final ext = dotIndex != -1 ? fileName.substring(dotIndex) : '';

    String candidateName = fileName;
    String fullPath = '$outputPath$sep$candidateName';
    int counter = 1;

    while (await File(fullPath).exists() ||
        _pendingFilePaths.contains(fullPath)) {
      candidateName = '${baseName}_$counter$ext';
      fullPath = '$outputPath$sep$candidateName';
      counter++;
    }

    _pendingFilePaths.add(fullPath);
    try {
      final file = File(fullPath);
      await file.writeAsBytes(bytes, flush: true);
      return candidateName;
    } finally {
      _pendingFilePaths.remove(fullPath);
    }
  }

  static Future<String> exportLogFile({
    required String outputPath,
    required String fileName,
    required String content,
  }) async {
    final dir = Directory(outputPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final sep = Platform.pathSeparator;
    final file = File('${dir.path}$sep$fileName');
    await file.writeAsString(content);
    return file.path;
  }

  static bool isUnrecoverableStorageError(Object error) =>
      error is FileSystemException;

  static String _getHistoryFilePath() {
    final sep = Platform.pathSeparator;
    final String basePath;
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['USERPROFILE'] ??
          '.';
      basePath = '$localAppData${sep}baixadorimagens';
    } else {
      final home = Platform.environment['HOME'] ?? '.';
      basePath = '$home$sep.local${sep}share${sep}baixadorimagens';
    }
    return '$basePath${sep}download_history.json';
  }

  static Future<String?> loadHistoryJson() async {
    try {
      final file = File(_getHistoryFilePath());
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (_) {
      // Ignora erro de leitura inicial
    }
    return null;
  }

  static Future<void> saveHistoryJson(String jsonString) async {
    try {
      final filePath = _getHistoryFilePath();
      final file = File(filePath);
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      await file.writeAsString(jsonString, flush: true);
    } catch (_) {
      // Ignora falha de salvamento secundária
    }
  }
}

