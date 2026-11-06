# OCAL 准直仪校准工具 · macOS 版

Windows 版 `OCAL1.32.exe`（MFC + OpenCV）的原生重写。功能与原版 1:1 对应：
打开工业相机实时画面，叠加 **3 个校准圆 + 1 个可旋转准星**（各自可调启用/颜色/半径/长度/粗细/角度），
支持**圆心偏移**与**圆心标定**（focus.txt），按分辨率自动选择配置档案并保持
**config 文件与 Windows 版互通**。

## 构建与运行

```bash
cd mac
bash build.sh          # 产物：mac/build/OCAL.app（ad-hoc 签名，双击即用）
open build/OCAL.app
```

只需 Command Line Tools（swiftc），无需安装任何第三方依赖。
macOS 10.15+，Intel / Apple Silicon 均可（build.sh 自动匹配架构）。

## 配置文件（与 Windows 版兼容）

| 文件 | 说明 |
|---|---|
| `config720.txt / config1080.txt / config1k.txt / config4k.txt` | 按相机分辨率自动选择（720p/1k/1080p/4k），也可在面板手动切换 |
| `focus.txt` | 「保存圆心 / 载入圆心」按钮读写，格式 `0 0 <cx> <cy>` 与原版一致 |

配置格式：前 11 个整数与原版完全一致（圈1半径 圈1启用 圈2半径 圈2启用 圈3半径 圈3启用
准星长度 准星启用 角度 上下偏移 左右偏移），行尾额外追加 4 组 RGB 颜色（Mac 版增强，
原版按固定字段数读取，不受影响）。Mac 与 Windows 机器可直接互拷配置。

**配置目录规则（便携模式优先）**：
- 若 `OCAL.app` 同级目录存在 `config*.txt`，直接读写该目录 —— 把 `OCAL.app` 拷进原来的
  `ocal-win` 文件夹即可沿用全部原配置；
- 否则使用 `~/Library/Application Support/OCAL/`。

## 使用

1. 左上角选择相机（外接 UVC 工业相机排在最前），点「开启摄像头」；
   首次运行需在系统弹窗中允许摄像头权限。
2. 「分辨率」显示当前相机输出；档案按分辨率自动切换（如 1920×1080 → config1080）。
3. 各分组拖滑杆/点颜色块实时调整；滑杆右侧数值框可直接输入精确值。
4. 「圆心偏移」启用后所有图形整体平移（上下正值向下，左右正值向右）。
5. 「保存圆心」把当前圆心写入 focus.txt；「载入圆心」按当前分辨率换算成偏移并启用。

## 「摄像头设置」面板

macOS 的 AVFoundation 不提供 DirectShow 那种完整属性页，面板提供系统可控的项：
**格式（分辨率/帧率）、自动曝光 + 帧时长滑杆（UVC 相机的手动曝光手段）、对焦模式、白平衡模式、镜像**。
按设备实际支持情况显示（不支持的项自动隐藏）。

> 注意：部分 UVC 相机的最高分辨率格式（如 3264×2448）仅在厂商 SDK 下可见，
> AVFoundation 枚举不到时不代表相机故障。可在「格式」下拉框查看全部可用格式。

## 调试

带 `--autostart` 参数启动会自动尝试开启摄像头（首次配合系统权限弹窗使用）：

```bash
open build/OCAL.app --args --autostart
```

## 源码结构

```
Sources/
├── main.swift            入口
├── AppDelegate.swift     主窗口与业务逻辑（相机生命周期、档案切换、focus 读写）
├── CameraService.swift   AVFoundation 取流（设备枚举/格式选择/帧回调）
├── VideoView.swift       视频绘制 + 圆/准星叠加（相机像素精确缩放）
├── ControlPanel.swift    左侧控制面板（复刻原版对话框分组）
├── CameraSettings.swift  摄像头设置面板
└── OverlaySettings.swift 设置数据模型 + config/focus 读写（含格式兼容逻辑）
```
