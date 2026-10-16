#!/bin/sh
set -eu

# X-UI Alpine Linux 首次安装一键脚本
# 项目：https://github.com/alireza0/x-ui
# 适用：Alpine Linux / OpenRC
#
# 默认自动生成用户名、密码、Web Base Path、面板端口。
#
# 自定义首次安装：
# XUI_USERNAME=admin XUI_PASSWORD='你的密码' XUI_PANEL_PORT=2053 \
# XUI_WEB_BASE_PATH='abc123' sh x-ui-alpine.sh

REPO="alireza0/x-ui"
INSTALL_DIR="/usr/local/x-ui"
DB_DIR="/etc/x-ui"
SERVICE_FILE="/etc/init.d/x-ui"
TMP_DIR="/tmp/x-ui-alpine-install"

RED="$(printf '\033[31m')"
GREEN="$(printf '\033[32m')"
PLAIN="$(printf '\033[0m')"

ok() { printf "%s%s%s\n" "$GREEN" "$*" "$PLAIN"; }
err() { printf "%s%s%s\n" "$RED" "$*" "$PLAIN" >&2; }
cleanup() { rm -rf "$TMP_DIR" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# 只允许首次安装，检测到已有 X-UI 就停止，避免覆盖。
if [ "$(id -u)" -ne 0 ]; then
    err "错误：请使用 root 用户运行。"
    exit 1
fi

if [ ! -f /etc/alpine-release ]; then
    err "错误：此脚本仅适用于 Alpine Linux。"
    exit 1
fi

if [ -x "$INSTALL_DIR/x-ui" ] || [ -f "$DB_DIR/x-ui.db" ]; then
    err "检测到 X-UI 已经安装。"
    err "这是首次安装脚本，不会覆盖现有安装。"
    exit 1
fi

detect_arch() {
    case "$(uname -m)" in
        x86_64|x64|amd64) echo "amd64" ;;
        i386|i486|i586|i686|x86) echo "386" ;;
        armv8*|armv8|arm64|aarch64) echo "arm64" ;;
        armv7*|armv7|arm) echo "armv7" ;;
        armv6*|armv6) echo "armv6" ;;
        armv5*|armv5) echo "armv5" ;;
        s390x) echo "s390x" ;;
        *)
            err "不支持的 CPU 架构：$(uname -m)"
            exit 1
            ;;
    esac
}

ARCH="$(detect_arch)"

echo "=============================================="
echo " X-UI Alpine Linux 首次安装"
echo "=============================================="
echo "架构：$ARCH"
echo "服务：OpenRC"
echo "=============================================="
echo

echo "[1/6] 安装 Alpine 依赖..."
apk add --no-cache curl wget tar tzdata ca-certificates nftables openrc
update-ca-certificates >/dev/null 2>&1 || true

mkdir -p "$TMP_DIR"

echo
echo "[2/6] 下载 X-UI 最新版本..."
DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/x-ui-linux-${ARCH}.tar.gz"

if ! curl -fL --retry 3 --connect-timeout 15 \
    -o "$TMP_DIR/x-ui.tar.gz" "$DOWNLOAD_URL"; then
    err "X-UI 下载失败，请检查 VPS 是否可以访问 GitHub。"
    exit 1
fi

echo
echo "[3/6] 解压并安装 X-UI..."
mkdir -p "$TMP_DIR/package"
tar -xzf "$TMP_DIR/x-ui.tar.gz" -C "$TMP_DIR/package"

if [ ! -f "$TMP_DIR/package/x-ui/x-ui" ]; then
    err "压缩包结构异常，未找到 x-ui 主程序。"
    exit 1
fi

mkdir -p "$DB_DIR"
cp -a "$TMP_DIR/package/x-ui" "$INSTALL_DIR"

chmod +x "$INSTALL_DIR/x-ui"
chmod +x "$INSTALL_DIR"/bin/xray-linux-* 2>/dev/null || true
chmod +x "$INSTALL_DIR/x-ui.sh" 2>/dev/null || true

# 与上游安装脚本一致，armv7 的 Xray 文件名改为 xray-linux-arm。
if [ "$ARCH" = "armv7" ] && [ -f "$INSTALL_DIR/bin/xray-linux-armv7" ]; then
    mv -f "$INSTALL_DIR/bin/xray-linux-armv7" "$INSTALL_DIR/bin/xray-linux-arm"
    chmod +x "$INSTALL_DIR/bin/xray-linux-arm"
fi

echo
echo "[4/6] 创建 Alpine OpenRC 服务..."

cat > "$SERVICE_FILE" <<'EOF'
#!/sbin/openrc-run

name="x-ui"
description="X-UI Panel"

command="/usr/local/x-ui/x-ui"
command_args=""
directory="/usr/local/x-ui"

command_background="yes"
pidfile="/run/x-ui.pid"

output_log="/var/log/x-ui.log"
error_log="/var/log/x-ui-error.log"

export XRAY_VMESS_AEAD_FORCED=false

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath --directory /var/log
    touch /var/log/x-ui.log /var/log/x-ui-error.log
    chmod 600 /var/log/x-ui.log /var/log/x-ui-error.log
}
EOF

chmod 755 "$SERVICE_FILE"

echo
echo "[5/6] 初始化首次安装配置..."

random_string() {
    length="$1"
    LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
}

random_port() {
    n="$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"
    echo $((1024 + n % 60977))
}

USERNAME="${XUI_USERNAME:-$(random_string 10)}"
PASSWORD="${XUI_PASSWORD:-$(random_string 18)}"
WEB_BASE_PATH="${XUI_WEB_BASE_PATH:-$(random_string 15)}"
PANEL_PORT="${XUI_PANEL_PORT:-$(random_port)}"

case "$PANEL_PORT" in
    ''|*[!0-9]*)
        err "面板端口必须是数字。"
        exit 1
        ;;
esac

if [ "$PANEL_PORT" -lt 1 ] || [ "$PANEL_PORT" -gt 65535 ]; then
    err "面板端口必须在 1-65535 范围内。"
    exit 1
fi

"$INSTALL_DIR/x-ui" setting \
    -username "$USERNAME" \
    -password "$PASSWORD" \
    -port "$PANEL_PORT" \
    -webBasePath "$WEB_BASE_PATH"

"$INSTALL_DIR/x-ui" migrate >/dev/null 2>&1 || true

echo
echo "[6/6] 启用 OpenRC 开机自启并启动 X-UI..."

rc-update add x-ui default >/dev/null 2>&1 || true

if ! rc-service x-ui start; then
    err "X-UI 启动失败。"
    err "检查：rc-service x-ui status"
    err "日志：tail -n 100 /var/log/x-ui-error.log"
    exit 1
fi

sleep 2

echo
ok "=============================================="
ok " X-UI 首次安装完成 ✓"
ok "=============================================="
echo "架构：        $ARCH"
echo "安装目录：    $INSTALL_DIR"
echo "数据库：      $DB_DIR/x-ui.db"
echo "OpenRC 服务： $SERVICE_FILE"
echo
echo "用户名：      $USERNAME"
echo "密码：        $PASSWORD"
echo "面板端口：    $PANEL_PORT"
echo "WebBasePath： $WEB_BASE_PATH"
echo
echo "面板地址："
"$INSTALL_DIR/x-ui" uri 2>/dev/null || true
echo
echo "服务状态：rc-service x-ui status"
echo "管理命令：x-ui"
ok "=============================================="
