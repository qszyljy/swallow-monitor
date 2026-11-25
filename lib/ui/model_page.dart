import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/classifier_provider.dart';
import '../core/contracts/model_package.dart';
import '../core/model_manager.dart';

/// 模型导入页：选 zip → 解压 → 四项一致性检查 → 登记为当前模型。
class ModelPage extends StatefulWidget {
  const ModelPage({super.key, required this.classifierProvider});

  final ClassifierProvider classifierProvider;

  @override
  State<ModelPage> createState() => _ModelPageState();
}

class _ModelPageState extends State<ModelPage> {
  ModelPackage? _package;
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final package = await ModelManager.describeActive();
    if (!mounted) return;
    setState(() => _package = package);
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: '选择模型包 (.zip)',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (files.isEmpty) return;
      final path = files.first.path;
      if (path == null) {
        setState(() => _status = '拿不到文件路径');
        return;
      }
      final result = await ModelManager.importZip(path);
      if (!mounted) return;
      setState(() {
        _status = result.issues.isEmpty
            ? result.message
            : '${result.message}\n${result.issues.join('\n')}';
      });
      await _refresh();
      // 让全局分类器换成新模型，不用重启
      await widget.classifierProvider.load();
    } catch (e) {
      if (mounted) setState(() => _status = '导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    await ModelManager.clearActive();
    await _refresh();
    if (!mounted) return;
    setState(() => _status = '已取消激活');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final package = _package;
    return Scaffold(
      appBar: AppBar(title: const Text('模型')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前模型', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  if (package == null)
                    const Text('未导入')
                  else ...[
                    Text('类别：${package.labels.join(' / ')}'),
                    Text(
                      '采样率 ${package.input.sampleRate} Hz · '
                      '窗长 ${package.input.windowMs} ms',
                    ),
                    Text('输入：${package.input.layout} · 格式：${package.input.format}'),
                    Text(
                      '归一化：${package.input.normalize}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: scheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('模型包要有什么', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Text(
                    'training 端 export/ 目录打成的 zip，四件套缺一不可：\n'
                    'labels.txt、preprocess.json、模型文件、eval.json',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.upload_file),
            label: Text(_busy ? '处理中…' : '导入模型包 (.zip)'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: package == null ? null : _clear,
            icon: const Icon(Icons.link_off),
            label: const Text('取消激活'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            SelectableText(
              _status!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          Text(
            '注意：导入只完成「解压 + 参数校验 + 登记」，'
            '推理还没接（TfliteClassifier 未实现），分类页仍是占位。',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}
