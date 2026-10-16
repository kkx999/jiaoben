#!/bin/sh
set -eu

# NAT / Alpine Linux SSL 证书一键申请脚本
# Cloudflare DNS 验证，无需开放 80 / 443
# 适合 Alpine Linux / NAT VPS / 低内存 VPS / LXC / 容器
#
# 证书：
#   /root/cert/<domain>/fullchain.pem
#   /root/cert/<domain>/privkey.pem
#
# 自动续期：acme.sh + Alpine BusyBox crond
# x-ui：证书安装/续期后自动尝试重启 x-ui

SCRIPT_VERSION="1.0.0-alpine"
ACME="/root/.acme.sh/acme.sh"
INSTALLER_FILE=""

if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用 root 用户运行"
    exit 1
fi

if [ ! -f /etc/alpine-release ]; then
    echo "错误：此脚本仅用于 Alpine Linux"
    exit 1
fi

cleanup() {
    stty echo 2>/dev/null || true

    if [ -n "${INSTALLER_FILE:-}" ]; then
        rm -f "$INSTALLER_FILE" 2>/dev/null || true
    fi

    unset CF_Token 2>/dev/null || true
}

trap cleanup EXIT INT TERM

install_packages() {
    echo "安装必要组件..."
    apk add --no-cache ca-certificates openssl curl
    update-ca-certificates >/dev/null 2>&1 || true
}

ensure_cron() {
    # Alpine 默认使用 BusyBox cron
    if ! command -v crontab >/dev/null 2>&1; then
        echo "错误：系统中不存在 crontab"
        echo "请确认 Alpine 安装了 busybox"
        exit 1
    fi

    if ! command -v crond >/dev/null 2>&1; then
        echo "错误：系统中不存在 crond"
        echo "请确认 Alpine 安装了 busybox"
        exit 1
    fi

    # Alpine + OpenRC
    if command -v rc-service >/dev/null 2>&1 &&
       [ -x /etc/init.d/crond ]; then

        if command -v rc-update >/dev/null 2>&1; then
            rc-update add crond default >/dev/null 2>&1 || true
        fi

        rc-service crond start >/dev/null 2>&1 ||         rc-service crond restart >/dev/null 2>&1 || true

        # 如果 OpenRC 没有成功启动，继续尝试直接启动
        if ! pidof crond >/dev/null 2>&1; then
            crond -b -l 8 >/dev/null 2>&1 || true
        fi

        return 0
    fi

    # 精简 Alpine / LXC / 容器等没有 OpenRC 的环境
    if ! pidof crond >/dev/null 2>&1; then
        crond -b -l 8 >/dev/null 2>&1 || true
    fi
}

echo "============================================================"
echo " NAT / Alpine Linux SSL 证书一键申请"
echo " 版本：$SCRIPT_VERSION"
echo " Cloudflare DNS 验证 · 无需开放 80 / 443"
echo "============================================================"
echo

read -r -p "请输入邮箱: " EMAIL
read -r -p "请输入要申请证书的域名: " DOMAIN

unset CF_Token 2>/dev/null || true

printf "请输入 Cloudflare API Token: "
stty -echo
read -r CF_Token
stty echo
printf "\n"

EMAIL=$(printf '%s' "$EMAIL" | tr -d '[:space:]')
DOMAIN=$(printf '%s' "$DOMAIN" | tr -d '[:space:]')

if [ -z "$EMAIL" ] || [ -z "$DOMAIN" ] || [ -z "$CF_Token" ]; then
    echo "错误：邮箱、域名和 Token 都不能为空"
    exit 1
fi

case "$DOMAIN" in
    http://*|https://*|*/*)
        echo "错误：域名只填写主机名，例如：nat.example.com"
        exit 1
        ;;
esac

echo
echo "[1/5] 检查并安装 Alpine 必要组件..."
install_packages

echo
echo "[2/5] 配置 BusyBox crond..."
ensure_cron

echo
echo "[3/5] 安装 / 更新 acme.sh..."

INSTALLER_FILE=$(mktemp)

curl -fsSL \
    --proto '=https' \
    --tlsv1.2 \
    https://get.acme.sh \
    -o "$INSTALLER_FILE"

# 安装 acme.sh 时不继承 Cloudflare Token
env -u CF_Token -u CF_Key -u CF_Email \
    sh "$INSTALLER_FILE" email="$EMAIL"

if [ ! -x "$ACME" ]; then
    echo "错误：acme.sh 安装失败"
    exit 1
fi

"$ACME" --set-default-ca --server letsencrypt

echo
echo "[4/5] 使用 Cloudflare DNS 验证申请证书..."

# Token 只传递给本次 acme.sh 调用
CF_Token="$CF_Token" "$ACME" \
    --issue \
    --server letsencrypt \
    --dns dns_cf \
    -d "$DOMAIN" \
    --keylength ec-256

CERT_DIR="/root/cert/$DOMAIN"

mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

echo
echo "[5/5] 安装证书到固定目录..."

"$ACME" \
    --install-cert \
    -d "$DOMAIN" \
    --ecc \
    --key-file "$CERT_DIR/privkey.pem" \
    --fullchain-file "$CERT_DIR/fullchain.pem" \
    --reloadcmd 'command -v x-ui >/dev/null 2>&1 && x-ui restart >/dev/null 2>&1 || true'

chmod 600 "$CERT_DIR/privkey.pem" 2>/dev/null || true
chmod 644 "$CERT_DIR/fullchain.pem" 2>/dev/null || true
chmod 600 /root/.acme.sh/account.conf 2>/dev/null || true

unset CF_Token 2>/dev/null || true

rm -f "$INSTALLER_FILE"
INSTALLER_FILE=""

echo
echo "============================================================"
echo " SSL 证书申请成功 ✓"
echo "------------------------------------------------------------"
echo "系统：Alpine Linux"
echo "域名：$DOMAIN"
echo "证书：$CERT_DIR/fullchain.pem"
echo "私钥：$CERT_DIR/privkey.pem"
echo

if crontab -l 2>/dev/null | grep -q "acme.sh"; then
    echo "自动续期任务：已配置 ✓"
else
    echo "自动续期任务：未检测到，请检查 crontab"
fi

if pidof crond >/dev/null 2>&1; then
    echo "BusyBox crond：正在运行 ✓"
else
    echo "BusyBox crond：未检测到运行，请检查 cron 服务"
fi

echo
echo "x-ui 中填写："
echo "证书公钥：$CERT_DIR/fullchain.pem"
echo "证书私钥：$CERT_DIR/privkey.pem"
echo "============================================================"
