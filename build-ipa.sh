#!/bin/bash
#
# 一键打包 IPA 脚本
# 用法: ./build-ipa.sh
#
# 前提:
#   1. 已安装 XcodeGen: brew install xcodegen
#   2. 在 Xcode 登录了 Apple ID (Preferences → Accounts)
#   3. 已连接过真机 (Xcode 会自动注册设备)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================"
echo "  ipaCamera IPA 打包脚本"
echo "================================================"

# 1. 安装 XcodeGen（如果没有）
if ! command -v xcodegen &> /dev/null; then
    echo "📦 安装 XcodeGen..."
    brew install xcodegen
fi

# 2. 生成 Xcode 项目
echo "🔧 生成 Xcode 项目..."
xcodegen

# 3. 询问 Team ID
read -p "请输入你的 Apple Team ID（留空则手动在 Xcode 设置）: " TEAM_ID

TEAM_ARG=""
if [ -n "$TEAM_ID" ]; then
    TEAM_ARG="DEVELOPMENT_TEAM=$TEAM_ID"
    echo "✅ 使用 Team ID: $TEAM_ID"
else
    echo "⚠️ 跳过 Team ID 设置，确保在 Xcode 中已配置"
fi

# 4. 清理旧文件
echo "🧹 清理..."
rm -rf "$SCRIPT_DIR/build"

# 5. Archive
echo "📦 编译中..."
xcodebuild clean archive \
    -project ipaCamera.xcodeproj \
    -scheme ipaCamera \
    -configuration Release \
    -archivePath "$SCRIPT_DIR/build/ipaCamera.xcarchive" \
    -allowProvisioningUpdates \
    $TEAM_ARG

echo "✅ Archive 完成"

# 6. 导出 IPA
echo "📱 导出 IPA..."
xcodebuild -exportArchive \
    -archivePath "$SCRIPT_DIR/build/ipaCamera.xcarchive" \
    -exportPath "$SCRIPT_DIR/build" \
    -exportOptionsPlist "$SCRIPT_DIR/ExportOptions.plist" \
    -allowProvisioningUpdates \
    $TEAM_ARG

echo "================================================"
echo "  ✅ IPA 导出成功！"
echo "================================================"
echo "📁 位置: $SCRIPT_DIR/build/"
ls -lh "$SCRIPT_DIR/build/"*.ipa 2>/dev/null
echo ""
echo "💡 安装方式："
echo "   1. 打开 Xcode → Window → Devices and Simulators"
echo "   2. 选中你的 iPhone"
echo "   3. 把 .ipa 文件拖进去"
echo "================================================"
