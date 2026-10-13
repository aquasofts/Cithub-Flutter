# Cithub Flutter

Cithub 的 Android / iOS Flutter 重构。Flutter 负责 Material 3 界面、导航和页面状态；WebVPN、教务、贴吧、系统更新、安全存储与本机日志通过 Pigeon 强类型接口连接 Kotlin 或 Swift。

所有原生协议实现、固定 PB schema、Helios 和 flavor 专用验证码实现都位于仓库内独立 Flutter 插件 [`packages/cithub_native`](packages/cithub_native)，应用模块只保留 Android 启动壳与品牌资源，不依赖旧仓库或子模块。

> 当前为 `1.0.0` 发布候选开发线。只有模拟服务、自动化检查和授权账号真机验收全部通过后才会创建 `V1.0.0` 正式 Release。

## 支持范围

- Android 8.0+（API 26），包名 `com.aquasofts.cithub_flutter`
- iOS 15.0+：WebVPN、教务和贴吧原生协议由 Swift 实现，凭据与 Cookie 使用 Keychain 保存
- Flutter 3.47.0 / Dart 3.13.0，Android targetSdk 35
- `autoCaptcha`：包含 ML Kit 中文文字识别并允许验证码自动续登
- `manualCaptcha`：不包含 ML Kit，不执行验证码识别或自动续登
- 两个 flavor 使用同一包名，不能彼此同时安装；可覆盖各自后续版本
- 与旧 Cithub 应用并存，不读取旧版账号、会话、设置或缓存

## 本地开发

```bash
flutter pub get
dart run pigeon --input pigeons/cithub_api.dart
flutter analyze
flutter test
swift test
flutter test integration_test
flutter build apk --debug --flavor manualCaptcha --target-platform android-arm64
flutter build apk --debug --flavor autoCaptcha --target-platform android-arm64
./tools/flutter_ios.sh build ios --simulator --debug
./tools/flutter_ios.sh test integration_test/ios_native_channel_test.dart -d <ios-simulator-id>
./tools/flutter_ios.sh test integration_test/ios_native_live_smoke_test.dart --dart-define=CITHUB_LIVE_PROTOCOL_TESTS=true -d <ios-simulator-id>
./tools/flutter_ios.sh test integration_test/app_test.dart -d <ios-simulator-id>
./tools/flutter_ios.sh test integration_test/tieba_image_viewer_test.dart -d <ios-simulator-id>
```

Android 构建需要 JDK 17、Android SDK 35 和接受过许可的 NDK。iOS 构建需要 Xcode 16+ 和 CocoaPods；仓库位于 macOS FileProvider 管理目录时，必须通过 `tools/flutter_ios.sh` 将签名产物放到系统临时目录，避免 `PhaseScriptExecution` 因扩展属性失败；脚本使用隔离配置，不会修改全局 Flutter 设置。Pigeon 生成文件必须和 [pigeons/cithub_api.dart](pigeons/cithub_api.dart) 同时提交。

## 本地课表与校园 AI

- 导航为贴吧、AI、教务、我的；公众号、校内新闻和官方新闻移入贴吧顶部。
- 我的页提供整周课表和今日列表，使用 Cithub 主题，支持本地离线查看。首次教务登录缓存当前学期；后续变化由用户选择替换或让 AI 合并。AI 导入与教务来源仅在内部记录。
- AI 直接修改手机课表，每次操作产生完整历史版本；“我的 → 菜单 → 历史版本”可预览差异和恢复。退出账号不会删除课表。
- “我的 → 设置 → AI”填写 HTTPS API 根地址（例如 `https://example.com/v1`）、API Key、模型 ID、显示名称及图片/工具能力。手机直连所配置服务，使用 `/chat/completions`，不需要新增后端。
- 支持选择任意扩展名和无扩展名文件；直接解析 UTF-8/UTF-16 文本、常见图片、PDF、DOCX、XLSX，其他二进制格式按 Base64 分块提供并标明解析范围；每次最多 5 个附件，单文件 20 MB。扫描 PDF 需要图片能力，分块文档需工具能力。会话与附件在手机保存，可主动删除。
- AI 对贴吧、公众号、校内新闻、官方新闻各默认读取最近 10 条；用户明确要求时最多各 50 条。评论按意图加载并区分普通楼层与楼中楼。贴吧请求串行、去重、缓存，至少间隔 2 秒；风控时停止，可在贴吧排序菜单中处理后重试。
- 教务工具只开放查询和本地课表修改，登录/验证码保持人工界面，不允许 AI 提交线上评教。

验收与实现边界见 [docs/campus-ai.md](docs/campus-ai.md)。

## 正式签名

项目不会生成或提交正式 keystore。构建 release 前设置：

```text
ANDROID_SIGNING_STORE_FILE
ANDROID_SIGNING_STORE_PASSWORD
ANDROID_SIGNING_KEY_ALIAS
ANDROID_SIGNING_KEY_PASSWORD
```

签名文件路径相对于 `android/`。CI 使用同名变量并从加密 Secret 还原 keystore；仓库只允许记录正式证书 SHA-256。

## 安全约束

- WebVPN 密码、教务密码和贴吧 Cookie/token 使用 Android Keystore AES-GCM 加密。
- AI API Key 使用 Android Keystore / iOS Keychain 保存；AI 运行日志完整记录密钥、输入、附件、回复、思考流和工具调用，仅保存在本机，不脱敏、不自动上传。
- 完整诊断日志持续写入本机持久文件，自动保留滚动最近 24 小时，导出前再次清理过期记录；设置中可主动导出保留范围内的完整 ZIP，不脱敏，绝不自动上传。
- 更新器只接受比当前版本更新、属于当前 flavor 的精确文件名；Release 必须同时提供 `SHA256SUMS`，下载后校验大小、SHA-256、包名、versionName、递增 versionCode 和当前应用签名，全部通过后才打开系统安装器。
- 文章、RSS、图片和 WebView 导航只允许 HTTPS；新闻正文会先清除脚本、表单和事件属性，再由本地 WebView 按原 DOM 顺序渲染。
- 贴吧不实现应用内发帖协议。长按主楼、普通楼层或楼中楼回复后选择“回复”，应用会打开官方百度贴吧客户端；普通楼层会携带 `postId` 定位到对应楼层，未安装官方客户端时给出明确提示。
- 贴吧登录入口位于“我的 → 设置 → 账号与关于”，使用移动端登录页和移动 UA；主页贴吧可在设置中修改，默认显示“长春工程学院吧”。

教务逐项核对、日志范围与验证边界见 [docs/academic-parity.md](docs/academic-parity.md)。

详细发布流程见 [docs/release.md](docs/release.md)，真机清单见 [docs/device-acceptance.md](docs/device-acceptance.md)。

## 许可证

原 Cithub 迁移代码采用 [GNU GPL-3.0](LICENSE)；RikkaHub 消息界面的 Flutter 移植采用 [AGPL-3.0-only](third_party/RikkaHub/LICENSE)，分发需保留其声明并按许可提供对应源码。第三方来源和修改说明见 [NOTICE.md](NOTICE.md)。
