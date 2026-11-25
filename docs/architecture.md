# 手机端架构

三层，从上到下：**参数源 → 接口契约 → 界面**。
所有数字只在 `assets/spec.default.json` 里出现一次；所有可替换的东西都在 `contracts/`。

```
assets/spec.default.json          唯一参数源（采样率/窗长/步长/阈值/时延/同步容差）
        │
        ▼
lib/core/spec.dart                PipelineSpec：解析、校验、兜底值
        │
        ├──► lib/core/contracts/sample_source.dart   一路数据源（麦克风 / BLE）
        ├──► lib/core/contracts/segmenter.dart       能量双阈值分割 + 冷却
        ├──► lib/core/contracts/classifier.dart      模型接口 + 输入约定
        ├──► lib/core/contracts/detector.dart        装配线：帧 → 事件 → 结果
        └──► lib/core/contracts/model_package.dart   导出包读取与一致性检查
        │
        ▼
lib/ui/*.dart                     界面只读 spec 和 interface，不碰具体实现
```

## 数据流

```
SampleSource.frames ──► 环形缓冲（保留最近 N 秒）
        │                     │
        │                     └──► 波形（每 10 ms 一个峰值点）
        ▼
   每帧算能量 (dBFS)
        │
        ▼
 EventSegmenter.update() ──► EventCandidate（起止时间戳）
        │
        ▼
 Classifier.classifyWindow() ──► 三类分数
        │
        ▼
 连续 voteWindows 窗里命中 ≥ voteMinHits ──► 确认事件
        │
        ▼
 DetectionResult（label / score / latencyMs / timestampMicros）
        │
        ├──► 界面：当前判定、事件计数
        └──► 记录：盲测表、时延打点
```

## 只改一个文件的那些数字

| 数字 | 你在哪改 | 影响 |
|---|---|---|
| 采样率、通道、位深 | `spec.default.json → audio` | 录音、WAV 头、特征、推理输入 |
| 窗长、步长 | `→ window` | 切窗、推理长度、响应延迟 |
| 阈值、最短/最长事件、冷却、投票 | `→ detection` | 事件检测与误触发率 |
| 时延预算 | `→ latency` | 报告里的两个时延口径 |
| 同步容差 | `→ sync` | 双路对齐验收 |

改完重启 App 生效，`PipelineSpec.validate()` 会在启动时自检并把问题打出来
（比如窗长不是步长整数倍、关闭阈值高于开启阈值）。

## 换数据源的步骤（BLE 接入时）

1. 写 `lib/core/impls/ble_source.dart`，实现 `SampleSource`
2. `deviceTimestampMicros` 必须填**单片机给的时间戳**，不是手机收到包的时刻
3. 界面和检测器一行都不用改——它们只认 `SampleFrame`
4. 双路对齐：两个 source 的帧按 `deviceTimestampMicros` 合并，误差超过
   `spec.sync.toleranceMs` 就在日志里报警

## 接模型的步骤

1. 把训练端导出的四件套拷到手机上（`labels.txt` / `preprocess.json` / 模型 / `eval.json`）
2. `ModelPackage.load(dir)` 读包，缺文件直接抛错
3. `package.checkAgainstApp(PipelineSpec.current)` 做四项一致性检查：
   采样率、窗长、归一化、类别顺序——**任何一项不一致都必须拒绝加载**
4. 新写 `TfliteClassifier implements Classifier`，把 `ready` 置真
5. 界面把 `PlaceholderClassifier` 换成它，其余不动

## 现在还没接上的地方（重要）

契约写好了，但界面还在用旧的 `RecorderService` 直接录音，尚未改成
`SampleSource`。迁移顺序建议：

1. 把 `RecorderService` 包一层 `MicSource implements SampleSource`（不改内部逻辑）
2. 波形页改成订阅 `SampleSource.frames`
3. 加 `MicDetector implements Detector`，把 `EnergyGateSegmenter` 串上
4. 最后接 `TfliteClassifier`

第 1~2 步只是包一层，风险低；第 3 步才开始有新的行为。
先做到第 3 步，现场就能演示「说一句话 → 不计数，咳一声 → 计数 +1」。

## 命名与目录

- 录音文件：`records/<被试>_<类别>_<yyyyMMdd_HHmmss>[_n].wav`（当前平铺，
  建议后续按被试分子目录，训练端两种都能扫）
- 类别：`swallow` / `cough` / `interfere` / `rest`
- 训练端扫描规则见 `swallow-trainer/trainer/dataset.py` 的 `_NAME_RE`

## 为什么分割器要吃能量值而不是音频

`EnergyGateSegmenter.update(energyDb, timestampMicros)` 的输入是数字，
所以可以在电脑上写单测跑几百个阈值组合，不用每次装 APK 试一遍（装一次四分钟）。
接口设计成这个样子就是为了这个。
