# OldEmby — iOS 6-9 32位 Emby 客户端 (armv7)

> **目标**: 在 iOS 6.0 ~ 9.x 的 32位设备 (iPhone 4S/5, iPad 2/3) 上稳定运行的 Emby 客户端，纯 Objective-C + Theos 构建，无需 macOS。

## 功能总览

- **连接 Emby**: 服务器地址 + 用户名/密码登录（`POST /Users/AuthenticateByName`），`X-Emby-Authorization` 认证
- **媒体库浏览**: 影视/剧集列表，封面 + 标题 + 时长，采用 `UITableView` 手动 frame 布局（避开 iOS 6 AutoLayout 缺陷）
- **视频播放**: `MPMoviePlayerViewController`（iOS 6-9 兼容最佳），流式 HLS/MP4
- **音乐播放**: `AVPlayer` 流式音频 + `MPNowPlayingInfoCenter` 锁屏信息 + `UIBackgroundModes: audio` 后台 + `remoteControlReceivedWithEvent:` 耳机/锁屏控制
- **强制转码 (默认)**: 720p H.264 4 Mbps，通过 `POST /Items/{Id}/PlaybackInfo` 的 `DeviceProfile.TranscodingProfiles` 与 `CodecProfiles` 强制服务器转码（`VideoCodec=h264`, `MaxVideoBitrate=4000000`, `MaxWidth=1280/MaxHeight=720`）
- **手动切换**: 设置页支持 480p/720p/1080p（1080p 提示老设备解码吃力）、视频码率 1.5/2.5/4/8 Mbps 或自定义、音频码率设置、直接播放开关；全部持久化到 `NSUserDefaults`，下次启动沿用

## 目录结构

```
oldemby/
├── Makefile                      # Theos application, ARCHS=armv7, TARGET=iphone:clang:9.3:6.0
├── control                       # Debian control (越狱包元信息)
├── OldEmby.plist                 # (保留) Tweak 过滤器占位
├── Resources/
│   └── Info.plist                # CFBundleIdentifier, MinimumOSVersion 6.0, UIBackgroundModes audio
├── Sources/
│   ├── main.m
│   ├── AppDelegate.h/m           # UIWindow + UITabBarController (视频/音乐/设置), AVAudioSession
│   ├── Constants.h               # NSUserDefaults keys, 默认转码参数
│   ├── Controllers/
│   │   ├── OELoginViewController      # 服务器登录 (NSURLConnection)
│   │   ├── OELibraryViewController    # 影视列表 (UITableView, 手动 frame)
│   │   ├── OEVideoDetailViewController# 详情 + MPMoviePlayerViewController 播放
│   │   ├── OESettingsViewController   # 转码设置 (持久化)
│   │   ├── OEMusicLibraryViewController # 音乐库 (Audio/MusicAlbum/MusicArtist)
│   │   └── OEMusicPlayerViewController  # AVPlayer + MPNowPlayingInfoCenter + remoteControl
│   ├── Models/
│   │   ├── OEServerConfig             # host/token/userId 持久化
│   │   ├── OEEmbyItem                 # Emby Item 模型
│   │   └── OETranscodeSettings        # 分辨率/码率/直通开关 (NSUserDefaults)
│   ├── Services/
│   │   ├── OEEmbyAPIClient            # NSURLConnection 封装 (禁用 NSURLSession)
│   │   ├── OETranscodeBuilder         # PlaybackInfo DeviceProfile 构造
│   │   └── OEImageCache               # 内存缓存 + NSURLConnection 图片加载
│   └── Views/
│       └── OEItemCell                 # UITableViewCell 手动布局
├── .github/workflows/build.yml   # 仅 workflow_dispatch 手动触发
└── Docs/
```

### Theos 标准结构对照

- `Makefile` 遵循 `$(THEOS)/makefiles/common.mk` + `$(THEOS_MAKE_PATH)/application.mk`
- `control` 与 `OldEmby.plist` 为 Theos 打包所需
- **不携带 entitlements**：普通 GUI 应用无需任何权限；Theos 构建 `ldid -S` 纯伪签名，侧载工具 (爱思助手/AltStore/Sideloadly) 重签时整体替换签名，嵌入越狱权限 (platform-application 等) 反而会导致重签安装失败（提示"IPA 已损坏"）

## SDK 来源说明（版权合规）

项目**不内置**任何 `iPhoneOS.sdk`（Apple 版权），CI 构建时从公开社区归档**动态下载**，不提交到仓库。

| 候选 | 仓库 | 内容 | 选择理由 |
|------|------|------|----------|
| **首选 (Primary)** | [theos/sdks](https://github.com/theos/sdks) | 官方 Theos 维护的**patched SDK** (iPhoneOS 9.3 / 10.3 ... 16.5)，`tbd` 精简，含私有符号 | **Theos 官方推荐**，与 `$THEOS/sdks` 路径原生兼容，体积小 (9.3 仅 ~7MB tar.xz)，CI 下载快；`iPhoneOS9.3.sdk` 配合 `-mios-version-min=6.0` 可向下兼容 iOS 6-9，覆盖本项目区间；Release 提供 `tar.xz`，workflow 可直接 `tar -xf`。Licence: BSD-like (见仓库 LICENSE.md) |
| **备选 (Mirror)** | [xybp888/iOS-SDKs](https://github.com/xybp888/iOS-SDKs) | 社区完整 SDK 归档 (iOS 9.3 ~ 26.x, 含私有 framework 头) | 覆盖版本最全 (903★)，提供**完整未精简** SDK，适合在首选下载失败或需要验证极老 API 时回退；提供 `iPhoneOS9.3.sdk` 全量头文件，验证 `MPMoviePlayerController` 等废弃 API 可用性。Licence: MIT (见仓库) |

> **下载方式**: `build.yml` 中 `Fetch iPhoneOS SDK` 步骤优先读取 `Secrets.SDK_URL`（若你有私有 SDK 镜像），否则回退到 `https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS9.3.sdk.tar.xz`；失败再尝试备选 `xybp888`。全程 `::add-mask::` 避免日志泄露。

**署名义务**: 若使用上述公开来源，请在分发时保留其仓库链接与原 Licence。本 README 已注明来源链接。

## 构建 (GitHub Actions — 禁止本地编译)

所有编译在 **ubuntu-latest** 上完成，`workflow_dispatch` 手动触发。

### Workflow 步骤 (`.github/workflows/build.yml`)

1. **安装依赖**: `clang`, `lld`, `git`, `curl`, `perl`, `fakeroot`, `libplist-utils`, `dpkg-dev`, `xz-utils`
2. **拉取 Theos**: `git clone --recursive https://github.com/theos/theos.git $THEOS`
3. **获取 ldid**: 优先 `apt`，回退 Procursus 预编译 `ldid_linux_x86_64`，再回退源码编译
4. **获取 iPhoneOS SDK**: Secrets 感知 + 公开回退 + 多格式解压 (`tar.xz`/`tar.gz`/`zip`)，放置到 `$THEOS/sdks/`
5. **`make package`**: `ARCHS=armv7 TARGET=iphone:clang:9.3:6.0 FINALPACKAGE=1`
6. **组装 IPA**: `Payload/OldEmby.app` → `zip -r OldEmby-*.ipa`（Theos 已 `ldid -S` 纯伪签名，无 entitlements）+ Info.plist 结构自检
7. **上传 Artifact**: `OldEmby-<sha>-armv7` (含 `.ipa` 与 `.deb`, 保留 14 天)

触发: GitHub 网页 → Actions → *OldEmby Build* → Run workflow

产物: Actions → Artifacts → `OldEmby-xxxxx-armv7` → `.ipa` (AltStore/Sideloadly 侧载) 或 `.deb` (`dpkg -i` 越狱安装)

### Secrets (可选，防泄露)

- `SDK_URL`: 私有 SDK 直链（若设置则优先使用，日志自动 `add-mask`）
- `SDK_MIRROR_URL`: 镜像回退地址

> 若不设置，workflow 使用上述公开 theos/sdks 链接，无需任何 Secret 即可构建。

## 转码策略实现

- 默认 `OETranscodeSettings.defaultSettings` → 720p H.264 4 Mbps，`OETranscodeBuilder` 在 `deviceProfile` 中置空 `DirectPlayProfiles`，强制 Emby 返回 `TranscodingUrl`
- `POST /Items/{Id}/PlaybackInfo` Body 包含 `DeviceProfile.TranscodingProfiles[VideoCodec=h264, AudioCodec=aac, MaxStreamingBitrate=4000000]` 与 `CodecProfiles[Width<=1280,Height<=720]`
- 设置页修改后 `[[OETranscodeSettings sharedSettings] save]` 写入 `NSUserDefaults` (`OETranscodeResolution`, `OETranscodeBitrate`, `OETranscodeDirectPlay`, `OEAudioBitrate`)
- 直接播放开关开启时，`EnableDirectPlay=YES, EnableTranscoding=NO`, `DirectPlayProfiles` 包含 `mp4,mkv,avi,mov`

## 兼容性保证

- 网络: 仅 `NSURLConnection` (`sendAsynchronousRequest:queue:completionHandler:`)，无 `NSURLSession`
- 布局: 手动 `frame`，无 Storyboard/XIB，`UITableView` 而非 `UICollectionView` 复杂布局
- 播放: `MPMoviePlayerViewController` (iOS 2.0+)，非 `AVPlayerViewController` (iOS 8+)
- 音频后台: `AVAudioSessionCategoryPlayback` + `MPNowPlayingInfoCenter` (iOS 5+) + `remoteControlReceivedWithEvent:` (非 `MPRemoteCommandCenter` iOS 7.1+)

## 分阶段开发计划

见 `Docs/STAGE_PLAN.md` 或下方摘要。

## 本地开发 (仅编辑，无需编译)

```bash
git clone https://github.com/gmcf111/oldemby.git
# 直接编辑 Sources/，推送后在 GitHub Actions 手动触发构建
git add .
git commit -m "feat: ..."
git push origin main
```

## 许可证

代码部分 MIT；SDK 归属 Apple，CI 时下载受其原仓库 Licence 约束。

## 致谢

- [theos/theos](https://github.com/theos/theos) & [theos/sdks](https://github.com/theos/sdks)
- [xybp888/iOS-SDKs](https://github.com/xybp888/iOS-SDKs)
- Emby API 文档

