# Cithub Flutter

Cithub 的 Android-only Flutter 重构。Flutter 负责 Material 3 界面、导航和页面状态；WebVPN、教务、贴吧、系统更新、Keystore 与本机日志通过 Pigeon 强类型接口连接 Kotlin。

所有原生协议实现、固定 PB schema、Helios 和 flavor 专用验证码实现都位于仓库内独立 Flutter 插件 [`packages/cithub_native`](packages/cithub_native)，应用模块只保留 Android 启动壳与品牌资源，不依赖旧仓库或子模块。

> 当前为 `1.0.0` 发布候选开发线。只有模拟服务、自动化检查和授权账号真机验收全部通过后才会创建 `V1.0.0` 正式 Release。

## 支持范围

- Android 8.0+（API 26），包名 `com.aquasofts.cithub_flutter`
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
flutter test integration_test
flutter build apk --debug --flavor manualCaptcha --target-platform android-arm64
flutter build apk --debug --flavor autoCaptcha --target-platform android-arm64
```

Android 构建需要 JDK 17、Android SDK 35 和接受过许可的 NDK。Pigeon 生成文件必须和 [pigeons/cithub_api.dart](pigeons/cithub_api.dart) 同时提交。

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
- 完整诊断日志仅写入本机滚动文件，只有用户主动操作才导出，绝不自动上传。
- 更新器只接受比当前版本更新、属于当前 flavor 的精确文件名；Release 必须同时提供 `SHA256SUMS`，下载后校验大小、SHA-256、包名、versionName、递增 versionCode 和当前应用签名，全部通过后才打开系统安装器。
- 文章、RSS、图片和 WebView 导航只允许 HTTPS；新闻正文会先清除脚本、表单和事件属性，再由本地 WebView 按原 DOM 顺序渲染。
- 贴吧不实现应用内发帖协议。长按主楼、普通楼层或楼中楼回复后选择“回复”，应用会打开官方百度贴吧客户端；普通楼层会携带 `postId` 定位到对应楼层，未安装官方客户端时给出明确提示。
- 贴吧登录入口仅位于“我的”页，使用移动端登录页和移动 UA；主页贴吧可在设置中修改，默认显示“长春工程学院吧”。

详细发布流程见 [docs/release.md](docs/release.md)，真机清单见 [docs/device-acceptance.md](docs/device-acceptance.md)。

## 许可证

本项目采用 [GNU GPL-3.0](LICENSE)。第三方来源和修改说明见 [NOTICE.md](NOTICE.md)。
