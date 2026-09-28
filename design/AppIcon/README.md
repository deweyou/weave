# Yours App Icon

定稿为波浪顶边倒三角与独立水滴。浅色为中性白底、近黑前景；深色为系统深色底板、近白前景。Mono 使用白色前景及轻量玻璃高光，供系统生成 Clear / Tinted 外观。

## 编辑与生成

- `yours-mark.svg` 是轮廓的唯一编辑源，1024 × 1024 画布；`wave` 和 `droplet` 为独立贝塞尔路径，无字体或嵌入位图。可以直接在矢量编辑器中调整控制点、大小与位置。
- 根据 Dock 对比反馈，图形组在原定稿基础上围绕 `(512, 555)` 等比放大 15%，并上移 16 个画布单位；通过父组 transform 保留原始路径，底板与两部分比例不变。
- `AppIcon.icon` 是 Xcode 实际使用的 Icon Composer 工程。底板、平台遮罩和动态材质由 Apple 渲染；不要把 SVG 加上圆角底板后重新导入，否则会重复遮罩。
- 在 Icon Composer 中编辑材质与外观，修改轮廓则回到主 SVG。执行下列命令前保存并关闭 Icon Composer 文档，避免编辑器覆盖同步后的图层。

从仓库根目录运行：

```sh
python3 scripts/generate_app_icons.py
python3 scripts/generate_app_icons.py --check
```

生成脚本将主 SVG 同步到 `.icon/Assets/yours-mark.svg`，通过当前 Xcode 内的 Icon Composer `ictool` 导出：

- `.build/app-icons/ios-*.png`、`macos-*.png`：各平台 Default、Dark、ClearLight、ClearDark、TintedLight、TintedDark 六种 1024 px 原生渲染图。
- `.build/app-icons/Yours.iconset` 和 `Yours.icns`：Mac 标准 16 / 32 / 128 / 256 / 512 pt 的 1×、2×图片及兼容图标包。
- `.build/app-icons/preview.html`：全外观与缩小预览。
- `.build/app-icons/yours-icon-preview.svg`：带可编辑圆角底板的平面展示稿；此遮罩仅用于设计查看，不作为系统图标输入。

只同步 SVG 可用 `--sync-only`；`--check` 只核对主稿与工程图层一致性，不修改文件。生成物保留在 `.build/`，不提交。原生导出的透明外观不包含用户壁纸，实际显示会随系统背景变化。

## App 接入

Xcode 的 Yours target 在 Debug / Release 均以 `AppIcon` 为主图标名，资源阶段编译 `AppIcon.icon`，自动生成 macOS、iPhone 和 iPad 所需尺寸、图标栈及 Info.plist 记录。不同时维护另一套 AppIcon asset catalog，避免同名冲突。Swift Package 用于源码和测试，不负责 App bundle 图标；设计源放在 Package target 外，不增加运行时资源。

平台接入方式依据 [Apple Icon Composer 文档](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)。

修改后运行生成检查与 Mac / iOS 构建，并核对实际输出；发布前仍需检查 Dock / 主屏幕、不同壁纸、透明与着色模式、小尺寸和真机效果。
