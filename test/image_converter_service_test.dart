import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:baixadorimagens/services/image_converter_service.dart';

void main() {
  group('ImageConverterService', () {
    late Uint8List dummyPngBytes;

    setUp(() {
      // Cria uma imagem de 10x10 pixels para testes
      final image = img.Image(width: 10, height: 10);
      img.fill(image, color: img.ColorRgb8(255, 0, 0));
      dummyPngBytes = Uint8List.fromList(img.encodePng(image));
    });

    test('Mantém os mesmos bytes se o formato for original', () async {
      final resultado = await ImageConverterService.instance.convertImageBytes(
        bytes: dummyPngBytes,
        targetFormat: ImageTargetFormat.original,
      );

      expect(resultado, dummyPngBytes);
    });

    test('Converte com sucesso para JPG', () async {
      final resultado = await ImageConverterService.instance.convertImageBytes(
        bytes: dummyPngBytes,
        targetFormat: ImageTargetFormat.jpg,
        quality: 85,
      );

      expect(resultado, isNotEmpty);
      final decoded = img.decodeJpg(resultado);
      expect(decoded, isNotNull);
      expect(decoded!.width, 10);
      expect(decoded.height, 10);
    });

    test('Converte com sucesso para WebP', () async {
      final resultado = await ImageConverterService.instance.convertImageBytes(
        bytes: dummyPngBytes,
        targetFormat: ImageTargetFormat.webp,
      );

      expect(resultado, isNotEmpty);
      final decoded = img.decodeWebP(resultado);
      expect(decoded, isNotNull);
      expect(decoded!.width, 10);
      expect(decoded.height, 10);
    });

    test('Converte com sucesso para BMP', () async {
      final resultado = await ImageConverterService.instance.convertImageBytes(
        bytes: dummyPngBytes,
        targetFormat: ImageTargetFormat.bmp,
      );

      expect(resultado, isNotEmpty);
      final decoded = img.decodeBmp(resultado);
      expect(decoded, isNotNull);
      expect(decoded!.width, 10);
      expect(decoded.height, 10);
    });

    test('Ajusta extensões de arquivos corretamente', () {
      final service = ImageConverterService.instance;

      expect(
        service.adjustFileName('foto.png', ImageTargetFormat.jpg),
        'foto.jpg',
      );
      expect(
        service.adjustFileName('imagem.webp', ImageTargetFormat.png),
        'imagem.png',
      );
      expect(
        service.adjustFileName('semextensao', ImageTargetFormat.bmp),
        'semextensao.bmp',
      );
      expect(
        service.adjustFileName('foto.jpeg', ImageTargetFormat.original),
        'foto.jpeg',
      );
    });
  });
}

