import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/download_history_service.dart';
import '../services/downloader_engine.dart';

class DownloadHistoryDialog extends StatefulWidget {
  final void Function(List<String> urls) onRetryUrls;

  const DownloadHistoryDialog({super.key, required this.onRetryUrls});

  @override
  State<DownloadHistoryDialog> createState() => _DownloadHistoryDialogState();
}

class _DownloadHistoryDialogState extends State<DownloadHistoryDialog> {
  final DownloadHistoryService _history = DownloadHistoryService.instance;
  DownloadStatus? _filtroStatus;

  void _copiarTexto(String texto, String sucessoMsg) {
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(sucessoMsg), duration: const Duration(seconds: 2)),
    );
  }

  void _copiarUrlsComErro() {
    final urls = _history.getUrlsComErro();
    if (urls.isEmpty) return;
    _copiarTexto(
      urls.join('\n'),
      '${urls.length} links com erro copiados para a área de transferência.',
    );
  }

  void _rebaixarUrls(List<String> urls) {
    if (urls.isEmpty) return;
    Navigator.of(context).pop();
    widget.onRetryUrls(urls);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListenableBuilder(
            listenable: _history,
            builder: (context, _) {
              final todos = _history.items;
              final filtrados = _filtroStatus == null
                  ? todos
                  : todos.where((e) => e.status == _filtroStatus).toList();

              final totalErros = _history.errorCount;
              final urlsComErro = _history.getUrlsComErro();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.history, color: Colors.tealAccent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Histórico de Links e Downloads',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SegmentedButton<DownloadStatus?>(
                        segments: [
                          ButtonSegment(
                            value: null,
                            label: Text('Todos (${todos.length})'),
                          ),
                          ButtonSegment(
                            value: DownloadStatus.error,
                            label: Text('Erros ($totalErros)'),
                          ),
                          ButtonSegment(
                            value: DownloadStatus.completed,
                            label: Text('Concluídos (${_history.completedCount})'),
                          ),
                        ],
                        selected: {_filtroStatus},
                        onSelectionChanged: (set) {
                          setState(() => _filtroStatus = set.first);
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Fechar',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (totalErros > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Você tem $totalErros link(s) que falharam ao baixar. Deseja re-tentar?',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _rebaixarUrls(urlsComErro),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Rebaixar Todos os Erros'),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 16),
                  Expanded(
                    child: filtrados.isEmpty
                        ? const Center(
                            child: Text(
                              'Nenhum registro encontrado no histórico.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtrados.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = filtrados[index];
                              final isError =
                                  item.status == DownloadStatus.error;

                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                leading: Icon(
                                  isError
                                      ? Icons.error_outline
                                      : Icons.check_circle_outline,
                                  color: isError
                                      ? Colors.redAccent
                                      : Colors.tealAccent,
                                ),
                                title: SelectableText(
                                  item.url,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text(
                                          item.formattedDate,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        if (item.targetFormat != null &&
                                            item.targetFormat!.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.blueGrey.withValues(alpha: 0.3),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              item.targetFormat!.toUpperCase(),
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (item.savedFileName != null) ...[
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              'Salvo: ${item.savedFileName}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.tealAccent,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (isError && item.errorMessage != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          'Erro: ${item.errorMessage}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.copy,
                                        size: 18,
                                      ),
                                      tooltip: 'Copiar link',
                                      onPressed: () => _copiarTexto(
                                        item.url,
                                        'Link copiado.',
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.refresh,
                                        size: 18,
                                        color: Colors.tealAccent,
                                      ),
                                      tooltip: 'Baixar novamente agora',
                                      onPressed: () =>
                                          _rebaixarUrls([item.url]),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                        color: Colors.grey,
                                      ),
                                      tooltip: 'Remover do histórico',
                                      onPressed: () =>
                                          _history.remover(item.id),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const Divider(height: 16),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: todos.isEmpty ? null : _history.limpar,
                        icon: const Icon(Icons.delete_sweep),
                        label: const Text('Limpar Histórico'),
                      ),
                      if (totalErros > 0) ...[
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: _copiarUrlsComErro,
                          icon: const Icon(Icons.copy_all),
                          label: const Text('Copiar Erros'),
                        ),
                      ],
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Fechar'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

