import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'downloader_engine.dart';
import 'platform_storage.dart';

class DownloadHistoryItem {
  final String id;
  final String url;
  final DateTime timestamp;
  DownloadStatus status;
  String? errorMessage;
  String? savedFileName;
  String? targetFormat;

  DownloadHistoryItem({
    required this.id,
    required this.url,
    required this.timestamp,
    required this.status,
    this.errorMessage,
    this.savedFileName,
    this.targetFormat,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'timestamp': timestamp.toIso8601String(),
    'status': status.name,
    'errorMessage': errorMessage,
    'savedFileName': savedFileName,
    'targetFormat': targetFormat,
  };

  factory DownloadHistoryItem.fromJson(Map<String, dynamic> json) {
    DownloadStatus status;
    try {
      status = DownloadStatus.values.byName(json['status'] as String);
    } catch (_) {
      status = DownloadStatus.idle;
    }

    return DownloadHistoryItem(
      id: json['id'] as String? ?? UniqueKey().toString(),
      url: json['url'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      status: status,
      errorMessage: json['errorMessage'] as String?,
      savedFileName: json['savedFileName'] as String?,
      targetFormat: json['targetFormat'] as String?,
    );
  }

  String get formattedDate {
    final y = timestamp.year.toString().padLeft(4, '0');
    final m = timestamp.month.toString().padLeft(2, '0');
    final d = timestamp.day.toString().padLeft(2, '0');
    final hh = timestamp.hour.toString().padLeft(2, '0');
    final mm = timestamp.minute.toString().padLeft(2, '0');
    final ss = timestamp.second.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm:$ss';
  }
}

class DownloadHistoryService extends ChangeNotifier {
  static final DownloadHistoryService instance = DownloadHistoryService._();
  DownloadHistoryService._();

  final List<DownloadHistoryItem> _items = [];
  bool _initialized = false;

  List<DownloadHistoryItem> get items => List.unmodifiable(_items);

  int get errorCount =>
      _items.where((e) => e.status == DownloadStatus.error).length;

  int get completedCount =>
      _items.where((e) => e.status == DownloadStatus.completed).length;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final jsonStr = await PlatformStorage.loadHistoryJson();
      if (jsonStr != null && jsonStr.trim().isNotEmpty) {
        final dynamic decoded = jsonDecode(jsonStr);
        if (decoded is List) {
          _items.clear();
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              _items.add(DownloadHistoryItem.fromJson(item));
            }
          }
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar histórico de downloads: $e');
    }
  }

  Future<void> registrarOuAtualizar({
    required String url,
    required DownloadStatus status,
    String? errorMessage,
    String? savedFileName,
    String? targetFormat,
  }) async {
    // Procura registro recente existente da mesma URL para atualizar
    final index = _items.indexWhere((element) => element.url == url);

    if (index != -1) {
      final existente = _items[index];
      existente.status = status;
      existente.errorMessage = errorMessage;
      existente.savedFileName = savedFileName ?? existente.savedFileName;
      if (targetFormat != null) {
        existente.targetFormat = targetFormat;
      }
      // Move o item para o topo para ficar como o mais recente
      if (index > 0) {
        final removido = _items.removeAt(index);
        _items.insert(0, removido);
      }
    } else {
      _items.insert(
        0,
        DownloadHistoryItem(
          id: '${DateTime.now().millisecondsSinceEpoch}_${_items.length}',
          url: url,
          timestamp: DateTime.now(),
          status: status,
          errorMessage: errorMessage,
          savedFileName: savedFileName,
          targetFormat: targetFormat,
        ),
      );
    }

    // Limita o histórico aos 500 registros mais recentes
    if (_items.length > 500) {
      _items.removeRange(500, _items.length);
    }

    notifyListeners();
    await _salvar();
  }

  Future<void> remover(String id) async {
    _items.removeWhere((e) => e.id == id);
    notifyListeners();
    await _salvar();
  }

  Future<void> limpar() async {
    _items.clear();
    notifyListeners();
    await _salvar();
  }

  Future<void> limparApenasErros() async {
    _items.removeWhere((e) => e.status == DownloadStatus.error);
    notifyListeners();
    await _salvar();
  }

  List<String> getUrlsComErro() {
    final seen = <String>{};
    final urls = <String>[];
    for (final item in _items) {
      if (item.status == DownloadStatus.error && !seen.contains(item.url)) {
        seen.add(item.url);
        urls.add(item.url);
      }
    }
    return urls;
  }

  Future<void> _salvar() async {
    try {
      final jsonList = _items.map((e) => e.toJson()).toList();
      final jsonStr = jsonEncode(jsonList);
      await PlatformStorage.saveHistoryJson(jsonStr);
    } catch (e) {
      debugPrint('Erro ao persistir histórico: $e');
    }
  }
}

