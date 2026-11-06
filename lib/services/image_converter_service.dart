import 'dart:typed_data';
import 'package:image/image.dart' as img;

enum ImageTargetFormat {
  original('Original (Sem conversão)', ''),
  jpg('JPG / JPEG (.jpg)', '.jpg', mimeType: 'image/jpeg'),
  png('PNG (.png)', '.png', mimeType: 'image/png'),
  webp('WebP (.webp)', '.webp', mimeType: 'image/webp'),
  bmp('BMP (.bmp)', '.bmp', mimeType: 'image/bmp');

  final String label;
  final String extension;
  final String mimeType;

  const ImageTargetFormat(this.label, this.extension, {this.mimeType = ''});

  bool get isOriginal => this == ImageTargetFormat.original;

  static ImageTargetFormat fromName(String? name) {
    if (name == null) return ImageTargetFormat.original;
    return ImageTargetFormat.values.firstWhere(
      (e) => e.name.toLowerCase() == name.toLowerCase(),
      orElse: () => ImageTargetFormat.original,
    );
  }
}

class ImageConverterService {
  static final ImageConverterService instance = ImageConverterService._();
  ImageConverterService._();

  /// Converte bytes de uma imagem para o formato alvo especificado.
  /// Retorna os novos bytes codificados.
  Future<Uint8List> convertImageBytes({
    required Uint8List bytes,
    required ImageTargetFormat targetFormat,
    int quality = 90,
  }) async {
    if (targetFormat.isOriginal) {
      return bytes;
    }

    if (bytes.isEmpty) {
      throw ArgumentError('Bytes da imagem estão vazios.');
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException(
        'Não foi possível decodificar o arquivo de imagem para conversão.',
      );
    }

    switch (targetFormat) {
      case ImageTargetFormat.jpg:
        return Uint8List.fromList(
          img.encodeJpg(decoded, quality: quality.clamp(1, 100)),
        );
      case ImageTargetFormat.png:
        return Uint8List.fromList(img.encodePng(decoded));
      case ImageTargetFormat.webp:
        return Uint8List.fromList(
          img.encodeWebP(decoded, quality: quality.clamp(1, 100)),
        );
      case ImageTargetFormat.bmp:
        return Uint8List.fromList(img.encodeBmp(decoded));
      case ImageTargetFormat.original:
        return bytes;
    }
  }

  /// Ajusta a extensão de um nome de arquivo para o formato desejado.
  String adjustFileName(String originalName, ImageTargetFormat targetFormat) {
    if (targetFormat.isOriginal || targetFormat.extension.isEmpty) {
      return originalName;
    }

    final dotIndex = originalName.lastIndexOf('.');
    if (dotIndex != -1) {
      final base = originalName.substring(0, dotIndex);
      return '$base${targetFormat.extension}';
    }
    return '$originalName${targetFormat.extension}';
  }
}

