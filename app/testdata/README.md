# 80MB 测试图

这两张图是**专门生成的最坏情况样本**：

| 文件 | 尺寸 | 特点 |
|---|---|---|
| `80mb.jpg` | 10000 × 7500（75MP） | 高频细节，**没有内嵌缩略图** |
| `80mb.png` | 7000 × 5000（35MP） | 高频细节，无损，**没有内嵌预览** |

真实相机 JPEG 通常有内嵌缩略图，第一帧会更快；这两张用来验证“最差路径”。

## 基准

```bash
cd app
swift run -c release mira-bench testdata/80mb.jpg 2023
swift run -c release mira-bench testdata/80mb.png 2023
```

如果磁盘紧张，可以直接删掉这两个文件；App 不依赖它们。
