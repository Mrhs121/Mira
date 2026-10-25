<p align="center">
  <img src="mira-icon.png" width="112" height="112" alt="Mira Icon" />
</p>

<h1 align="center">Mira</h1>

<p align="center">
  <strong>Open a folder. Hit the arrow keys. See everything.</strong>
</p>

<p align="center">
  <a href="README.md">简体中文</a> · English
</p>

<p align="center">
  <a href="https://github.com/Mrhs121/Mira/actions/workflows/build.yml"><img src="https://github.com/Mrhs121/Mira/actions/workflows/build.yml/badge.svg" alt="Build status" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B%20arm64-black" alt="macOS 14+ arm64" />
</p>

![Mira browser window](native-view.png)

Mira is a native macOS image viewer for a very small job: open a folder, press the arrow keys, and go through the whole folder without breaking stride.

No imports, no library, no cloud. Your files stay where they are; Mira just puts them on screen. Large images don't wait for a full decode. You get a quick placeholder first, detail fills in the background, and a 6144 px texture is fetched only when you zoom in. The previous and next images are warmed up while you look at the current one. Scroll or pinch to zoom around the pointer; drag to pan. It feels closer to reading a PDF than managing a photo library.

The annotation tools follow macOS Preview: rectangle, ellipse, line, text, crop, and rotate in a top toolbar. Colors and the six stroke widths take effect immediately. Text goes directly onto the image, no modal dialog. When you're done, copy the annotated image with `⌘C` or save a PNG copy. The original file is never overwritten.

Mira currently supports Apple Silicon and macOS 14 or later.

## Features

### Browsing

- Opening an image automatically picks up the other images in the same folder; use `←` / `→` / `Space` to move through them.
- `G` switches between the grid and the large view; `F` goes full screen; `S` starts a slideshow.
- Scroll the wheel or pinch on a trackpad to zoom around the pointer.
- Drag inside the image to pan; double-click to toggle between fit-to-window and 100%.
- `I` opens the info panel with EXIF, color space, and dimensions.

### Markup

Press `⌘E` to open the editor. The tools sit in the top bar: rectangle, ellipse, line, text, crop, and rotate. Draw something, then keep adjusting it: move it, change its color, change its stroke width, or press `Delete` to remove it.

- Text: choose the text tool and click an empty spot. Clicking an existing shape selects it instead of opening a text box.
- Stroke width: six options in a dropdown. The menu shows each weight as a line drawn at its real proportion.
- Color: a built-in palette plus HEX input. Mira does not use the system color picker.
- Crop: drag a crop box, then apply it. The original file stays untouched.
- Output: `⌘C` copies the annotated image, or save it as a PNG copy.

### Files

Rename, move to Trash, undo the last delete with `⌘Z`, reveal in Finder, and share through the system share sheet — all from the context menu.

## Performance

Measured on an M1 Max / 32 GB / macOS 27.2 with roughly 80 MB high-resolution images:

| Image | Resolution | Stage | Time |
| :--- | :--- | :--- | :--- |
| 80 MB PNG | 7000 × 5000 | Fit-to-window decode | 471–598 ms |
| 80 MB PNG | 7000 × 5000 | 6144 px detail pass | 571 ms |
| 80 MB JPEG | 10000 × 7500 | Fit-to-window decode | 741 ms |
| Next large image | Continuous paging | Prefetch hit | 0 ms (cache hit only) |

The first frame is a skeleton, so these numbers are time-to-usable-image, not time-to-first-pixel. The 0 ms page turn only happens when the prefetch has already finished.

## Install

### Download

Get `Mira-macos-arm64.zip` or the `.dmg` from [Releases](https://github.com/Mrhs121/Mira/releases/latest), then drag `Mira.app` into Applications.

This build is ad-hoc signed and not notarized. If macOS says it can't verify the developer, right-click `Mira.app` → Open first. If it still refuses, run:

```bash
xattr -dr com.apple.quarantine /Applications/Mira.app
```

Only do this for a build you trust.

### Build from source

You need macOS 14+, an Apple Silicon Mac, and Xcode Command Line Tools with Swift 5.9.

```bash
git clone https://github.com/Mrhs121/Mira.git
cd Mira/app
./build.sh
open build/Mira.app
```

To install it in `/Applications`:

```bash
rm -rf /Applications/Mira.app
ditto build/Mira.app /Applications/Mira.app
```

You can also open a folder or image straight from the command line:

```bash
./build/Mira.app/Contents/MacOS/Mira ~/Pictures
```

## Shortcuts

| Key / action | What it does |
| :--- | :--- |
| `⌘O` | Open an image or folder |
| `←` / `→` / `Space` | Previous / next image |
| Scroll wheel | Zoom around the pointer |
| Drag in the canvas | Pan the image |
| Double-click / `Z` | Fit to window / 100% |
| `1` | 100% actual pixels |
| `G` | Grid / large view |
| `I` | Show / hide the info panel |
| `⌘E` | Open the markup and crop editor |
| `⌘C` | Copy the current image (annotated image in the editor) |
| `Delete` / `⌘Z` | Move to Trash / undo the last delete |
| `F` / `S` | Full screen / slideshow |

In the editor, `Delete` removes the selected annotation. In the browser, it moves the file to Trash.

## Layout

```text
Mira/
├── README.md
├── README.en.md
├── LICENSE
├── app/
│   ├── README.md              # Development notes
│   ├── Package.swift
│   ├── build.sh
│   ├── Sources/
│   │   ├── MiraCore/          # Decoding, folder scan, metadata, prefetch cache
│   │   ├── MiraApp/           # AppKit UI, canvas, grid, markup editor
│   │   └── MiraBench/         # Large-image decode benchmark
│   └── Resources/             # Info.plist and app icon
├── prototype/                 # Early interaction prototype and sample images
├── PRODUCT_DESIGN.md
└── PERF_80MB.md
```

## Known limitations

- Apple Silicon only; no Intel Mac support.
- Annotation text is single-line. There is no undo/redo for markup, no layers, and no masks.
- The editor caps the working image at 8192 px on its longest edge. Very large images are saved at that working size.
- Crop must be applied before saving or copying.
- The download build is ad-hoc signed and not notarized; first launch may need the steps above.

## Development

```bash
cd app
./build.sh
```

For UI changes, run the build and include a before/after screenshot in the PR. More detailed module notes are in [app/README.md](app/README.md).

Issues and pull requests are welcome. For larger changes, open an issue first so we can agree on the direction.

## Releases

Pushes to `main` build an Actions artifact but do not touch Releases. A new Release is created only when a `v*` tag is pushed:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

## License

[MIT](LICENSE)
