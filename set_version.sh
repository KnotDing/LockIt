#!/bin/bash

# ==============================================================================
# 安全地更新 Xcode 项目的版本号和构建号
#
# 功能:
#   - 从最新的 Git 标签获取 Marketing Version (例如: 1.2.3)
#   - 从最新的 Git Commit 哈希获取 Build Number (例如: a1b2c3d)
#   - 使用苹果官方的 PlistBuddy 工具来安全地修改 Info.plist 文件。
#   - 这种方法不会破坏 .xcodeproj 文件，是 CI/CD 的标准实践。
# ==============================================================================

# 如果任何命令失败，立即退出脚本
set -e
set -o pipefail

# --- 配置 ---
# !!! 重要: 请确认这个路径是您项目中正确的 Info.plist 文件路径
# 根据你的项目结构，它很可能就是 "LockIt/Info.plist"
INFO_PLIST_PATH="LockIt/Info.plist"


# --- 从 Git 获取版本信息 (与你原来的脚本逻辑相同) ---

# 1. 获取最新的 git tag (例如 "v1.2.3")
TAG=$(git describe --tags --abbrev=0)

# 2. 去掉 'v' 前缀，得到版本号 (例如 "1.2.3")
VERSION=${TAG#v}

# 3. 获取简短的 commit hash 作为构建版本号
COMMIT_HASH=$(git rev-parse --short HEAD)


# --- 执行前检查 ---

echo "准备更新版本信息..."
echo "  - 目标文件: $INFO_PLIST_PATH"
echo "  - Marketing Version (版本号) -> $VERSION"
echo "  - Current Project Version (构建号) -> $COMMIT_HASH"

# 检查 Info.plist 文件是否存在
if [ ! -f "$INFO_PLIST_PATH" ]; then
    echo "错误: 在 '$INFO_PLIST_PATH' 未找到 Info.plist 文件。"
    echo "请检查并修改脚本中的 INFO_PLIST_PATH 变量。"
    exit 1
fi


# --- 使用 PlistBuddy 安全地更新版本 ---

# 1. 更新 Marketing Version (对应 Info.plist 中的 CFBundleShortVersionString)
# 这是用户在 App Store 中看到的版本，如 "1.2.3"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST_PATH"

# 2. 更新 Build Number (对应 Info.plist 中的 CFBundleVersion)
# 这是内部追踪的构建号，如 "a1b2c3d"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $COMMIT_HASH" "$INFO_PLIST_PATH"


# --- 验证结果 ---

echo "✅ 成功更新 '$INFO_PLIST_PATH'。"
echo "当前版本信息:"
echo "  - Marketing Version: $(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST_PATH")"
echo "  - Build Number:      $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST_PATH")"

