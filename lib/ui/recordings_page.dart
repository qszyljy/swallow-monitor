import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/recorder_service.dart';

class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key});

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  Future<List<File>> _future = RecorderService.listRecordings();

  void _reload() {
    setState(() => _future = RecorderService.listRecordings());
  }

  Future<void> _share(File file) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: '喉麦录音 ${file.path.split('/').last}',
      ),
    );
  }

  Future<void> _delete(File file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条录音？'),
        content: Text(file.path.split('/').last),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await file.delete();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记录'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<File>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final files = snapshot.data ?? const <File>[];
          if (files.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '还没有音频文件。\n去「采集」页录一条，按类别自动命名。',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: files.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    '共 ${files.length} 条 · '
                    '${(files.fold<int>(0, (s, f) => s + f.lengthSync()) / 1024 / 1024).toStringAsFixed(1)} MB',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }
              final file = files[index - 1];
              final name = file.path.split('/').last;
              final sizeMb = file.lengthSync() / 1024 / 1024;
              final seconds =
                  file.lengthSync() / (RecorderService.sampleRate * 2);
              return ListTile(
                leading: const Icon(Icons.audio_file),
                title: Text(name, style: Theme.of(context).textTheme.bodyMedium),
                subtitle: Text(
                  '${seconds.toStringAsFixed(1)} s · ${sizeMb.toStringAsFixed(2)} MB',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '导出',
                      onPressed: () => _share(file),
                      icon: const Icon(Icons.ios_share),
                    ),
                    IconButton(
                      tooltip: '删除',
                      onPressed: () => _delete(file),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
