# Carbide Shell 碳壳

一个能连服务器干活的 agent，跑在手机和电脑上。

- 纯 Dart 内核：一轮 = 问模型 → 调工具 → 回填结果 → 再问，直到给出结论
- 工具：`ssh_exec`（可带 timeout_seconds）/ `ssh_sftp` / `http_request` / `local_exec`（仅桌面）/ `file_io` / `remember`
- 任务与监听：`task_add` / `task_list` / `task_control`、`watch_add` / `watch_list` / `watch_control`
- 主机：`host_list`，Advance Master 另有 `host_add` / `host_remove`
- 跑长任务时挂一条前台通知，切出去、锁屏也继续跑
- 附件：图片进多模态，纯文本与 Word（.docx）抽成文字拼进对话
- 审批：只读自动放行，写操作弹确认卡，命中危险规则直接拒
- 主机密钥 TOFU：首次连接记指纹，之后不一致拒连
- 视觉规范见 `DESIGN.md`（暖白纸底、白卡浮起、一个墨蓝强调色）

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

## 发布

打一个 `v*` 标签就出包（`.github/workflows/release.yml`），装包按架构分开出三个：
`CarbideShell_<tag>_arm64-v8a.apk` / `_armeabi-v7a.apk` / `_x86_64.apk`，先发预发布。
手机几乎都是 arm64，应用内更新也优先拿那一个。

签名固定：APK 用仓库里的一套密钥签，所以新版能直接装在旧版上。密钥不进仓库，CI 从这四个仓库密钥里取：
`ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`
（PKCS12，别名 `carbide`）。本地没有 `ANDROID_KEYSTORE_BASE64` 时退回 debug 签名，只影响本地随手跑的包。

证书指纹（SHA-256）：`0ab48eb8643ca144a19de1479eb5af027cc1bcbc59e03aff0009a72a07a82b35`。
发布流程每次都会打印一遍，可以拿来核对。

小改动不换版本号：删掉标签（`git tag -d vX` + 推 `:refs/tags/vX`），重打到修好的提交再推。
重推前先在网页上把同名 Release 删掉，否则 action-gh-release 会报 `already_exists`。
