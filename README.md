<div align="center">

<img src="https://raw.githubusercontent.com/dariondong/carbide-shell/main/brand/wordmark_light.png" alt="Carbide Shell" width="420" />

<br/>

<img src="https://raw.githubusercontent.com/dariondong/carbide-shell/main/assets/pet/idle.png" alt="壳壳" width="180" />

<br/>

**一个能连服务器干活的 agent，跑在手机和电脑上。**

<br/>

<img src="https://img.shields.io/github/v/release/dariondong/carbide-shell?label=%E7%89%88%E6%9C%AC&style=flat-square" alt="版本" />
<img src="https://img.shields.io/github/stars/dariondong/carbide-shell?style=flat-square&label=%E6%98%9F%E6%98%9F" alt="星星" />
<img src="https://img.shields.io/badge/Dart-Flutter-3355E8?style=flat-square&label=%E5%86%99%E5%BC%8F" alt="语言" />
<img src="https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Desktop-3355E8?style=flat-square&label=%E5%8F%B0%E9%98%BF" alt="平台" />
<img src="https://img.shields.io/badge/pure-Dart%20core-3FA96B?style=flat-square&label=%E5%86%85%E6%A0%B8" alt="内核" />

<br/>

[下载](https://github.com/dariondong/carbide-shell/releases/latest) · [更新日志](CHANGELOG.md) · [视觉规范](DESIGN.md)

</div>

---

## 嗨，我是壳壳

一只住在终端里的猫。六边形的脑袋，脸上刻着一个 `>`，脖子上围条围巾。

我在这儿干的事，跟你直接 SSH 上去敲命令其实一样 —— 只不过你敲一条，我敲一串，
中间那些「查状态、看日志、重试、翻文件」的碎活，我替你干了。

**给我一句话，我给你一个结论。** 不是给你一堆命令让你自己看。

```
> 看看 ali 上那块盘还剩多少空间，占满了就清一下日志
```

我自己能干的事，不需要你守在旁边盯着：

- **定时任务**（`task_add` / `task_list` / `task_control`）—— 到点我起来干活。还能带条件：`disk>90 且 (cpu>80 或 memory>=85)`
- **资源监听**（`watch_add` / `watch_list` / `watch_control`）—— 每隔几分钟瞄一眼 CPU、内存、磁盘、负载，过了线就给你发通知
- **触发器**（`trigger_list` / `trigger_save` / `trigger_delete`）—— 电量低了、到家了在充电、有人在群里 @ 我
- **邮箱** —— 我能看收件箱，也能给你发通知邮件
- **报告** —— 把一堆数字排成一份能看的报告，网页版、邮件版、纯文本

---

## 我怎么干活

一轮是这样过去的：

```
问模型 → 调工具 → 把结果填回去 → 再问 → …… → 给你结论
```

纯 Dart 内核，不依赖 Flutter，所以能塞进手机、桌面、命令行任何地方。

### 工具

**连机器**

`ssh_exec`（可带 `timeout_seconds`）· `ssh_sftp` · `host_list` · `host_add` · `host_remove` · `remote_diff`

`remote_diff` 挺顺手：比两台机器上的同一份配置，或者跟昨天存的样比，
只把变了那几行甩给你看。

**上网**

`http_request` 只发允许列表里的域名，`http_allow` 看和改这份清单（加进去的连带子域）。
`http_probe` 只做 TCP 握手、不发内容，所以不受白名单限制 —— 排查网络的时候好用。

**读写文件**

`temp_file` 列、读、写、删 · `temp_upload` 传到主机 · `temp_download` 从主机拉回来
（8 MB 以内）· `local_exec` / `file_io`（仅桌面）

**记事**

`remember` 记一条，`memory` 看全部（带 id）、按 id 改写、按 id 删掉。

**邮件**

`mail_inbox` 看收件箱 · `mail_read` 读正文 · `mail_send` 发信 · `mail_allow` 管「我能发给谁」

**出报告**

`report_render` 排版（网页版 / 邮件版 / Markdown）· `render_check` 体检 HTML

**其他**

`clock` · `plan` · `ask` · `notify` · `http_probe` · `tune_param` · `env_*`（密钥存取）

### 手机上的扩展

设置 → 扩展 里逐项打开，**开了才给模型**，默认全关。

| 扩展 | 工具 | 能干什么 |
| --- | --- | --- |
| 设备信息 | `device_info` `phone_state` | 机型、电量、网络、剩余存储；充电、亮屏、锁屏、耳机、铃声、勿扰 |
| 剪贴板 | `clipboard` | 读一段、写一段 |
| 打开与分享 | `open_url` `share_text` | 用浏览器开网址 / 交给系统分享面板 |
| 定位 | `where_am_i` | 最近一次定位的经纬度和精度 |
| 联系人 | `find_contact` | 按名字找号码 |
| 短信 | `sms_send` | 给一个号码发条短信 |
| 通知 | `notifications` | 最近收到的通知：哪个应用、标题、正文 |
| 使用时间 | `app_usage` | 每个应用最近用了多久 |
| 应用与闹钟 | `open_app` `set_alarm` `set_timer` | 打开应用 / 设闹钟 / 设计时器 |
| 音量 | `volume` | 四档音量与铃声方式，看和改 |

---

## 我有点认生

群里有人骂街、跟别人斗嘴，不该由我接话。

所以消息通知这条触发器，认「**冲着我来的**」：

- 私聊直接算
- 群消息只有明确 @ 了我才算 —— @ 全体成员不算，只是提到名字也不算
- 认不准是不是群的时候，一律要求明确 @
- 在触发器编辑面板填一格「**我是谁**」：昵称、呼号、备注名，逗号分开，任一命中就算
- 微信那种 `@昵称（呼号) 备注名` 的写法认得出来
- 没填的老配置照旧只看关键词，行为跟以前一样

宁可漏掉，不替别人接话。

---

## 动手之前

两档拦：

**永远不做** —— `mkfs`、`dd of=/dev/`、`shutdown`、`reboot`、`poweroff`、`halt`、
写 `/etc/`、`chmod -R 777 /`、`init 0`、删到根、删到整个家目录。

**先问一句** —— 删除、清库这类（`rm`、`rmdir`、`shred`、`unlink`、`drop table/database`）。
问过就能做，批准卡上会写明这一步会删什么。

只读操作自动放行。

另外，**主机密钥 TOFU**：第一次连接记下指纹，之后对不上就拒连。

---

## 你和我的对话

- 一个对话在跑的时候，状态不在页面里 —— 关掉那一页、切到别的对话，它照样往下跑
- 报错那一轮可以回退一步。退回去把最后那句提问和它后面的一起删掉，那句话放回输入框，光标停在末尾
- 跑长任务挂一条前台通知，切出去、锁屏也继续跑
- 附件：图片进多模态，纯文本和 Word（`.docx`）抽成文字拼进对话
- `plan` 把一件事拆成清单摆在对话顶上，做完一步更新一次状态
- `ask` 缺一个只有你知道的值时问你，改东西之前拿不准也会问你

密钥放安全存储：`env_list` 看有哪些（只给末尾两位），`env_set` / `env_delete` 增删，
`env_request` 带着密钥发请求。

---

## 里面长什么样

```
lib/core/   内核：模型接口、工具表、审批策略、日志、循环（不 import Flutter）
lib/tools/  工具实现
lib/data/   主机清单、设置、日志落盘
lib/ui/     界面
```

视觉规范见 [`DESIGN.md`](DESIGN.md)：暖白纸底、白卡浮起、一个墨蓝强调色、柔和圆角。
界面代码里不许出现这份文件没写的颜色、圆角和阴影。

---

## 自己动手

```
flutter pub get
flutter test
flutter run
```

沙箱里没有 Flutter SDK，`analyze` / `test` / 构建全部在 CI 跑（`.github/workflows/ci.yml`）。

---

## 出包

打一个 `v*` 标签就出包（`.github/workflows/release.yml`），按架构出三个：
`CarbideShell_<tag>_arm64-v8a.apk` / `_armeabi-v7a.apk` / `_x86_64.apk`，先发预发布。
手机几乎都是 arm64，应用内更新也优先拿那一个。

签名固定：APK 用仓库里的一套密钥签，所以新版能直接装在旧版上。密钥不进仓库，
CI 从这四个仓库密钥里取：`ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` /
`ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`（PKCS12，别名 `carbide`）。
本地没有 `ANDROID_KEYSTORE_BASE64` 时退回 debug 签名，只影响本地随手跑的包。

证书指纹（SHA-256）：`0ab48eb8643ca144a19de1479eb5af027cc1bcbc59e03aff0009a72a07a82b35`。
发布流程每次都会打印一遍，可以拿来核对。

小改动不换版本号：删掉标签（`git tag -d vX` + 推 `:refs/tags/vX`），重打到修好的提交再推。
重推前先在网页上把同名 Release 删掉，否则 action-gh-release 会报 `already_exists`。

---

<div align="center">

<img src="https://raw.githubusercontent.com/dariondong/carbide-shell/main/assets/pet/working.png" alt="壳壳在干活" width="150" />

**小小的壳壳，陪你一起敲代码。**

</div>
