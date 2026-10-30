# Carbide Shell 碳壳

一个能连服务器干活的 agent，跑在手机和电脑上。

- 纯 Dart 内核：一轮 = 问模型 → 调工具 → 回填结果 → 再问，直到给出结论
- 工具：`ssh_exec`（可带 timeout_seconds）/ `ssh_sftp` / `http_request` / `local_exec`（仅桌面）/ `file_io` / `remember` / `memory`
- 网络：`http_request` 只发允许列表里的域名，`http_allow` 看和改这份清单（加进去的连带子域）；`http_probe` 只做 TCP 握手、不发内容，所以不受域名白名单限制
- 临时文件区：模型用 `temp_file` 列、读、写、删，用 `temp_upload` 传到主机；界面上能预览、加文件、传服务器
- 任务与监听：`task_add` / `task_list` / `task_control`、`watch_add` / `watch_list` / `watch_control`
- 主机：`host_list`，Advance Master 另有 `host_add` / `host_remove`
- 手机上的扩展：设置 → 扩展 里逐项打开，开了才给模型。
  设备信息 `device_info`、剪贴板 `clipboard`、打开与分享 `open_url` / `share_text`、
  定位 `where_am_i`、联系人 `find_contact`、短信 `sms_send`、通知 `notifications`、
  使用时间 `app_usage`、应用 `open_app` / 闹钟 `set_alarm` / 计时器 `set_timer`、音量 `volume`。
  默认全关。
- 跑长任务时挂一条前台通知，切出去、锁屏也继续跑
- 附件：图片进多模态，纯文本与 Word（.docx）抽成文字拼进对话
- 审批：只读自动放行，写操作弹确认卡，命中危险规则直接拒
- 主机密钥 TOFU：首次连接记指纹，之后不一致拒连
- 视觉规范见 `DESIGN.md`（暖白纸底、白卡浮起、一个墨蓝强调色）

## 它能自己动起来

除了你问一句它答一句，还可以让它在特定条件下自己做事。

### 定时任务

到点让助手跑一条指令。`daily` 每天、`weekly` 每周、`interval` 每隔几分钟、`once` 只跑一次。

要「磁盘超过 90% 才清」这种判断，就把条件写进 `conditions`，到点先读数字，符合了才叫模型：

```
disk>90 且 (cpu>80 或 memory>=85)
```

条件没满足就隔几分钟再看一次，最多等一小时（`gate_window_minutes`），过了这一轮就不跑。

### 资源监听

每隔几分钟读一台机器的 CPU、内存、磁盘、交换、负载，或者失败登录次数、没见过的来源登录，过了线就给手机发通知。

这个不叫模型，只看数字和登录记录 —— 便宜、快、不会自己发挥。

### 触发器

三种条件：

- **手机状态**：电量低了、到家了在充电、耳机插上了
- **消息通知**：某条通知的正文里出现了关键词
- **定时**：跟定时任务差不多

三种动作：发一条通知、让模型跑一句话（可以先弹确认卡等人点一下）、或者直接打开一个应用。

消息通知这一条认「冲着我来的」：群里有人骂街、跟别人斗嘴，不该由它接话。规则是：

- 私聊直接算
- 群消息只有明确 @ 了它才算 —— @ 全体成员不算，只是提到名字也不算
- 认不准是不是群的时候，一律要求明确 @
- 在触发器编辑面板填一格「我是谁」：昵称、呼号、备注名，逗号分开。任一命中就算 @ 了它
- 没填的老配置照旧只看关键词，行为跟以前一样

微信那种 `@昵称（呼号) 备注名` 的写法认得出来。

### 邮箱

配好 SMTP / IMAP 之后，模型能看收件箱（`mail_inbox` / `mail_read`），也能发通知邮件（`mail_send`）。

能发给谁有一份名单（`mail_allow`），不在名单里发不出去。发之前会弹确认卡，写明收件人和理由。

### 报告

`report_render` 把一堆数字和几段话排成一份报告，落到临时文件区：

- `template=report` 网页版，手机上好读
- `template=email` 纯 table 加全行内样式，Gmail 和 Outlook 都认
- `template=plain` Markdown 纯文本

`render_check` 可以体检一份 HTML：标签配不配平、行内样式覆盖率、有没有外链样式和图片。

## 对话

- 一个对话在跑的时候，状态不在页面里 —— 关掉这一页、切到别的对话，它照样往下跑
- 报错那一轮可以回退一步：标题栏一个回退按钮，「更多」里也有。退回去把最后那句提问和它后面的一起删掉，那句话放回输入框，光标停在末尾
- 长期记忆能写、能改、能删：`remember` 记一条，`memory` 看全部（带 id）、按 id 改写、按 id 删掉
- 配置里的密钥存在安全存储：`env_list` 看有哪些（只给末尾两位），`env_set` / `env_delete` 增删，`env_request` 带着密钥发请求
- `plan` 把一件事拆成清单摆在对话顶上，做完一步更新一次状态
- `ask` 缺一个只有你知道的值时问你，改东西之前拿不准也会问你

## 审批

两档拦：

- **永远不做**：`mkfs`、`dd of=/dev/`、`shutdown`、`reboot`、`poweroff`、`halt`、写 `/etc/`、`chmod -R 777 /`、`init 0`、删到根、删到整个家目录
- **先问一句**：删除、清库这类（`rm`、`rmdir`、`shred`、`unlink`、`drop table/database`）。问过就能做，批准卡上会写明这一步会删什么

只读操作自动放行。

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
