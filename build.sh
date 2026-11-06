#!/bin/bash
# OCAL 准直仪校准工具 — macOS 版构建脚本
# 产物：mac/build/OCAL.app（ad-hoc 签名，仅本机需要 Command Line Tools）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="OCAL"
BUNDLE="build/${APP_NAME}.app"
ARCH="$(uname -m)"
MIN_OS="10.15"

echo "==> 编译 (${ARCH}, macOS >= ${MIN_OS})"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
swiftc -O -swift-version 5 \
  -target "${ARCH}-apple-macos${MIN_OS}" \
  -o "${BUNDLE}/Contents/MacOS/${APP_NAME}" \
  Sources/*.swift

echo "==> 生成 Info.plist"
cat > "${BUNDLE}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>OCAL</string>
    <key>CFBundleDisplayName</key><string>OCAL 准直仪校准</string>
    <key>CFBundleExecutable</key><string>OCAL</string>
    <key>CFBundleIdentifier</key><string>com.local.ocal-calibration</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.32</string>
    <key>CFBundleVersion</key><string>132</string>
    <key>LSMinimumSystemVersion</key><string>10.15</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSCameraUsageDescription</key><string>OCAL 准直仪校准工具需要访问摄像头以显示实时画面并叠加校准图形。</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc 签名"
codesign --force --sign - "${BUNDLE}"

echo "==> 完成: $(cd "$(dirname "${BUNDLE}")" && pwd)/$(basename "${BUNDLE}")"
echo "    提示：把 OCAL.app 放到原版 ocal-win 目录（有 config*.txt 的目录）即可直接读写原配置。"
