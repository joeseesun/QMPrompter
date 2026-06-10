# QMPrompter / 乔木提词器

QMPrompter is a small, personal iOS teleprompter app for speaking to camera. It keeps the script on screen, uses the front camera as a live preview background, and can follow your speech so the current line stays near a comfortable reading position.

乔木提词器是一款自用 iOS 提词器。它把文稿显示在摄像头预览之上，适合对着镜头练习表达、录制口播或直播前试讲。当前版本专注于提词和预览，不录制视频。

> Status: early self-use version. The app is usable on a real iPhone, but it is not an App Store product yet.
>
> 状态：早期自用版本。真机可用，但还不是 App Store 发布版。

## Highlights / 功能亮点

- Script library: create, edit, save, search, and delete scripts.
- Manual input and AI-assisted script generation.
- AI providers: DeepSeek, OpenAI-compatible APIs, and Claude/Anthropic-compatible APIs.
- Custom Base URL and model selection, with quick model presets and custom model names.
- Remote model discovery from compatible `/models` endpoints, with searchable model selection.
- Large voice input button for AI prompt dictation.
- Front camera live preview behind the script.
- Full-screen teleprompter with speech-following mode by default.
- Speed mode with play, pause, rewind, forward, reset, and progress controls.
- Manual vertical dragging to adjust the reading position.
- Font size, scroll speed, text color, and camera transparency settings.
- Liquid Glass-inspired black/white/gray interface.
- Local script storage. API keys are stored in Keychain.

- 文稿库：新建、编辑、保存、搜索、删除。
- 支持手动输入和 AI 生成口播文稿。
- AI 服务支持 DeepSeek、OpenAI 兼容接口、Claude/Anthropic 兼容接口。
- 支持自定义 Base URL、模型下拉选择和自定义模型名。
- 支持从兼容 `/models` 接口拉取服务器模型，并在可搜索列表中选择。
- AI 生成页支持底部大圆形语音输入。
- 前置摄像头实时预览作为提词背景。
- 全屏提词界面默认使用语音跟随模式。
- 速度模式支持播放、暂停、前进、后退、重置和进度控制。
- 支持手动上下拖动文本位置。
- 支持字号、速度、文字颜色、摄像头透明度设置。
- 黑白灰 Liquid Glass 风格界面。
- 文稿本地存储，API Key 存入 Keychain。

## Requirements / 环境要求

- macOS with Xcode installed.
- iPhone running iOS 17.0 or later.
- Apple ID for free local signing, or an Apple Developer Program account for longer-lived signing and distribution.
- Camera, microphone, and speech recognition permissions on the device.

- 需要一台安装了 Xcode 的 Mac。
- 需要 iOS 17.0 或更高版本的 iPhone。
- 免费本地签名需要 Apple ID；付费 Apple Developer Program 账号只在长期签名、TestFlight 或 App Store 分发时需要。
- 真机需要开启摄像头、麦克风和语音识别权限。

Project settings:

```text
Xcode project: QMPrompter.xcodeproj
Target: QMPrompter
Bundle ID: com.qiaomu.Prompter
iOS deployment target: 17.0
```

## Install on iPhone / 真机安装

### Option A: You do not have a paid developer account

You can still install the app on your own iPhone with a free Apple ID.

1. Install Xcode from the Mac App Store or Apple Developer website.
2. Open `QMPrompter.xcodeproj` in Xcode.
3. In Xcode, open `Settings > Accounts` and sign in with your Apple ID.
4. Select the `QMPrompter` target, then open `Signing & Capabilities`.
5. Choose your Personal Team.
6. If Xcode reports a bundle identifier conflict, change `com.qiaomu.Prompter` to a unique value, for example `com.yourname.Prompter`.
7. Connect your iPhone with USB or enable wireless debugging.
8. Select your iPhone as the run destination.
9. Click Run.
10. On the iPhone, trust the developer profile if prompted:
    `Settings > General > VPN & Device Management > Developer App > Trust`.

Important limits of free signing:

- The app is for your own devices only.
- The app normally needs to be rebuilt/reinstalled after about 7 days.
- You cannot publish to TestFlight or the App Store without a paid Apple Developer Program account.
- If the Home Screen icon does not refresh after reinstalling, restarting the iPhone usually fixes SpringBoard cache. Developers can also try posting SpringBoard/LaunchServices Darwin notifications through `devicectl`.

### 方式 A：没有付费开发者账号

没有付费 Apple Developer Program 账号也可以安装到自己的 iPhone。你只需要一个普通 Apple ID，用 Xcode 免费签名。

1. 安装 Xcode。
2. 用 Xcode 打开 `QMPrompter.xcodeproj`。
3. 在 `Settings > Accounts` 登录你的 Apple ID。
4. 选中 `QMPrompter` target，进入 `Signing & Capabilities`。
5. Team 选择你的 Personal Team。
6. 如果 Xcode 提示 Bundle ID 冲突，把 `com.qiaomu.Prompter` 改成你自己的唯一 ID，例如 `com.yourname.Prompter`。
7. 连接 iPhone，或开启无线调试。
8. 运行目标选择你的 iPhone。
9. 点击 Run。
10. 如果手机提示需要信任开发者，在 iPhone 上进入：
    `设置 > 通用 > VPN 与设备管理 > 开发者 App > 信任`。

免费签名限制：

- 只能用于自己的设备。
- App 通常约 7 天后需要重新构建/安装。
- 不能用于 TestFlight 或 App Store 发布。
- 如果覆盖安装后桌面图标没有刷新，通常是 SpringBoard 缓存；重启手机可解决。开发者也可以用 `devicectl` 发送 SpringBoard/LaunchServices Darwin notification 尝试刷新。

### Option B: You have a paid Apple Developer Program account

Use the same Xcode flow, but choose your paid team in `Signing & Capabilities`. Paid signing is suitable for TestFlight, App Store distribution, or longer-lived internal testing builds.

### 方式 B：有付费开发者账号

流程和免费安装基本一样，只是在 `Signing & Capabilities` 中选择你的付费开发者 Team。付费账号适合 TestFlight、App Store 或更稳定的内测分发。

### Option C: You have no Apple ID at all

You cannot sign and install an iOS app from source without some signing identity. Ask someone with Xcode and an Apple ID to build it for your device, or wait for a TestFlight/App Store build from a developer account.

### 方式 C：完全没有 Apple ID

完全没有 Apple ID 时，无法自行从源码签名安装 iOS App。你需要让有 Apple ID 和 Xcode 的人帮你构建到你的设备，或者等待开发者提供 TestFlight/App Store 版本。

## Build from CLI / 命令行构建

Generic build:

```bash
xcodebuild \
  -project QMPrompter.xcodeproj \
  -scheme QMPrompter \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  build
```

Build for a connected device:

```bash
xcrun devicectl list devices

xcodebuild \
  -project QMPrompter.xcodeproj \
  -scheme QMPrompter \
  -configuration Debug \
  -destination 'id=<DEVICE_ID>' \
  -derivedDataPath build/DerivedData \
  build
```

Install and launch:

```bash
xcrun devicectl device install app \
  --device <DEVICE_ID> \
  build/DerivedData/Build/Products/Debug-iphoneos/QMPrompter.app

xcrun devicectl device process launch \
  --device <DEVICE_ID> \
  --terminate-existing \
  com.qiaomu.Prompter
```

Optional icon/cache refresh after reinstall:

```bash
xcrun devicectl device notification post \
  --device <DEVICE_ID> \
  --name com.apple.mobile.application_installed \
  --name com.apple.LaunchServices.applicationRegistered \
  --name com.apple.springboard.applicationStateChanged \
  --name com.apple.SpringBoard.IconStateChanged
```

## AI Setup / AI 配置

Open the app, go to Settings, and configure:

- AI service: DeepSeek, OpenAI-compatible, or Claude-compatible.
- API Key: stored locally in Keychain.
- Base URL: useful for official APIs or third-party gateways.
- Model: choose from quick presets or enter a custom model name.
- Remote models: tap refresh next to the model field to load models from the configured provider, then search and select one.

打开 App 后进入设置页，可配置：

- AI 服务：DeepSeek、OpenAI 兼容、Claude 兼容。
- API Key：本地存入 Keychain。
- Base URL：可填写官方接口或第三方中转地址。
- 模型：可从预设模型下拉选择，也可以填写自定义模型名。
- 远程模型：点击模型字段旁边的刷新按钮，可从当前服务端拉取模型列表，再搜索选择。

Do not hard-code API keys in the project. Do not commit API keys to GitHub.

不要把 API Key 写进源码，也不要提交到 GitHub。

## Privacy / 隐私说明

- The app does not record video.
- Camera permission is used only for the live preview background.
- Microphone and speech recognition permissions are used for speech-following and voice input.
- Local scripts are stored on device as app data.
- AI prompts are sent to the selected AI provider only when you use AI generation.
- API keys are stored in iOS Keychain.

- App 不录制视频。
- 摄像头权限仅用于实时预览背景。
- 麦克风和语音识别权限用于语音跟随和语音输入。
- 文稿存储在本机 App 数据中。
- 只有使用 AI 生成功能时，提示词才会发送给你选择的 AI 服务。
- API Key 存储在 iOS Keychain。

## Troubleshooting / 常见问题

### Xcode says the bundle identifier is unavailable

Change the Bundle Identifier in `Signing & Capabilities` to a unique value. A reverse-DNS style value is recommended, for example `com.yourname.Prompter`.

### Xcode 提示 Bundle Identifier 不可用

在 `Signing & Capabilities` 里改成你自己的唯一 Bundle ID，例如 `com.yourname.Prompter`。

### The app installs but cannot open on iPhone

Trust the developer profile on the device:
`Settings > General > VPN & Device Management > Developer App > Trust`.

### App 安装后打不开

在 iPhone 上信任开发者：
`设置 > 通用 > VPN 与设备管理 > 开发者 App > 信任`。

### The Home Screen icon does not update

iOS may cache SpringBoard icons after sideloaded installs. Try reinstalling, posting the Darwin notifications shown above, or restarting the device.

### 桌面图标没有更新

iOS 可能缓存侧载 App 的 SpringBoard 图标。可以尝试重新安装、发送上面的 Darwin notification，或重启手机。

### Speech following does not work

Check microphone and speech recognition permissions. Also make sure the device language and the spoken script language are close enough for iOS speech recognition.

### 语音跟随不工作

检查麦克风和语音识别权限，并确认朗读语言和系统识别语言接近。

## Roadmap / 后续方向

- Better speech-following accuracy and smoother scroll behavior.
- More polished Liquid Glass controls for the teleprompter screen.
- More export/import options for scripts.
- TestFlight/App Store packaging if the project moves beyond self-use.

- 优化语音跟随准确率和滚动丝滑度。
- 继续打磨提词界面的 Liquid Glass 控制组件。
- 增加文稿导入/导出能力。
- 如果从自用走向公开产品，再补 TestFlight/App Store 分发。

## License / 许可证

No license file has been added yet. If you plan to reuse or redistribute the code, add an explicit open-source license first.

当前仓库还没有添加许可证文件。如果你计划复用或再分发代码，请先补充明确的开源许可证。
