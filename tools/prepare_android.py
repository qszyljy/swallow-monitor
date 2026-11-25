#!/usr/bin/env python3
"""给 `flutter create` 生成的 Android 工程打补丁。

仓库里不放 android/ 目录（几百个文件，且随 Flutter 版本变），
CI 里现场生成，再用这个脚本补上音频插件需要的东西：

  1. 录音与蓝牙权限
  2. minSdk 24（record 要求 23 以上）
  3. 应用显示名

用法: python3 tools/prepare_android.py <flutter 工程目录>
"""

from __future__ import annotations

import pathlib
import re
import sys

PERMISSIONS = [
    ("android.permission.RECORD_AUDIO", None),
    ("android.permission.BLUETOOTH_SCAN", "neverForLocation"),
    ("android.permission.BLUETOOTH_CONNECT", None),
    ("android.permission.ACCESS_FINE_LOCATION", None),
]

APP_LABEL = "吞咽采集"


def patch_manifest(root: pathlib.Path) -> str:
    manifest = root / "android/app/src/main/AndroidManifest.xml"
    if not manifest.exists():
        return "找不到 AndroidManifest.xml"

    text = manifest.read_text(encoding="utf-8")

    added = []
    for name, flag in PERMISSIONS:
        if name in text:
            continue
        flag_attr = (
            f' android:usesPermissionFlags="{flag}"' if flag else ""
        )
        added.append(f'    <uses-permission android:name="{name}"{flag_attr} />\n')

    if added:
        text = text.replace("<application", "".join(added) + "<application", 1)

    text = re.sub(r'android:label="[^"]*"', f'android:label="{APP_LABEL}"', text, count=1)
    manifest.write_text(text, encoding="utf-8")
    return f"权限新增 {len(added)} 条，应用名改为 {APP_LABEL}"


def patch_min_sdk(root: pathlib.Path) -> str:
    for name in ("build.gradle.kts", "build.gradle"):
        path = root / "android/app" / name
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        new = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 24", text)
        new = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", new)
        if new != text:
            path.write_text(new, encoding="utf-8")
            return f"{name}: minSdk -> 24"
    return "未找到 minSdk 配置，跳过（如构建报错请检查这里）"


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    root = pathlib.Path(sys.argv[1]).resolve()
    if not root.exists():
        print(f"目录不存在: {root}")
        return 1
    print(patch_manifest(root))
    print(patch_min_sdk(root))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
