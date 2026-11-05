import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baixadorimagens/services/platform_storage.dart';

void main() {
  test('saveImageBytes não sobrescreve arquivos existentes e gera sufixo único',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('downloader_test_');
    try {
      final bytesOriginal = [1, 2, 3, 4];
      final bytesNovo = [5, 6, 7, 8];

      // Salva o primeiro arquivo
      final nome1 = await PlatformStorage.saveImageBytes(
        outputPath: tempDir.path,
        fileName: '0001_foto.jpg',
        bytes: bytesOriginal,
      );
      expect(nome1, '0001_foto.jpg');

      final arquivo1 = File('${tempDir.path}/0001_foto.jpg');
      expect(await arquivo1.exists(), isTrue);
      expect(await arquivo1.readAsBytes(), bytesOriginal);

      // Salva o segundo arquivo com o mesmo nome pretendido
      final nome2 = await PlatformStorage.saveImageBytes(
        outputPath: tempDir.path,
        fileName: '0001_foto.jpg',
        bytes: bytesNovo,
      );
      expect(nome2, '0001_foto_1.jpg');

      // Verifica que o primeiro arquivo continua intacto (não foi excluído/sobrescrito)
      expect(await arquivo1.exists(), isTrue);
      expect(await arquivo1.readAsBytes(), bytesOriginal);

      // Verifica que o segundo arquivo foi gravado separadamente
      final arquivo2 = File('${tempDir.path}/0001_foto_1.jpg');
      expect(await arquivo2.exists(), isTrue);
      expect(await arquivo2.readAsBytes(), bytesNovo);

      // Salva um terceiro com o mesmo nome
      final nome3 = await PlatformStorage.saveImageBytes(
        outputPath: tempDir.path,
        fileName: '0001_foto.jpg',
        bytes: [9, 10],
      );
      expect(nome3, '0001_foto_2.jpg');
      expect(await File('${tempDir.path}/0001_foto_2.jpg').exists(), isTrue);
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });
}

