import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/app_logger.dart';
import '../services/image_converter_service.dart';
import '../services/platform_storage.dart';

class ImageConversionItem {
  final String name;
  final String path;
  final Uint8List bytes;
  String? outputName;
  String? statusText;
  bool isSuccess = false;
  bool isConverting = false;
  bool isError = false;

  ImageConversionItem({
    required this.name,
    required this.path,
    required this.bytes,
  });
}

class ImageConverterDialog extends StatefulWidget {
  final String initialOutputDir;

  const ImageConverterDialog({super.key, required this.initialOutputDir});

  @override
  State<ImageConverterDialog> createState() => _ImageConverterDialogState();
}

class _ImageConverterDialogState extends State<ImageConverterDialog> {
  final ImageConverterService _converter = ImageConverterService.instance;
  final AppLogger _logger = AppLogger.instance;

  late final TextEditingController _dirController = TextEditingController(
    text: widget.initialOutputDir,
  );

  final List<ImageConversionItem> _items = [];
  ImageTargetFormat _targetFormat = ImageTargetFormat.jpg;
  double _quality = 90;
  bool _isConverting = false;
  double _progress = 0.0;

  @override
  void dispose() {
    _dirController.dispose();
    super.dispose();
  }

  Future<void> _selecionarArquivos() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          'webp',
          'bmp',
          'gif',
          'tiff',
          'tga',
        ],
      );

      if (files.isNotEmpty) {
        final novos = <ImageConversionItem>[];
        for (final f in files) {
          final bytes = await f.readAsBytes();
          if (bytes.isNotEmpty) {
            novos.add(
              ImageConversionItem(
                name: f.name,
                path: f.path ?? f.name,
                bytes: bytes,
              ),
            );
          }
        }
        if (mounted) {
          setState(() {
            _items.addAll(novos);
          });
        }
        _logger.info(
          'Arquivos adicionados para conversão',
          details: 'Quantidade: ${novos.length}',
        );
      }
    } catch (e) {
      _logger.error('Erro ao selecionar arquivos de imagem', error: e);
    }
  }

  Future<void> _selecionarPastaDestino() async {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: 'Selecione a pasta de destino para as imagens convertidas',
    );
    if (selected != null && mounted) {
      setState(() => _dirController.text = selected);
    }
  }

  Future<void> _iniciarConversao() async {
    if (_items.isEmpty || _isConverting) return;

    setState(() {
      _isConverting = true;
      _progress = 0.0;
    });

    final outputPath = _dirController.text.trim();
    await PlatformStorage.ensureDirectory(outputPath);

    int concluidos = 0;

    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      setState(() {
        item.isConverting = true;
        item.isError = false;
        item.statusText = 'Convertendo...';
      });

      try {
        final convertedBytes = await _converter.convertImageBytes(
          bytes: item.bytes,
          targetFormat: _targetFormat,
          quality: _quality.toInt(),
        );

        final adjustedName = _converter.adjustFileName(
          item.name,
          _targetFormat,
        );

        final savedName = await PlatformStorage.saveImageBytes(
          outputPath: outputPath,
          fileName: adjustedName,
          bytes: convertedBytes,
        );

        item.outputName = savedName;
        item.isSuccess = true;
        item.statusText = 'Convertido com sucesso';
        concluidos++;

        _logger.info(
          'Imagem convertida com sucesso',
          details:
              'De ${item.name} (${(item.bytes.length / 1024).toStringAsFixed(1)} KB) para $savedName (${(convertedBytes.length / 1024).toStringAsFixed(1)} KB)',
        );
      } catch (e) {
        item.isError = true;
        item.statusText = 'Erro: $e';
        _logger.error(
          'Falha ao converter imagem ${item.name}',
          error: e,
        );
      } finally {
        item.isConverting = false;
        setState(() {
          _progress = (i + 1) / _items.length;
        });
      }
    }

    setState(() {
      _isConverting = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Conversão concluída: $concluidos de ${_items.length} imagens convertidas!',
          ),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  void _limparLista() {
    if (_isConverting) return;
    setState(() {
      _items.clear();
      _progress = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.transform, color: Colors.tealAccent),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Conversor de Imagens',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Fechar',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Controles de Conversão
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Botão de seleção de formato
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Formato de Saída:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<ImageTargetFormat>(
                        value: _targetFormat,
                        underline: const SizedBox(),
                        items: ImageTargetFormat.values
                            .where((f) => !f.isOriginal)
                            .map((f) => DropdownMenuItem(
                                  value: f,
                                  child: Text(f.label),
                                ))
                            .toList(),
                        onChanged: _isConverting
                            ? null
                            : (val) {
                                if (val != null) {
                                  setState(() => _targetFormat = val);
                                }
                              },
                      ),
                    ],
                  ),
                  if (_targetFormat == ImageTargetFormat.jpg ||
                      _targetFormat == ImageTargetFormat.webp) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Qualidade: ${_quality.toInt()}%'),
                        SizedBox(
                          width: 140,
                          child: Slider(
                            value: _quality,
                            min: 10,
                            max: 100,
                            divisions: 18,
                            onChanged: _isConverting
                                ? null
                                : (v) => setState(() => _quality = v),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dirController,
                      enabled: !_isConverting && !PlatformStorage.isWeb,
                      readOnly: PlatformStorage.isWeb,
                      decoration: InputDecoration(
                        labelText: PlatformStorage.isWeb
                            ? 'Destino no Navegador'
                            : 'Pasta de Destino para Conversão',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  if (!PlatformStorage.isWeb) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed:
                          _isConverting ? null : _selecionarPastaDestino,
                      icon: const Icon(Icons.folder_open),
                      tooltip: 'Escolher pasta de saída',
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _isConverting ? null : _selecionarArquivos,
                    icon: const Icon(Icons.add_photo_alternate),
                    label: const Text('Selecionar Imagens'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed:
                        _items.isEmpty || _isConverting ? null : _limparLista,
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Limpar'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.tealAccent.shade700,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _items.isEmpty || _isConverting
                        ? null
                        : _iniciarConversao,
                    icon: Icon(_isConverting ? Icons.hourglass_top : Icons.play_arrow),
                    label: Text(
                      _isConverting
                          ? 'Convertendo...'
                          : 'Converter (${_items.length})',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_isConverting) ...[
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
              ],
              const Divider(height: 1),
              Expanded(
                child: _items.isEmpty
                    ? const Center(
                        child: Text(
                          'Nenhuma imagem selecionada.\nClique em "Selecionar Imagens" para começar.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final kbOriginal =
                              (item.bytes.length / 1024).toStringAsFixed(1);

                          return ListTile(
                            dense: true,
                            leading: item.isConverting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    item.isSuccess
                                        ? Icons.check_circle
                                        : item.isError
                                        ? Icons.error_outline
                                        : Icons.image,
                                    color: item.isSuccess
                                        ? Colors.tealAccent
                                        : item.isError
                                        ? Colors.redAccent
                                        : Colors.grey,
                                  ),
                            title: Text(item.name),
                            subtitle: Text(
                              item.statusText ?? 'Original: $kbOriginal KB',
                              style: TextStyle(
                                color: item.isError
                                    ? Colors.redAccent
                                    : item.isSuccess
                                    ? Colors.tealAccent
                                    : Colors.grey,
                              ),
                            ),
                            trailing: Text('#${index + 1}'),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
