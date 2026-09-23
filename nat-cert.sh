#!/usr/bin/env bash
set -Eeuo pipefail

# NAT / 低内存 Debian SSL 证书一键申请脚本
# Cloudflare DNS 验证，无需开放 80 / 443 端口
# 适合 Debian / NAT VPS / 低内存 Podman / LXC

SCRIPT_VERSION="1.0.1"
LOWMEM="/etc/apt/apt.conf.d/99-acme-lowmem"
DEBCONF="/etc/apt/apt.conf.d/70debconf"
DEBCONF_BAK="/etc/apt/apt.conf.d/70debconf.acme-backup"
ACME="/root/.acme.sh/acme.sh"
CRON_SERVICE="/etc/systemd/system/acme-crond.service"
CRON_SERVICE_MARKER="# Managed by kkx999/jiaoben nat-cert.sh"
DEBCONF_MOVED=0
INSTALLER_FILE=""

if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用 root 用户运行"
    exit 1
fi

if [ ! -f /etc/debian_version ]; then
    echo "错误：此脚本仅用于 Debian"
    exit 1
fi

cleanup() {
    rm -f "$LOWMEM"

    if [ "$DEBCONF_MOVED" = "1" ] && [ -f "$DEBCONF_BAK" ]; then
        mv -f "$DEBCONF_BAK" "$DEBCONF"
    fi

    if [ -n "$INSTALLER_FILE" ]; then
        rm -f "$INSTALLER_FILE"
    fi

    unset CF_Token || true
}
trap cleanup EXIT

is_managed_cron_service() {
    [ -f "$CRON_SERVICE" ] && grep -Fqx "$CRON_SERVICE_MARKER" "$CRON_SERVICE"
}

ensure_busybox_cron() {
    local busybox=""

    if command -v crontab >/dev/null 2>&1; then
        return 0
    fi

    install_pkg busybox-static

    if [ -x /bin/busybox ]; then
        busybox="/bin/busybox"
    elif [ -x /usr/bin/busybox ]; then
        busybox="/usr/bin/busybox"
    else
        echo "错误：BusyBox 安装失败"
        return 1
    fi

    "$busybox" --list | grep -qx crontab || {
        echo "错误：BusyBox 不包含 crontab"
        return 1
    }

    "$busybox" --list | grep -qx crond || {
        echo "错误：BusyBox 不包含 crond"
        return 1
    }

    if [ -e /usr/local/bin/crontab ] && [ ! -L /usr/local/bin/crontab ]; then
        echo "错误：/usr/local/bin/crontab 已存在且不是符号链接，拒绝覆盖"
        return 1
    fi

    if [ -e /usr/local/sbin/crond ] && [ ! -L /usr/local/sbin/crond ]; then
        echo "错误：/usr/local/sbin/crond 已存在且不是符号链接，拒绝覆盖"
        return 1
    fi

    ln -sfn "$busybox" /usr/local/bin/crontab
    ln -sfn "$busybox" /usr/local/sbin/crond

    mkdir -p /var/spool/cron/crontabs
    chmod 700 /var/spool/cron/crontabs
}

configure_busybox_cron_service() {
    [ -x /usr/local/sbin/crond ] || return 0

    if command -v systemctl >/dev/null 2>&1 && [ "$(cat /proc/1/comm 2>/dev/null || true)" = "systemd" ]; then
        if [ -L "$CRON_SERVICE" ]; then
            echo "警告：$CRON_SERVICE 是符号链接，为安全起见跳过写入。"
            echo "请确认系统现有 cron 服务可以执行 acme.sh 的续期任务。"
            return 0
        fi

        if [ -e "$CRON_SERVICE" ] && ! is_managed_cron_service; then
            echo "警告：$CRON_SERVICE 已存在且不是本脚本创建，跳过覆盖。"
            echo "请确认系统现有 cron 服务可以执行 acme.sh 的续期任务。"
            return 0
        fi

        cat > "$CRON_SERVICE" <<SERVICE
$CRON_SERVICE_MARKER
[Unit]
Description=BusyBox Cron for acme.sh
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/crond -f -l 8
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

        systemctl daemon-reload
        systemctl enable --now acme-crond.service >/dev/null 2>&1 || {
            echo "警告：BusyBox cron 的 systemd 服务启动失败。"
            echo "证书已可申请，但请检查自动续期服务。"
        }
    elif ! pgrep -f '(^|/)(busybox[[:space:]]+)?crond([[:space:]]|$)' >/dev/null 2>&1; then
        /usr/local/sbin/crond -b -l 8 >/dev/null 2>&1 || {
            echo "警告：BusyBox crond 启动失败，请检查自动续期。"
        }
    fi
}

install_pkg() {
    local pkg="$1"

    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        echo "安装 $pkg ..."
        apt-get install -y \
            --no-install-recommends \
            -o Dpkg::Use-Pty=0 \
            "$pkg"
    fi
}

echo "============================================================"
echo " NAT / Debian SSL 证书一键申请"
echo " 版本：$SCRIPT_VERSION"
echo " Cloudflare DNS 验证 · 无需开放 80 / 443"
echo "============================================================"
echo

read -rp "请输入邮箱: " EMAIL
read -rp "请输入要申请证书的域名: " DOMAIN

# 先清除可能从父进程继承的同名导出变量，避免后续安装器意外继承 Token。
unset CF_Token || true
read -rsp "请输入 Cloudflare API Token: " CF_Token
echo

EMAIL="${EMAIL//[[:space:]]/}"
DOMAIN="${DOMAIN//[[:space:]]/}"

if [ -z "$EMAIL" ] || [ -z "$DOMAIN" ] || [ -z "$CF_Token" ]; then
    echo "错误：邮箱、域名和 Token 都不能为空"
    exit 1
fi

if [[ "$DOMAIN" == http://* || "$DOMAIN" == https://* || "$DOMAIN" == */* ]]; then
    echo "错误：域名只填写主机名，例如：nat.example.com"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo
echo "[1/6] 配置 Debian 低内存安装模式..."

cat > "$LOWMEM" <<'APTCONF'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
APT::Keep-Downloaded-Packages "false";
Acquire::Languages "none";
Acquire::Queue-Mode "access";
Acquire::http::Pipeline-Depth "0";
Dpkg::Use-Pty "0";
APTCONF

# 128MB 左右 Debian 在 dpkg-preconfigure 阶段较容易触发 OOM。
# 临时移走 70debconf，脚本退出时恢复。
if [ -f "$DEBCONF" ]; then
    rm -f "$DEBCONF_BAK"
    mv "$DEBCONF" "$DEBCONF_BAK"
    DEBCONF_MOVED=1
fi

echo
echo "[2/6] 安装最小必要组件..."

dpkg --configure -a >/dev/null 2>&1 || true
apt-get clean
apt-get update -o Acquire::Languages=none -o Dpkg::Use-Pty=0

install_pkg ca-certificates
install_pkg openssl

if ! command -v curl >/dev/null 2>&1; then
    install_pkg curl
fi

ensure_busybox_cron

command -v curl >/dev/null 2>&1 || {
    echo "错误：curl 不存在"
    exit 1
}

command -v openssl >/dev/null 2>&1 || {
    echo "错误：openssl 不存在"
    exit 1
}

command -v crontab >/dev/null 2>&1 || {
    echo "错误：crontab 不存在"
    exit 1
}

echo
echo "[3/6] 安装 / 更新 acme.sh..."

INSTALLER_FILE="$(mktemp)"
curl -fsSL --proto '=https' --tlsv1.2 https://get.acme.sh -o "$INSTALLER_FILE"

# 安装器在不包含 Cloudflare 凭据的干净环境中运行。
env -u CF_Token -u CF_Key -u CF_Email sh "$INSTALLER_FILE" email="$EMAIL"

if [ ! -x "$ACME" ]; then
    echo "错误：acme.sh 安装失败"
    exit 1
fi

"$ACME" --set-default-ca --server letsencrypt

echo
echo "[4/6] 配置自动续期服务..."
configure_busybox_cron_service

echo
echo "[5/6] 使用 Cloudflare DNS 申请证书..."

# Token 只传递给本次 acme.sh 调用，不全局 export 给其他子进程。
CF_Token="$CF_Token" "$ACME" \
    --issue \
    --server letsencrypt \
    --dns dns_cf \
    -d "$DOMAIN" \
    --keylength ec-256

# acme.sh 已将续期所需凭据保存到自己的配置中。
chmod 600 /root/.acme.sh/account.conf 2>/dev/null || true

# 当前 Shell 不再保留 Token。
unset CF_Token

CERT_DIR="/root/cert/$DOMAIN"
mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

echo
echo "[6/6] 安装证书到固定目录..."

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

apt-get clean >/dev/null 2>&1 || true
rm -rf /var/lib/apt/lists/* >/dev/null 2>&1 || true

echo
echo "============================================================"
echo " SSL 证书申请成功 ✓"
echo "------------------------------------------------------------"
echo "域名：$DOMAIN"
echo "证书：$CERT_DIR/fullchain.pem"
echo "私钥：$CERT_DIR/privkey.pem"
echo

if crontab -l 2>/dev/null | grep -q "acme.sh"; then
    echo "自动续期：已配置 ✓"
else
    echo "自动续期：未检测到，请检查 crontab"
fi

echo
echo "x-ui 中填写："
echo "证书公钥：$CERT_DIR/fullchain.pem"
echo "证书私钥：$CERT_DIR/privkey.pem"
echo "============================================================"
