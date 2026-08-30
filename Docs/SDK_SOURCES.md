# SDK 来源候选清单

## 候选 1 — theos/sdks (首选)

- **URL**: https://github.com/theos/sdks
- **Release 直链 (CI 使用)**: https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS9.3.sdk.tar.xz
- **内容**: Patched SDKs (iPhoneOS 9.3/10.3/11.4/12.4/13.7/14.5/15.6/16.5 + AppleTVOS)，`tbd` 格式，含私有符号，体积小
- **许可证**: 仓库 LICENSE.md (BSD-like, 需保留署名)
- **选择理由**:
  - Theos 官方维护，与 `$THEOS/sdks` 预期路径完全一致，文档直接给出 `copy into $THEOS/sdks/` 流程
  - iPhoneOS 9.3 SDK 配合 `-mios-version-min=6.0` 可覆盖 iOS 6-9，且 9.3 是最后一个支持 32位 armv7 的较新 SDK，API 覆盖度与老设备兼容性平衡最佳
  - Release 提供 `tar.xz`，CI 可 `curl -L | tar -xf` 一步完成，无需处理 Xcode 内部 `Platforms/iPhoneOS.platform` 提取
  - 社区验证充分 (691★, 被 theos/theos Wiki 直接引用)

## 候选 2 — xybp888/iOS-SDKs (备选/镜像)

- **URL**: https://github.com/xybp888/iOS-SDKs
- **内容**: 完整 Apple SDK 原样归档 (iOS 9.3 ~ 26.x)，含完整 Framework 头与私有头，未精简
- **许可证**: MIT (仓库 README 注明)
- **选择理由**:
  - 版本最全 (903★)，提供与首选同版本的 `iPhoneOS9.3.sdk` 全量头，可用于对照验证 `MPMoviePlayerController` 等废弃 API 在 patched SDK 中是否缺头
  - 若 `theos/sdks` Release 因网络/限流失败，可作为 `SDK_FALLBACK_MIRROR` (master.tar.gz) 回退，workflow 中已实现 `tar -xzf` 后 `cp -R iPhoneOS9.3.sdk $THEOS/sdks/`
  - 适合需要在同一 CI 中对比多版本 SDK (9.3 vs 10.3) 的场景

## 未选候选 (记录)

| 来源 | 原因 |
|------|------|
| Apple 官方 Xcode dmg 中提取 | 需要 macOS + Apple Developer 账号 + 大体积 dmg ( > 5GB )，不符合 Windows CI 约束 |
| iOS-SDKs 社区其他 fork (如 Superbil) | 久未维护，最后更新多为 iOS 10-11，不如 xybp888 新 |
| 自建 SDK (从 IPSW 提取) | 法务与构建复杂度高，无必要 |

## CI 使用方式

```yaml
SDK_FALLBACK_URL: "https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS9.3.sdk.tar.xz"
# workflow 会: curl -L $SDK_URL (或 Secret) -o /tmp/sdk.tar.xz && tar -xf -C $THEOS/sdks
```

> 版权: SDK 本身归 Apple 所有，以上归档仅为社区为越狱开发提供的**下载便利**，请遵守 Apple SDK 许可，仅用于兼容性构建，不二次分发 SDK 文件。
