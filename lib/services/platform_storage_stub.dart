class PlatformStorage {
  static bool get isWeb => false;

  static String get systemInfo => 'Unknown Platform';

  static String get defaultDownloadDir => './Downloads/baixadorimagens';

  static Future<String?> initPersistentLogFile() async => null;

  static void appendLogLine(String filePath, String line) {}

  static Future<bool> ensureDirectory(String outputPath) async => false;

  static Future<String> saveImageBytes({
    required String outputPath,
    required String fileName,
    required List<int> bytes,
  }) async {
    throw UnsupportedError('Plataforma não suportada.');
  }

  static Future<String> exportLogFile({
    required String outputPath,
    required String fileName,
    required String content,
  }) async {
    throw UnsupportedError('Plataforma não suportada.');
  }

  static bool isUnrecoverableStorageError(Object error) => false;
}

