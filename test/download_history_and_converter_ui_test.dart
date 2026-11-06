import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baixadorimagens/main.dart';
import 'package:baixadorimagens/services/download_history_service.dart';
import 'package:baixadorimagens/services/downloader_engine.dart';
import 'package:baixadorimagens/services/image_converter_service.dart';
import 'package:baixadorimagens/widgets/download_history_dialog.dart';

void main() {
  testWidgets('Testa seletor de formato de imagem e abertura dos diálogos',
      (WidgetTester tester) async {
    final history = DownloadHistoryService.instance;
    await history.limpar();

    // Adiciona um link com erro prévio no histórico
    await history.registrarOuAtualizar(
      url: 'https://exemplo.com/erro.png',
      status: DownloadStatus.error,
      errorMessage: 'HTTP 500',
    );

    await tester.pumpWidget(const BaixadorImagensApp());
    await tester.pumpAndSettle();

    // Verifica que o seletor de formato de download está presente
    expect(find.text('Tipo de Imagem para Download'), findsOneWidget);
    expect(find.text('Original (Sem conversão)'), findsOneWidget);

    // Altera o tipo de imagem para JPG
    await tester.tap(find.text('Original (Sem conversão)'));
    await tester.pumpAndSettle();

    expect(find.text(ImageTargetFormat.jpg.label), findsWidgets);
    await tester.tap(find.text(ImageTargetFormat.jpg.label).last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Conversão automática ativada: salvará em JPG'),
      findsOneWidget,
    );

    // Abre o Histórico de Links através da AppBar
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    expect(find.text('Histórico de Links e Downloads'), findsOneWidget);
    expect(find.text('https://exemplo.com/erro.png'), findsOneWidget);
    expect(find.text('Rebaixar Todos os Erros'), findsOneWidget);

    // Fecha o Histórico
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Histórico de Links e Downloads'), findsNothing);

    // Abre o Conversor de Imagens Dedicado através da AppBar
    await tester.tap(find.byIcon(Icons.transform));
    await tester.pumpAndSettle();

    expect(find.text('Conversor de Imagens'), findsOneWidget);
    expect(find.text('Selecionar Imagens'), findsOneWidget);

    // Fecha o Conversor de Imagens
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Conversor de Imagens'), findsNothing);
  });

  testWidgets('Testa callback de re-tentativa no DownloadHistoryDialog',
      (WidgetTester tester) async {
    final history = DownloadHistoryService.instance;
    await history.limpar();

    await history.registrarOuAtualizar(
      url: 'https://site.com/falha.jpg',
      status: DownloadStatus.error,
      errorMessage: 'Falha 404',
    );

    List<String> retried = [];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadHistoryDialog(
            onRetryUrls: (urls) {
              retried = urls;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rebaixar Todos os Erros'), findsOneWidget);
    await tester.tap(find.text('Rebaixar Todos os Erros'));
    await tester.pump();

    expect(retried, contains('https://site.com/falha.jpg'));
  });
}
