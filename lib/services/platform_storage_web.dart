import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('window.navigator.userAgent')
external String get _userAgent;

@JS('Blob')
extension type _JSBlob._(JSObject _) implements JSObject {
  external factory _JSBlob(JSArray<JSAny> blobParts);
}

@JS('URL.createObjectURL')
external String _createObjectURL(JSObject blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectURL(String url);

@JS('document.createElement')
external _JSAnchorElement _createElement(String tagName);

extension type _JSAnchorElement._(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external void click();
}

class PlatformStorage {
  static bool get isWeb => true;

  static String get systemInfo => 'Web ($_userAgent)';

  static String get defaultDownloadDir => 'Downloads do Navegador';

  static Future<String?> initPersistentLogFile() async => null;

  static void appendLogLine(String filePath, String line) {}

  static Future<bool> ensureDirectory(String outputPath) async => false;

  static Future<String> saveImageBytes({
    required String outputPath,
    required String fileName,
    required List<int> bytes,
  }) async {
    _triggerBrowserDownload(fileName, Uint8List.fromList(bytes));
    return fileName;
  }

  static Future<String> exportLogFile({
    required String outputPath,
    required String fileName,
    required String content,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    _triggerBrowserDownload(fileName, bytes);
    return '$fileName (Downloads do Navegador)';
  }

  static void _triggerBrowserDownload(String fileName, Uint8List bytes) {
    final parts = <JSAny>[bytes.toJS].toJS;
    final blob = _JSBlob(parts);
    final objectUrl = _createObjectURL(blob);
    try {
      final anchor = _createElement('a');
      anchor.href = objectUrl;
      anchor.download = fileName;
      anchor.click();
    } finally {
      _revokeObjectURL(objectUrl);
    }
  }

  static bool isUnrecoverableStorageError(Object error) => false;
}

