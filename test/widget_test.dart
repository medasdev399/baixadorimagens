import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baixadorimagens/main.dart';
import 'package:baixadorimagens/services/app_logger.dart';

void main() {
  testWidgets('Renderiza tela principal, monta fila e abre visualizador de logs',
      (WidgetTester tester) async {
    AppLogger.instance.limpar();
    AppLogger.instance.info('Teste de log inicial');

    await tester.pumpWidget(const BaixadorImagensApp());

    expect(find.text('Baixador de Imagens'), findsOneWidget);
    expect(find.text('Cole as URLs ao lado para montar a fila.'), findsOneWidget);

    final urlField = find.byType(TextField).first;
    await tester.enterText(
      urlField,
      'https://site1.com/foto.jpg\nhttps://site2.com/imagem.png',
    );
    await tester.pump();

    expect(find.text('https://site1.com/foto.jpg'), findsWidgets);
    expect(find.text('https://site2.com/imagem.png'), findsWidgets);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);

    // Abre o visualizador de logs na AppBar
    await tester.tap(find.byIcon(Icons.receipt_long));
    await tester.pumpAndSettle();

    expect(find.text('Logs da Aplicação'), findsOneWidget);
    expect(find.textContaining('Teste de log inicial'), findsOneWidget);
  });
}
