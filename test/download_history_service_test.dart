import 'package:flutter_test/flutter_test.dart';
import 'package:baixadorimagens/services/download_history_service.dart';
import 'package:baixadorimagens/services/downloader_engine.dart';

void main() {
  group('DownloadHistoryService', () {
    final history = DownloadHistoryService.instance;

    setUp(() async {
      await history.limpar();
    });

    test('Registra downloads e recupera URLs com erro para re-download', () async {
      expect(history.items, isEmpty);
      expect(history.errorCount, 0);

      // Registra 1 sucesso e 2 erros
      await history.registrarOuAtualizar(
        url: 'https://exemplo.com/ok.jpg',
        status: DownloadStatus.completed,
        savedFileName: '0001_ok.jpg',
        targetFormat: 'jpg',
      );

      await history.registrarOuAtualizar(
        url: 'https://exemplo.com/falha1.jpg',
        status: DownloadStatus.error,
        errorMessage: 'HTTP 404 (Not Found)',
        targetFormat: 'png',
      );

      await history.registrarOuAtualizar(
        url: 'https://exemplo.com/falha2.jpg',
        status: DownloadStatus.error,
        errorMessage: 'Connection timed out',
        targetFormat: 'original',
      );

      expect(history.items.length, 3);
      expect(history.errorCount, 2);
      expect(history.completedCount, 1);

      final erros = history.getUrlsComErro();
      expect(erros.length, 2);
      expect(erros, contains('https://exemplo.com/falha1.jpg'));
      expect(erros, contains('https://exemplo.com/falha2.jpg'));
    });

    test('Atualiza item ao ser rebaixado com sucesso', () async {
      await history.registrarOuAtualizar(
        url: 'https://exemplo.com/foto.jpg',
        status: DownloadStatus.error,
        errorMessage: 'Timeout',
      );

      expect(history.errorCount, 1);

      // Rebaixa com sucesso
      await history.registrarOuAtualizar(
        url: 'https://exemplo.com/foto.jpg',
        status: DownloadStatus.completed,
        savedFileName: '0001_foto.jpg',
      );

      expect(history.items.length, 1);
      expect(history.errorCount, 0);
      expect(history.completedCount, 1);
      expect(history.items.first.savedFileName, '0001_foto.jpg');
    });

    test('Limpa histórico corretamente', () async {
      await history.registrarOuAtualizar(
        url: 'https://exemplo.com/a.jpg',
        status: DownloadStatus.error,
      );
      expect(history.items, isNotEmpty);

      await history.limpar();
      expect(history.items, isEmpty);
      expect(history.errorCount, 0);
    });
  });
}

