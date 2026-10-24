# Carbide Shell 碳壳

一个能连服务器干活的 agent，跑在手机和电脑上。

- 纯 Dart 内核：一轮 = 问模型 → 调工具 → 回填结果 → 再问，直到给出结论
- 工具：`ssh_exec` / `ssh_sftp` / `http_request` / `local_exec`（仅桌面）/ `file_io` / `remember`
- 审批：只读自动放行，写操作弹确认卡，命中危险规则直接拒
- 主机密钥 TOFU：首次连接记指纹，之后不一致拒连
- 视觉规范见 `DESIGN.md`（瑞士风格，一个强调色，方角，用线不用卡）

## 结构

```
lib/core/   内核：模型接口、工具表、审批策略、日志、循环（不 import Flutter）
lib/tools/  工具实现
lib/data/   主机清单、设置、日志落盘
lib/ui/     界面
```

## 开发

```
flutter pub get
flutter test
flutter run
```

沙箱里没有 Flutter SDK，`analyze` / `test` / 构建全部在 CI 跑（`.github/workflows/ci.yml`）。
