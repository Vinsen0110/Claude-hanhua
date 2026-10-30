#!/bin/bash
# Claude 桌面版一键汉化（macOS）
#
# 从 GitHub 下载 javaht/claude-desktop-zh-cn 的最新版补丁，给 /Applications/Claude.app 装上中文界面。
# 补丁会先把原版备份为 /Applications/Claude.backup-before-zh-CN-日期.app，随时可以恢复。
#
# 用法：
#   双击运行                                安装简体中文；已汉化过时会询问重装还是恢复英文
#   bash Claude一键汉化.command --restore   恢复英文原版
#   bash Claude一键汉化.command --lang zh-TW   繁体中文（台湾）；zh-HK 为繁体中文（香港）
#   bash Claude一键汉化.command --dry-run   只在临时副本上试运行，不改动已安装的 Claude
#   bash Claude一键汉化.command --from 路径  使用已下载的补丁包（文件夹或 .tar.gz），不联网下载
#   bash Claude一键汉化.command --version 1.4.19   指定补丁版本，默认用最新版

set -u -o pipefail

REPO="javaht/claude-desktop-zh-cn"
APP="/Applications/Claude.app"
BACKUP_GLOB="/Applications/Claude.backup-before-zh-CN-*.app"
PYTHON="/usr/bin/python3"
MIN_FREE_GB=2

LANG_CODE="zh-CN"
MODE=""
DRY_RUN=0
FROM=""
VERSION=""
WORK=""
USED_SUDO=0

usage() {
  cat <<'EOF'
用法：
  双击运行                     安装简体中文；已汉化过时会询问重装还是恢复英文
  --restore                    恢复英文原版
  --lang zh-CN|zh-TW|zh-HK     简体中文 / 繁体中文（台湾）/ 繁体中文（香港）
  --dry-run                    只在临时副本上试运行，不改动已安装的 Claude
  --from 路径                  使用已下载的补丁包（文件夹或 .tar.gz），不联网下载
  --version 版本号             指定补丁版本，默认用最新版
EOF
}

# 双击运行和 curl | bash 两种方式下都从键盘读输入
ask() {
  local answer=""
  if (: </dev/tty) 2>/dev/null; then
    read -rp "$1" answer </dev/tty || true
  fi
  printf '%s' "$answer"
}

finish() {
  echo
  ask "按回车键关闭窗口。" >/dev/null
  exit "$1"
}

die() {
  echo
  echo "❌ $*"
  finish 1
}

cleanup() {
  [ -n "$WORK" ] && [ -d "$WORK" ] || return 0
  # 补丁以管理员身份运行，临时目录里可能留有 root 的文件
  if [ "$USED_SUDO" -eq 1 ]; then
    sudo -n rm -rf "$WORK" 2>/dev/null || rm -rf "$WORK" 2>/dev/null
  else
    rm -rf "$WORK" 2>/dev/null
  fi
}
trap cleanup EXIT
trap 'echo; echo "已中断。"; exit 130' INT TERM

need_value() {
  [ -n "${2:-}" ] || { echo "参数 $1 后面要跟一个值。"; usage; exit 2; }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --restore) MODE="restore"; shift ;;
    --install) MODE="install"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --lang) need_value "$1" "${2:-}"; LANG_CODE="$2"; shift 2 ;;
    --lang=*) LANG_CODE="${1#*=}"; shift ;;
    --from) need_value "$1" "${2:-}"; FROM="$2"; shift 2 ;;
    --from=*) FROM="${1#*=}"; shift ;;
    --version) need_value "$1" "${2:-}"; VERSION="$2"; shift 2 ;;
    --version=*) VERSION="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数：$1"; usage; exit 2 ;;
  esac
done

case "$LANG_CODE" in
  zh-CN) LABEL="简体中文" ;;
  zh-TW) LABEL="繁體中文（台灣）" ;;
  zh-HK) LABEL="繁體中文（香港）" ;;
  *) echo "不支持的语言：${LANG_CODE}（可选 zh-CN、zh-TW、zh-HK）"; exit 2 ;;
esac

# 不用 grep -q：它提前退出会让 codesign 收到 SIGPIPE，在 pipefail 下误判为失败
is_patched() { codesign -dv "$APP" 2>&1 | grep 'Signature=adhoc' >/dev/null; }
has_backup() { compgen -G "$BACKUP_GLOB" >/dev/null; }
free_gb() { df -Pk "$1" 2>/dev/null | awk 'NR == 2 { print int($4 / 1024 / 1024) }'; }

echo "======================================"
echo "   Claude 桌面版一键汉化（macOS）"
echo "======================================"
[ "$DRY_RUN" -eq 1 ] && echo "【试运行】只在临时副本上操作，不会改动已安装的 Claude。"
echo

# ---------- 环境检查 ----------
[ "$(uname -s)" = "Darwin" ] || die "这个脚本只能在 macOS 上运行。"
[ -d "$APP" ] || die "没找到 ${APP}。
请先从 https://claude.ai/download 安装 Claude 桌面版，再运行本脚本。"

if ! "$PYTHON" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
  die "这台 Mac 还没装“命令行开发者工具”（补丁要用系统自带的 Python 3）。
系统应该已经弹出安装窗口；如果没有，打开“终端”运行：xcode-select --install
装好后再运行本脚本。"
fi

for dir in /Applications "${TMPDIR:-/tmp}"; do
  gb="$(free_gb "$dir")"
  if [ -n "$gb" ] && [ "$gb" -lt "$MIN_FREE_GB" ]; then
    die "磁盘剩余空间只有 ${gb} GB，至少需要 ${MIN_FREE_GB} GB（要临时复制一份 Claude）。"
  fi
done

APP_VERSION="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo 未知)"
echo "Claude 版本：$APP_VERSION"

# ---------- 选择操作 ----------
if [ -z "$MODE" ]; then
  if is_patched; then
    echo "这台 Mac 上的 Claude 已经装过中文补丁。"
    echo "  [1] 重新安装中文补丁（补丁有新版、或汉化不完整时用）"
    echo "  [2] 恢复英文原版"
    echo "  [3] 退出"
    choice="$(ask "请输入 1、2 或 3（直接回车 = 1）：")"
    case "${choice:-1}" in
      1) MODE="install" ;;
      2) MODE="restore" ;;
      *) echo "已退出，没有做任何改动。"; finish 0 ;;
    esac
  else
    MODE="install"
    has_backup && echo "Claude 更新后汉化失效了，现在重新安装。"
  fi
fi

if [ "$MODE" = "restore" ] && ! has_backup; then
  die "没找到原版备份（${BACKUP_GLOB}），无法自动恢复。
可以从 https://claude.ai/download 重新下载官方版，拖进“应用程序”覆盖即可。"
fi

# ---------- 确认并获取管理员权限 ----------
if [ "$DRY_RUN" -eq 0 ]; then
  echo
  if [ "$MODE" = "install" ]; then
    echo "接下来会：退出 Claude → 备份原版 → 安装${LABEL}补丁 → 重新打开 Claude，大约 2～3 分钟。"
  else
    echo "接下来会：退出 Claude → 用备份恢复英文原版 → 重新打开 Claude。"
  fi
  echo "请先保存 Claude 里正在进行的工作。"
  answer="$(ask "按回车开始，输入 n 取消：")"
  case "$answer" in
    n|N|no|NO) echo "已取消，没有做任何改动。"; finish 0 ;;
  esac
  echo
  echo "需要管理员权限来替换 /Applications/Claude.app。"
  echo "请输入这台 Mac 的开机密码（输入时屏幕上不显示，输完按回车）："
  sudo -v || die "没有拿到管理员权限，已取消，没有做任何改动。"
  USED_SUDO=1
fi

# ---------- 准备补丁 ----------
WORK="$(mktemp -d -t claude-zh-cn)" || die "无法创建临时目录。"
mkdir -p "$WORK/tmp"

if [ -n "$FROM" ]; then
  if [ -d "$FROM" ]; then
    SRC="$(cd "$FROM" && pwd)"
  elif [ -f "$FROM" ]; then
    SRC="$WORK/patch"
    mkdir -p "$SRC"
    tar -xzf "$FROM" -C "$SRC" --strip-components 1 || die "解压 $FROM 失败，请确认它是补丁的 .tar.gz 源码包。"
  else
    die "找不到 ${FROM}。"
  fi
  echo "使用本地补丁包：$FROM"
else
  if [ -z "$VERSION" ]; then
    echo "正在查询补丁最新版本…"
    latest_url="$(curl -fsSIL -o /dev/null -w '%{url_effective}' --connect-timeout 15 --max-time 30 \
      "https://github.com/$REPO/releases/latest" 2>/dev/null || true)"
    VERSION="${latest_url##*/}"
  fi
  if ! [[ "$VERSION" =~ ^[0-9A-Za-z._-]+$ ]] || [ "$VERSION" = "latest" ]; then
    die "连不上 GitHub，查不到补丁版本。
请确认能打开 https://github.com/$REPO （国内网络可能需要开代理），然后重新运行。"
  fi
  url="https://github.com/$REPO/archive/refs/tags/$VERSION.tar.gz"
  echo "正在下载补丁 ${VERSION}…"
  if ! curl -fL# --retry 3 --connect-timeout 20 --max-time 600 -o "$WORK/patch.tar.gz" "$url"; then
    die "下载失败。请确认能打开 github.com（国内网络可能需要开代理）。
也可以先用浏览器下载 $url
再运行：bash \"$0\" --from 下载好的文件路径"
  fi
  echo "补丁包 SHA-256：$(shasum -a 256 "$WORK/patch.tar.gz" | awk '{ print $1 }')"
  SRC="$WORK/patch"
  mkdir -p "$SRC"
  tar -xzf "$WORK/patch.tar.gz" -C "$SRC" --strip-components 1 || die "解压补丁包失败。"
fi

PATCHER="$SRC/scripts/patch_claude_zh_cn.py"
[ -f "$PATCHER" ] || die "补丁包里没有 scripts/patch_claude_zh_cn.py，可能不是 $REPO 的补丁包。"
patcher_help="$("$PYTHON" -I "$PATCHER" --help 2>&1)"
for flag in --user-home --lang --dry-run --restore --restore-if-backup-exists; do
  grep -q -- "$flag" <<<"$patcher_help" || die "这个版本的补丁不支持 $flag 参数，本脚本需要更新。"
done

run_patcher() {
  local args=(--user-home "$HOME" "$@")
  [ "$DRY_RUN" -eq 1 ] && args+=(--dry-run)
  # TMPDIR 指到本脚本的临时目录，补丁的临时副本会随它一起清理
  if [ "$DRY_RUN" -eq 1 ]; then
    /usr/bin/env TMPDIR="$WORK/tmp/" "$PYTHON" -I "$PATCHER" "${args[@]}"
  else
    sudo /usr/bin/env TMPDIR="$WORK/tmp/" "$PYTHON" -I "$PATCHER" "${args[@]}"
  fi
}

patch_failed() {
  echo
  echo "❌ 补丁没有执行成功，详细原因见上面的输出。"
  echo "如果提示“终端”无法修改 App（Operation not permitted），请打开"
  echo "系统设置 → 隐私与安全性 → App 管理，允许“终端”，然后重新运行本脚本。"
  if [ "$DRY_RUN" -eq 0 ]; then
    if [ -d "$APP" ]; then
      open -a "$APP" 2>/dev/null || true
    elif has_backup; then
      echo "Claude.app 不在“应用程序”里了，原版备份还在：$(compgen -G "$BACKUP_GLOB" | tail -n 1)"
      echo "重新运行本脚本并选择“恢复英文原版”即可恢复。"
    fi
  fi
  finish 1
}

# ---------- 执行 ----------
echo
if [ "$MODE" = "install" ]; then
  echo "▶ 第 1 步：清理旧版补丁（没有就跳过）"
  run_patcher --restore-if-backup-exists || patch_failed
  echo
  echo "▶ 第 2 步：安装${LABEL}补丁"
  run_patcher --lang "$LANG_CODE" || patch_failed
else
  # 旧版补丁装过常驻的 frida 进程，恢复时一并清掉
  plist="$HOME/Library/LaunchAgents/com.claude-desktop-zh-cn.frida-zh.plist"
  if [ -f "$plist" ] && [ "$DRY_RUN" -eq 0 ]; then
    launchctl bootout "gui/$(id -u)/com.claude-desktop-zh-cn.frida-zh" 2>/dev/null || true
    rm -f "$plist"
    rm -rf "$HOME/.claude-zh"
    echo "已清理旧版补丁留下的常驻进程。"
  fi
  echo "▶ 恢复英文原版"
  run_patcher --restore || patch_failed
fi

echo
if [ "$DRY_RUN" -eq 1 ]; then
  if [ "$MODE" = "install" ]; then
    echo "✅ 试运行通过：补丁兼容这台 Mac 上的 Claude ${APP_VERSION}，已安装的 Claude 没有改动。"
  else
    echo "✅ 试运行通过：可以从备份恢复英文原版，已安装的 Claude 没有改动。"
  fi
  finish 0
fi

open -a "$APP" 2>/dev/null || true
if [ "$MODE" = "install" ]; then
  echo "✅ 汉化完成，Claude 已重新打开。"
  echo "如果界面还是英文：点左下角账号菜单 → Language → ${LABEL}。"
  echo "Claude 自动更新后会变回英文，到时再双击运行一次本脚本即可。"
else
  echo "✅ 已恢复英文原版，Claude 已重新打开。"
fi
finish 0
