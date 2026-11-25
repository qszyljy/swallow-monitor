import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import 'contracts/model_package.dart';
import 'spec.dart';

class ModelImportResult {
  const ModelImportResult({
    required this.ok,
    required this.message,
    this.directory,
    this.labels,
    this.issues = const <String>[],
  });

  final bool ok;
  final String message;
  final String? directory;
  final List<String>? labels;
  final List<String> issues;
}

/// 模型包的导入与登记。
///
/// 只做三件事：解压、校验、登记。推理还没有接（`TfliteClassifier` 未实现），
/// 所以导入成功也只代表「这个包和 App 的参数对得上」。
class ModelManager {
  static Future<Directory> modelsDir() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/models');
  }

  static Future<File> _activeFile() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}/model_active.json');
  }

  static Future<String?> activeDir() async {
    try {
      final file = await _activeFile();
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      if (data is Map && data['dir'] is String) return data['dir'] as String;
    } catch (_) {
      // 读坏了当作未激活
    }
    return null;
  }

  static Future<void> setActive(String directory) async {
    final file = await _activeFile();
    await file.writeAsString(jsonEncode({'dir': directory}));
  }

  static Future<void> clearActive() async {
    final file = await _activeFile();
    if (await file.exists()) await file.delete();
  }

  /// 读当前激活包的信息，界面用。
  static Future<ModelPackage?> describeActive() async {
    final dir = await activeDir();
    if (dir == null) return null;
    try {
      return await ModelPackage.load(dir);
    } catch (_) {
      return null;
    }
  }

  /// 导入 zip：解压到 models/model_<时间戳>/，校验四件套与参数一致性。
  static Future<ModelImportResult> importZip(String zipPath) async {
    Directory? target;
    try {
      final root = await modelsDir();
      await root.create(recursive: true);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      target = Directory('${root.path}/model_$stamp');
      await target.create(recursive: true);

      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      var count = 0;
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final name = entry.name.replaceAll('\\', '/');
        if (name.contains('..') || name.startsWith('/')) continue;
        final out = File('${target.path}/$name');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(entry.content, flush: true);
        count++;
      }
      if (count == 0) {
        return const ModelImportResult(ok: false, message: '压缩包是空的');
      }

      final package = await ModelPackage.load(target.path);
      final issues = package.checkAgainstApp(PipelineSpec.current);
      if (issues.isNotEmpty) {
        return ModelImportResult(
          ok: false,
          message: '模型和 App 的参数对不上，不能激活',
          directory: target.path,
          labels: package.labels,
          issues: issues,
        );
      }

      await setActive(target.path);
      return ModelImportResult(
        ok: true,
        message: '已导入：${package.labels.length} 类',
        directory: target.path,
        labels: package.labels,
      );
    } catch (e) {
      if (target != null) {
        try {
          if (await target.exists()) await target.delete(recursive: true);
        } catch (_) {
          // 清不掉就留着，不影响判断
        }
      }
      return ModelImportResult(ok: false, message: '导入失败：$e');
    }
  }
}
