# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目与兼容性边界

OldEmby 是面向 iOS 6.0–9.x、32 位 armv7 设备的 Emby 客户端。代码使用 ARC 的 Objective-C 和 Theos；编译目标固定为 `iphone:clang:9.3:6.0`。不要将较新 iOS API 引入应用：

- 网络层只用 `NSURLConnection`，不能使用 `NSURLSession`。
- UI 用纯代码和手动 `frame` / `UITableView`；不要引入 Storyboard、XIB、Auto Layout 或 `UICollectionView`。
- 视频播放使用 `MPMoviePlayerViewController`，不可改为 `AVPlayerViewController`。
- 后台音频使用 `AVAudioSessionCategoryPlayback`、`MPNowPlayingInfoCenter` 与 `remoteControlReceivedWithEvent:`；不要使用 `MPRemoteCommandCenter`。
- 9.3 SDK 会为 iOS 6 不存在的 re-export 生成错误 dyld 绑定。CI 中的 `tools/fix_ios6_bindings.py` 和其后的 `ldid -S` 是启动兼容性所必需的，不能删除或跳过。
- 产物不得携带 entitlements；侧载工具需要能以个人证书重新签名。

## 构建与验证

本仓库没有本地测试框架、lint 任务或可单独运行的测试。Windows 开发环境只编辑源码；不要在本地执行 `make`。唯一受支持的构建验证是在 GitHub Actions 的 **OldEmby Build** workflow 中完成：它下载 Theos、iOS 工具链和 SDK，执行 `make package`，修补 iOS 6 dyld 绑定，并生成 `.ipa` 与 `.deb`。

常用命令（需已认证的 GitHub CLI）：

```bash
# 触发 release 构建
gh workflow run build.yml -f build_type=release

# 触发 debug 构建
gh workflow run build.yml -f build_type=debug

# 查看最近的构建并跟踪某次运行
gh run list --workflow build.yml
gh run watch <run-id>
```

也可在 GitHub 网页中通过 Actions → **OldEmby Build** → Run workflow 手动触发。构建 Artifact 名为 `OldEmby-<sha>-armv7`，含 IPA 和 Debian 包；保留 14 天。

新增或删除 Objective-C 实现文件时，必须同步更新 `Makefile` 的显式 `OldEmby_FILES` 列表；Theos 在此项目中不使用通配符搜集源文件。图标 PNG 由 CI 从 `Resources/icon.svg` 使用 `tools/gen_icons.py` 生成，不应提交。SDK 也只在 CI 中获取，不应入库。

## 架构

- `Sources/main.m` 启动 `AppDelegate`。`AppDelegate` 配置后台音频、创建三个导航栈（影视、音乐、设置），并在没有保存的 host/token 时展示登录页。
- `Sources/Controllers/` 是 UIKit 展示与导航层：影视库按目录/剧集/详情逐层浏览；音乐库选择音频后交给全局播放管理器；`OERootTabBarController` 负责音乐 Tab 中的迷你播放器和全屏播放器切换。
- `Sources/Models/` 保存领域与持久化状态：`OEEmbyItem` 将 Emby JSON 映射为显示/导航模型；`OEServerConfig` 持久化服务器、用户和 token；`OETranscodeSettings` 持久化清晰度、音视频码率和直播放开关。默认策略为关闭直播放、720p H.264、4 Mbps 视频、192 kbps 音频。
- `Sources/Services/OEEmbyAPIClient` 是所有 Emby HTTP 请求的唯一入口，负责认证、分页媒体查询、`PlaybackInfo` 与播放 URL。所有回调运行于主队列；请求和播放流程的改动应保留其现有错误处理与 URL 编码逻辑。
- `OETranscodeBuilder` 将 `OETranscodeSettings` 转换为 `POST /Items/{Id}/PlaybackInfo` 的 DeviceProfile，并从响应选择转码或直流 URL。强制转码模式必须保持禁用 direct play/direct stream，确保服务器实际转为设备可解码的流。
- `OEMusicPlaybackManager` 是全局单例，持有播放列表和 `AVPlayer`，通过 `Constants.h` 中的通知同步音乐页、迷你播放器和锁屏信息。注意其 `generation` 检查和 KVO/通知清理，避免异步回调覆盖当前曲目或留下观察者。
- `Sources/Views/` 集中可复用的手工布局单元、主题、图标和迷你播放器；颜色和应用级 appearance 应经 `OETheme` 管理。

## 打包链路

`.github/workflows/build.yml` 是构建行为的权威来源。它先用 `tools/patch_sdk_tbd.py` 修复 Theos SDK stub，再构建 armv7 app，解析实际的 `OldEmby.app` 路径（release/debug 不同），对同一二进制运行 `tools/fix_ios6_bindings.py` 并重签，然后组装 IPA。更改构建、SDK 或打包相关文件时，须保留这些顺序依赖和 IPA 的 `Info.plist`、图标、Mach-O、无 entitlements 校验。
