#!/bin/sh
set -eu

# X-UI Alpine Linux 首次安装一键脚本（轻量版）
# 项目：https://github.com/alireza0/x-ui
# 适用：Alpine Linux / OpenRC
#
# 特点：
#   - 不调用 GitHub API，直接下载 latest
#   - 不把压缩包保存到 /tmp，直接流式解压，降低 tmpfs/内存压力
#   - 尽量使用 Alpine BusyBox 自带 wget/tar，少装依赖
#   - 仅首次安装；检测到已有 X-UI 会直接退出
#
# 自定义首次安装：
# XUI_USERNAME=admin XUI_PASSWORD='你的密码' XUI_PANEL_PORT=2053 \
# XUI_WEB_BASE_PATH='abc123' sh x-ui-alpine.sh

REPO="alireza0/x-ui"
INSTALL_DIR="/usr/local/x-ui"
DB_DIR="/etc/x-ui"
SERVICE_FILE="/etc/init.d/x-ui"

RED="$(printf '\033[31m')"
GREEN="$(printf '\033[32m')"
PLAIN="$(printf '\033[0m')"

ok() { printf "%s%s%s\n" "$GREEN" "$*" "$PLAIN"; }
err() { printf "%s%s%s\n" "$RED" "$*" "$PLAIN" >&2; }

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
echo " X-UI Alpine Linux 首次安装（轻量版）"
echo "=============================================="
echo "架构：$ARCH"
echo "服务：OpenRC"
echo "=============================================="
echo

# Alpine 默认通常已经带 BusyBox wget/tar 和 OpenRC。
# 这里只补充 HTTPS 证书及系统时区数据，避免安装不必要的大量包。
echo "[1/5] 安装最少依赖..."
apk add --no-cache ca-certificates tzdata
update-ca-certificates >/dev/null 2>&1 || true

if ! command -v wget >/dev/null 2>&1; then
    apk add --no-cache wget
fi

if ! command -v tar >/dev/null 2>&1; then
    apk add --no-cache tar
fi

if ! command -v rc-service >/dev/null 2>&1; then
    apk add --no-cache openrc
fi

echo
echo "[2/5] 下载并直接解压 X-UI..."
DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/x-ui-linux-${ARCH}.tar.gz"

mkdir -p /usr/local

# 流式下载 + 解压，不在 /tmp 或 /usr/local 保存整个 tar.gz。
if ! wget -qO- "$DOWNLOAD_URL" | tar -xzf - -C /usr/local; then
    err "X-UI 下载或解压失败。"
    rm -rf "$INSTALL_DIR" 2>/dev/null || true
    exit 1
fi

if [ ! -f "$INSTALL_DIR/x-ui" ]; then
    err "安装失败：未找到 $INSTALL_DIR/x-ui"
    rm -rf "$INSTALL_DIR" 2>/dev/null || true
    exit 1
fi

echo
echo "[3/5] 配置 X-UI..."

mkdir -p "$DB_DIR"

chmod +x "$INSTALL_DIR/x-ui"
chmod +x "$INSTALL_DIR"/bin/xray-linux-* 2>/dev/null || true

# 与上游架构处理保持一致。
if [ "$ARCH" = "armv7" ] && [ -f "$INSTALL_DIR/bin/xray-linux-armv7" ]; then
    mv -f "$INSTALL_DIR/bin/xray-linux-armv7" "$INSTALL_DIR/bin/xray-linux-arm"
    chmod +x "$INSTALL_DIR/bin/xray-linux-arm"
fi

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

"$INSTALL_DIR/x-ui" \
    setting \
    -username "$USERNAME" \
    -password "$PASSWORD" \
    -port "$PANEL_PORT" \
    -webBasePath "$WEB_BASE_PATH"

echo
echo "[4/5] 创建 Alpine OpenRC 服务..."

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

# Alpine 兼容的轻量管理命令，不使用上游 systemd 管理脚本。
cat > /usr/bin/x-ui <<'EOF'
#!/bin/sh

case "${1:-}" in
    start)    rc-service x-ui start ;;
    stop)     rc-service x-ui stop ;;
    restart)  rc-service x-ui restart ;;
    status)   rc-service x-ui status ;;
    enable)   rc-update add x-ui default ;;
    disable)  rc-update del x-ui default ;;
    log)      tail -n 100 /var/log/x-ui.log ;;
    settings) /usr/local/x-ui/x-ui setting -show true ;;
    uri)      /usr/local/x-ui/x-ui uri ;;
    *)
        echo "X-UI Alpine 管理命令"
        echo
        echo "x-ui start       启动"
        echo "x-ui stop        停止"
        echo "x-ui restart     重启"
        echo "x-ui status      查看状态"
        echo "x-ui settings    查看设置"
        echo "x-ui uri         查看面板地址"
        echo "x-ui log         查看日志"
        echo "x-ui enable      开机自启"
        echo "x-ui disable     取消开机自启"
        ;;
esac
EOF

chmod 755 /usr/bin/x-ui

echo
echo "[5/5] 启用开机自启并启动 X-UI..."

rc-update add x-ui default >/dev/null 2>&1 || true

if ! rc-service x-ui start; then
    err "X-UI 启动失败。"
    err "检查：rc-service x-ui status"
    err "日志：tail -n 100 /var/log/x-ui-error.log"
    exit 1
fi

sleep 1

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
