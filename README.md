<p align="center">
  <img src="mira-icon.png" width="112" height="112" alt="Mira Icon" />
</p>

<h1 align="center">Mira</h1>

<p align="center">
  <strong>打开文件夹，按方向键，一口气看完。</strong><br/>
  面向 macOS 的原生轻量文件夹图片浏览器 —— 不导入、不建库、80MB 大图秒开、滚轮丝滑缩放。
</p>

![Mira 预览界面](native-view.png)

---

## 核心特性

- **文件夹即图库**：打开任意一张图片或文件夹，自动串起同目录图片序列；不导入、不建数据库、不上传云端。
- **大图瞬时响应**：针对 70–80MB 高像素 JPEG / PNG 优化，采用「首帧骨架占位 → 后台适应尺寸解码 → 放大按需加载 6144px 细节 → 相邻图片预取」流水线。
- **顺手看图与手势**：
  - `←` / `→` / `Space` 连续翻页，`G` 一键切换网格与大图查看态
  - **鼠标上下滚动 / 触控板捏合**：以鼠标指针为锚点丝滑放大、缩小
  - **图片内单击拖拽**：自由平移画面；双击在「适应窗口」与「100% 实际像素」间切换
- **原生级轻量标注**：内置参考 macOS「预览」设计的顶部标注工具栏，支持矩形、椭圆、直线、内联文字、裁切、旋转、6 档线宽与色板 / HEX 取色，支持 `⌘C` 直接复制合成图粘贴至聊天软件，或另存为 PNG 副本（绝不覆盖原图）。
- **随手整理**：查看 EXIF / 色彩 / 尺寸信息面板（`I`）、重命名、移到废纸篓并支持 `⌘Z` 撤销恢复、在 Finder 中显示、系统分享。

---

## 快速开始

### 环境要求

- **系统**：macOS 14.0+（Apple Silicon）
- **工具链**：Xcode Command Line Tools（Swift 5.9+）

### 源码构建与运行

```bash
git clone git@github.com:Mrhs121/Mira.git
cd Mira/app
./build.sh
open build/Mira.app
```

也可以直接下载预构建包解压运行：[Mira-0.1.0-arm64.zip](Mira-0.1.0-arm64.zip)，或安装到 `/Applications`：

```bash
cp -R app/build/Mira.app /Applications/Mira.app
```

支持通过命令行直接打开指定图片或文件夹：

```bash
./app/build/Mira.app/Contents/MacOS/Mira /path/to/photos
```

---

## 常用快捷键

| 按键 / 操作 | 功能 |
| :--- | :--- |
| `⌘O` | 打开图片或文件夹 |
| `←` / `→` / `Space` | 上一张 / 下一张 |
| `鼠标滚轮上下` | 以指针为中心放大 / 缩小图片 |
| `画布内单击拖拽` | 平移移动图片 |
| `双击图片` / `Z` | 切换「适应窗口」与「100% 实际像素」 |
| `1` | 100% 实际像素 |
| `G` | 切换「网格浏览」与「大图查看」 |
| `I` | 显示 / 隐藏右侧信息面板 |
| `⌘E` | 打开图片标注与裁切编辑器 |
| `⌘C` | 复制当前图片（编辑态下复制带标注合成图） |
| `Delete` / `⌘Z` | 移到废纸篓 / 撤销删除 |
| `F` / `S` | 全屏 / 幻灯片播放 |

---

## 性能实测（80MB 大图）

测试环境：Apple M1 Max / 32GB / macOS

| 测试样本 | 分辨率 | 阶段 | 耗时 |
| :--- | :--- | :--- | :--- |
| 80MB PNG | 7000 × 5000 (35MP) | Fit 窗口解码 | **471–598 ms** |
| 80MB PNG | 7000 × 5000 (35MP) | 6144px 细节纹理 | **571 ms** |
| 80MB JPEG | 10000 × 7500 (75MP) | Fit 窗口解码 | **741 ms** |
| 相邻大图翻页 | 连续翻页 | 后台预取命中 | **0 ms（缓存直接命中）** |

---

## 目录结构

```text
Mira/
├── app/
│   ├── Package.swift          # SwiftPM 工程配置
│   ├── build.sh               # Release 编译与 .app 打包脚本
│   ├── Sources/
│   │   ├── MiraCore/          # 解码管线、目录扫描、图像元数据与预取缓存
│   │   ├── MiraApp/           # 原生 AppKit 界面、画布手势、网格与标注编辑器
│   │   └── MiraBench/         # 命令行大图解码基准测试工具
│   └── Resources/             # Info.plist 与应用图标资源
├── prototype/                 # 早期交互原型与示例图片资源
├── PRODUCT_DESIGN.md          # 产品设计文档
└── PERF_80MB.md               # 80MB 大图性能设计与实测规范
```

---

## License

MIT License
