# OldEmby 分阶段开发计划 (5 阶段 + CI 检查点)

> 约束: Windows 无 Mac，全部通过 GitHub Actions (`workflow_dispatch`) 验证。每个阶段结束必须在 Actions 上编译成功才进入下一阶段，不做“最后一次性集成”。

## 阶段 0 — 工程基建 (Day 0, 本次交付)

- 产出: `Makefile` / `control` / `entitlements.plist` / `Resources/Info.plist` / `Sources/main.m` / `AppDelegate.m` / `Constants.h` / `.github/workflows/build.yml` / `README` / `Docs`
- CI 检查: `make package` 产出 `Payload/OldEmby.app` + `.ipa` + `.deb`，Artifact 上传成功
- 关键决策: `ARCHS=armv7`, `TARGET=iphone:clang:9.3:6.0`, `TARGET_IPHONEOS_DEPLOYMENT_VERSION=6.0`, `ldid` 伪签名

## 阶段 1 — Hello World 跑通 (CI 检查点 1)

- 目标: 空 `UITabBarController` (视频/音乐/设置 三 tab)，纯代码 `UILabel` 居中 “OldEmby Hello iOS6”，无网络
- 验证: 在 iOS 6 模拟器/真机 (iPhone 5) 启动不崩溃，Actions 构建通过
- 文件: `AppDelegate.m` 极简, `OELibraryViewController` 仅 `UILabel`

## 阶段 2 — 网络层 + Emby 登录/浏览 (CI 检查点 2)

- 新增: `OEServerConfig`, `OEEmbyAPIClient` (NSURLConnection), `OEEmbyItem`, `OEImageCache`, `OELoginViewController`, `OELibraryViewController` 完整列表
- API: `POST /Users/AuthenticateByName`, `GET /Users/{Id}/Views`, `GET /Users/{Id}/Items` (Fields, ImageTags)
- CI 检查: 登录页可输入 host/user/pass，列表页在配置错误时弹 `UIAlertView` 而非崩溃；构建通过

## 阶段 3 — 视频播放 + 强制转码 (CI 检查点 3)

- 新增: `OETranscodeSettings`, `OETranscodeBuilder`, `OEVideoDetailViewController` + `MPMoviePlayerViewController`
- 逻辑: 默认 `PlaybackInfo` Body 强制 `VideoCodec=h264, MaxVideoBitrate=4000000, Width<=1280 Height<=720`，`TranscodingUrl` → `MPMoviePlayerViewController`
- CI 检查: 播放按钮触发 `fetchStreamURL` 流程可编译；`MPMoviePlayer` 相关废弃警告已 `-Wno-deprecated-declarations` 屏蔽
- 测试: 在 Emby Server 4.x 上验证 720p H264 流可播，服务器 Dashboard 显示 Transcoding

## 阶段 4 — 转码设置界面 + 持久化 (CI 检查点 4)

- 新增: `OESettingsViewController` (UITableViewGrouped, UISwitch/UISegmented)
- 功能: 480p/720p/1080p 切换、4 档码率 + 自定义输入、`直接播放` 开关、音频码率；`NSUserDefaults` 持久化，`OETranscodeBuilder` 读取 `sharedSettings`
- CI 检查: 设置页在 iOS 6 上 `UIAlertViewStylePlainTextInput` (iOS 5+) 可用，构建通过；切换后重新播放验证参数生效

## 阶段 5 — 音乐模块 + 后台/锁屏 (CI 检查点 5, 最终)

- 新增: `OEMusicLibraryViewController`, `OEMusicPlayerViewController`
- 功能: `Audio/MusicAlbum/MusicArtist` 浏览；`AVPlayer` 流式音频；`AVAudioSessionCategoryPlayback` + `UIBackgroundModes audio` + `MPNowPlayingInfoCenter` + `remoteControlReceivedWithEvent:` (iOS 5-9)
- 音频转码: `DeviceProfile.MusicStreamingTranscodingBitrate` + `TranscodingProfiles[AudioCodec=mp3/aac]`，默认 192kbps
- CI 检查: 音乐播放页可编译，无 `MPRemoteCommandCenter` (iOS 7.1+) 引用；全文无 `NSURLSession` 残留
- 交付: 完整 IPA + README + 本文档，Actions 全绿

---

### 通用 CI 门禁

每个阶段 PR/推送后: Actions → Run workflow → 检查 `make package` 日志无 `error:`，Artifact 中 `.ipa` 大小合理 (>500KB)，`Info.plist` 的 `MinimumOSVersion=6.0` 存在。

### 回滚策略

若某阶段 CI 失败: 复用上一阶段成功的 commit 为 base，`git revert` 或 `fixup` 后重触发 workflow，不阻塞后续阶段设计讨论。

