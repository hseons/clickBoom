#!/usr/bin/env bash
# 从 CHANGELOG.md 提取指定版本的段落，供 GitHub Release 说明使用。
#
# 用法：scripts/changelog-notes.sh <版本号> [CHANGELOG 路径]
# 例：  scripts/changelog-notes.sh 1.5.0
set -euo pipefail

VERSION="${1:?用法: changelog-notes.sh <版本号，例如 1.5.0> [CHANGELOG 路径]}"
NOTES_FILE="${2:-CHANGELOG.md}"

if [[ ! -f "$NOTES_FILE" ]]; then
  echo "找不到 $NOTES_FILE" >&2
  exit 1
fi

awk -v version="$VERSION" '
  $0 ~ "^## \\[" version "\\]" { inside = 1; next }
  inside && /^## \[/ { exit }
  inside { print }
' "$NOTES_FILE"
