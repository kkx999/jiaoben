# 常用脚本

## VPS性能测试

```
#VPS基本信息、IO性能、全球测速
wget -qO- bench.sh | bash
#VPS基本信息、IO性能、国内测速
bash <(curl -Lso- git.io/superbench.sh)
#VPS基本信息、IO性能、国内外测速、Ping、路由测试
bash <(curl -Lso- https://raw.githubusercontent.com/FunctionClub/ZBench/master/ZBench-CN.sh)
#IO测试、宽带测试、SpeedTest国内节点测试、世界各地下载速度测试、路由测试、回程路由测试、全国Ping测试、国外Ping测试、UnixBench跑分测试
wget -N --no-check-certificate https://raw.githubusercontent.com/91yun/91yuntest/master/test.sh && bash test.sh -i "io,bandwidth,chinabw,download,traceroute,backtraceroute,allping"
```

## BBR加速

```
wget -N --no-check-certificate "https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh" && chmod +x tcp.sh && ./tcp.sh
```

## 三网测速

```
bash <(curl -Lso- https://raw.githubusercontent.com/uxh/superspeed/master/superspeed.sh)
```

## 线路测试

```
curl https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh -sSf | sh
bash <(curl -Lso- https://raw.githubusercontent.com/flyzy2005/shell/master/autoBestTrace.sh)
bash <(curl -Lso- https://raw.githubusercontent.com/nanqinlang-script/testrace/master/testrace.sh)
```

## IP质量检测

```
bash <(curl -Ls IP.Check.Place)
```

## DD Debian12

```
apt update && apt install -y curl wget ca-certificates && \
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh && \
bash reinstall.sh debian 12 --username root --password '修改成你的新密码' --ssh-port 22
```
DD 重装脚本准备完成执行重启
```
reboot
```
查看实时安装进度
```
tail -f /var/log/syslog
```
nat申请证书
```
cat > /root/acme-debian-lowmem.sh <<'EOF'
#!/bin/bash
set -e

# ==============================
# Debian 低内存 ACME DNS 证书脚本
# 适合 128MB Podman / LXC
# ==============================

if [ "$(id -u)" != "0" ]; then
    echo "错误：请使用 root 用户运行"
    exit 1
fi

if [ ! -f /etc/debian_version ]; then
    echo "错误：此脚本仅用于 Debian"
    exit 1
fi

echo "========================================"
echo " Debian 低内存 SSL 证书申请脚本"
echo " Cloudflare DNS 验证"
echo " 无需开放 80 / 443"
echo "========================================"
echo

read -rp "请输入邮箱: " EMAIL
read -rp "请输入要申请证书的域名: " DOMAIN
read -rsp "请输入 Cloudflare API Token: " CF_Token
echo

if [ -z "$EMAIL" ] || [ -z "$DOMAIN" ] || [ -z "$CF_Token" ]; then
    echo "错误：邮箱、域名和 Token 都不能为空"
    exit 1
fi

export CF_Token
export DEBIAN_FRONTEND=noninteractive

echo
echo "[1/6] 配置 Debian 低内存安装模式..."

LOWMEM="/etc/apt/apt.conf.d/99-acme-lowmem"
DEBCONF="/etc/apt/apt.conf.d/70debconf"
DEBCONF_BAK="/etc/apt/apt.conf.d/70debconf.acme-backup"

cat > "$LOWMEM" <<'APTCONF'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
APT::Keep-Downloaded-Packages "false";
Acquire::Languages "none";
Acquire::Queue-Mode "access";
Acquire::http::Pipeline-Depth "0";
Dpkg::Use-Pty "0";
APTCONF

# 禁用 dpkg-preconfigure
# 128MB Debian 最容易在这里被 OOM Kill
if [ -f "$DEBCONF" ]; then
    mv "$DEBCONF" "$DEBCONF_BAK"
fi

restore_debconf() {
    rm -f "$LOWMEM"

    if [ -f "$DEBCONF_BAK" ]; then
        mv "$DEBCONF_BAK" "$DEBCONF"
    fi
}

trap restore_debconf EXIT

echo
echo "[2/6] 安装最小必要组件..."

dpkg --configure -a >/dev/null 2>&1 || true

apt-get clean

apt-get update \
    -o Acquire::Languages=none \
    -o Dpkg::Use-Pty=0

install_pkg() {
    PKG="$1"

    if ! dpkg -s "$PKG" >/dev/null 2>&1; then
        echo "安装 $PKG ..."

        apt-get install -y \
            --no-install-recommends \
            -o Dpkg::Use-Pty=0 \
            "$PKG"
    fi
}

install_pkg ca-certificates
install_pkg openssl

if ! command -v curl >/dev/null 2>&1; then
    install_pkg curl
fi

# 不安装完整 cron
# 使用轻量 BusyBox cron
if ! command -v crontab >/dev/null 2>&1; then
    install_pkg busybox-static

    if [ -x /bin/busybox ]; then
        BUSYBOX="/bin/busybox"
    elif [ -x /usr/bin/busybox ]; then
        BUSYBOX="/usr/bin/busybox"
    else
        echo "错误：BusyBox 安装失败"
        exit 1
    fi

    "$BUSYBOX" --list | grep -qx crontab || {
        echo "错误：BusyBox 不包含 crontab"
        exit 1
    }

    "$BUSYBOX" --list | grep -qx crond || {
        echo "错误：BusyBox 不包含 crond"
        exit 1
    }

    ln -sf "$BUSYBOX" /usr/local/bin/crontab
    ln -sf "$BUSYBOX" /usr/local/sbin/crond

    mkdir -p /var/spool/cron/crontabs
    chmod 700 /var/spool/cron/crontabs
fi

echo
echo "[3/6] 启动轻量自动续期服务..."

# 当前立即启动
if command -v crond >/dev/null 2>&1; then
    if ! pgrep -x crond >/dev/null 2>&1; then
        crond -b -l 8 >/dev/null 2>&1 || true
    fi
fi

# systemd 环境：设置开机启动
if command -v systemctl >/dev/null 2>&1 && [ "$(cat /proc/1/comm 2>/dev/null)" = "systemd" ]; then

cat > /etc/systemd/system/acme-crond.service <<'SERVICE'
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
    systemctl enable acme-crond.service >/dev/null 2>&1 || true

    if ! systemctl is-active --quiet acme-crond.service; then
        pkill crond >/dev/null 2>&1 || true
        systemctl start acme-crond.service >/dev/null 2>&1 || true
    fi
fi

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
echo "[4/6] 安装 acme.sh..."

curl -fsSL https://get.acme.sh | sh -s email="$EMAIL"

ACME="/root/.acme.sh/acme.sh"

if [ ! -x "$ACME" ]; then
    echo "错误：acme.sh 安装失败"
    exit 1
fi

"$ACME" --set-default-ca --server letsencrypt

echo
echo "[5/6] 使用 Cloudflare DNS 申请证书..."

"$ACME" \
    --issue \
    --server letsencrypt \
    --dns dns_cf \
    -d "$DOMAIN" \
    --keylength ec-256

CERT_DIR="/root/cert/$DOMAIN"

mkdir -p "$CERT_DIR"

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
chmod 600 /root/.acme.sh/account.conf 2>/dev/null || true

unset CF_Token

apt-get clean >/dev/null 2>&1 || true
rm -rf /var/lib/apt/lists/* >/dev/null 2>&1 || true

echo
echo "========================================"
echo "        SSL 证书申请成功"
echo "========================================"
echo
echo "域名：$DOMAIN"
echo
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
echo
echo "证书公钥："
echo "$CERT_DIR/fullchain.pem"
echo
echo "证书私钥："
echo "$CERT_DIR/privkey.pem"
echo
echo "========================================"
EOF

chmod +x /root/acme-debian-lowmem.sh
/root/acme-debian-lowmem.sh
```
