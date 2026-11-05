export 'platform_storage_stub.dart'
    if (dart.library.io) 'platform_storage_io.dart'
    if (dart.library.js_interop) 'platform_storage_web.dart';

