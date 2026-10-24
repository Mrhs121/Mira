# Mira.app · 原生实现说明

基于 Swift + AppKit + ImageIO + Core Animation 构建的原生 macOS 文件夹图片浏览器。

## 构建与运行

```bash
cd app
./build.sh
open build/Mira.app
```

也可以直接从命令行带路径启动：

```bash
./build/Mira.app/Contents/MacOS/Mira /path/to/image.jpg
```

## 交互说明

### 查看与浏览
- **窗口移动**：拖拽顶部标题栏空白区域可移动窗口，双击标题栏缩放窗口。
- **缩放与平移**：鼠标滚轮上下滚动（或触控板双指缩放）以指针位置为中心放大/缩小；在图片区域内单击拖拽即可直接平移图片；双击图片切换适应窗口与 100%。
- **连续看图**：`←` / `→` 或 `Space` 切换前后图片，`G` 切换网格视图，`I` 开关右侧信息面板。

### 图片标注与编辑（`⌘E`）
采用原生 macOS「预览」风格的图标化标注工具栏：
- **绘制工具**：矩形、椭圆（按住 `Shift` 正圆）、直线（按住 `Shift` 45°）、文字（`[字]`，点击画面直接内联输入，双击已有文字可二次编辑）、裁切（框选后点击浮现的「应用裁切」按钮）。
- **样式调整**：支持三横线线宽下拉选择（6 档粗细）与色井颜色面板（内置色板 + HEX 输入）；点击已有标注即可选中拖动或实时修改样式，按 `Delete` 删除选中标注。
- **导出与复制**：点「复制」或按 `⌘C` 直接将合成图写入系统剪贴板；点「保存副本…」另存为 PNG，不覆盖原图。

## 目录说明

```text
Sources/MiraCore/      ImagePipeline / FolderScanner / 元数据提取
Sources/MiraApp/       AppKit 主界面、画布与 ImageEditorViewController
Sources/MiraBench/     命令行解码基准测试
Resources/Info.plist   App Bundle 配置
build.sh               构建并签名 build/Mira.app
```
