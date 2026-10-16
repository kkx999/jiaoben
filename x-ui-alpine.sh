#!/bin/sh
set -eu

# X-UI Alpine Linux 首次安装一键脚本（轻量 + 交互版）
# 项目：https://github.com/alireza0/x-ui
# 适用：Alpine Linux / OpenRC
#
# 特点：
#   - 首次安装时恢复交互式端口设置
#   - wget | sh 模式下从 /dev/tty 读取用户输入
#   - 不调用 GitHub API
#   - 不把整个安装包写入 /tmp，直接流式解压
#   - 安装完成后提供完整 Alpine OpenRC x-ui 管理菜单
#   - 检测到已有 X-UI 后不会覆盖

REPO="alireza0/x-ui"
INSTALL_DIR="/usr/local/x-ui"
DB_DIR="/etc/x-ui"
SERVICE_FILE="/etc/init.d/x-ui"
MENU_URL="https://raw.githubusercontent.com/kkx999/jiaoben/main/x-ui-alpine-menu.sh"

RED="$(printf '\033[31m')"
GREEN="$(printf '\033[32m')"
YELLOW="$(printf '\033[33m')"
PLAIN="$(printf '\033[0m')"

ok()   { printf "%s%s%s\n" "$GREEN" "$*" "$PLAIN"; }
warn() { printf "%s%s%s\n" "$YELLOW" "$*" "$PLAIN"; }
err()  { printf "%s%s%s\n" "$RED" "$*" "$PLAIN" >&2; }

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
        x86_64|x64|amd64) echo amd64 ;;
        i386|i486|i586|i686|x86) echo 386 ;;
        armv8*|armv8|arm64|aarch64) echo arm64 ;;
        armv7*|armv7|arm) echo armv7 ;;
        armv6*|armv6) echo armv6 ;;
        armv5*|armv5) echo armv5 ;;
        s390x) echo s390x ;;
        *)
            err "不支持的 CPU 架构：$(uname -m)"
            exit 1
            ;;
    esac
}

random_string() {
    length="$1"
    LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
}

random_port() {
    n="$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"
    echo $((1024 + n % 60977))
}

ARCH="$(detect_arch)"

echo
echo "=============================================="
echo "       X-UI Alpine Linux 首次安装"
echo "=============================================="
echo "架构：$ARCH"
echo "服务：OpenRC"
echo "模式：轻量安装"
echo "=============================================="
echo

echo "[1/6] 安装 Alpine 必要依赖..."
apk add --no-cache ca-certificates tzdata nftables
update-ca-certificates >/dev/null 2>&1 || true

command -v wget >/dev/null 2>&1 || apk add --no-cache wget
command -v tar >/dev/null 2>&1 || apk add --no-cache tar
command -v rc-service >/dev/null 2>&1 || apk add --no-cache openrc

echo
echo "[2/6] 下载并直接解压 X-UI..."
DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/x-ui-linux-${ARCH}.tar.gz"

mkdir -p /usr/local

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

chmod +x "$INSTALL_DIR/x-ui"
chmod +x "$INSTALL_DIR"/bin/xray-linux-* 2>/dev/null || true

if [ "$ARCH" = "armv7" ] && [ -f "$INSTALL_DIR/bin/xray-linux-armv7" ]; then
    mv -f "$INSTALL_DIR/bin/xray-linux-armv7" "$INSTALL_DIR/bin/xray-linux-arm"
    chmod +x "$INSTALL_DIR/bin/xray-linux-arm"
fi

mkdir -p "$DB_DIR"

echo
echo "[3/6] 配置首次安装账号和面板端口..."

USERNAME="${XUI_USERNAME:-$(random_string 10)}"
PASSWORD="${XUI_PASSWORD:-$(random_string 18)}"
WEB_BASE_PATH="${XUI_WEB_BASE_PATH:-$(random_string 15)}"

if [ -n "${XUI_PANEL_PORT:-}" ]; then
    PANEL_PORT="$XUI_PANEL_PORT"
elif [ "${XUI_NONINTERACTIVE:-0}" = "1" ] || [ ! -e /dev/tty ]; then
    PANEL_PORT="$(random_port)"
    echo "非交互安装：已生成随机面板端口：$PANEL_PORT"
else
    custom_port=""
    printf "是否自定义面板端口？[y/N]: "
    read -r custom_port </dev/tty || custom_port=""

    case "$custom_port" in
        y|Y|yes|YES)
            while :; do
                printf "请输入面板端口 [1-65535]: "
                read -r PANEL_PORT </dev/tty || PANEL_PORT=""
                case "$PANEL_PORT" in
                    ''|*[!0-9]*)
                        err "端口无效，请重新输入。"
                        continue
                        ;;
                esac
                if [ "$PANEL_PORT" -ge 1 ] && [ "$PANEL_PORT" -le 65535 ]; then
                    break
                fi
                err "端口必须在 1-65535 范围内，请重新输入。"
            done
            ;;
        *)
            PANEL_PORT="$(random_port)"
            echo "已生成随机面板端口：$PANEL_PORT"
            ;;
    esac
fi

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
echo "[5/6] 安装 Alpine x-ui 管理菜单..."

if wget -qO /usr/bin/x-ui "$MENU_URL"; then
    chmod 755 /usr/bin/x-ui
    ok "x-ui 管理菜单安装成功。"
else
    warn "管理菜单下载失败，X-UI 本体仍已安装。"
    echo "手动恢复：wget -qO /usr/bin/x-ui $MENU_URL && chmod 755 /usr/bin/x-ui"
fi

echo
echo "[6/6] 启用开机自启并启动 X-UI..."

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
echo "用户名：      $USERNAME"
echo "密码：        $PASSWORD"
echo "面板端口：    $PANEL_PORT"
echo "WebBasePath： $WEB_BASE_PATH"
echo
echo "面板地址："
"$INSTALL_DIR/x-ui" uri 2>/dev/null || true
echo
echo "执行 x-ui 可进入管理菜单。"
ok "=============================================="
