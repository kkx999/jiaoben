# 常用脚本

## VPS性能测试

```bash
# VPS基本信息、IO性能、全球测速
wget -qO- bench.sh | bash

# VPS基本信息、IO性能、国内测速
bash <(curl -Lso- git.io/superbench.sh)

# VPS基本信息、IO性能、国内外测速、Ping、路由测试
bash <(curl -Lso- https://raw.githubusercontent.com/FunctionClub/ZBench/master/ZBench-CN.sh)

# IO测试、宽带测试、SpeedTest国内节点测试、世界各地下载速度测试、路由测试、回程路由测试、全国Ping测试、国外Ping测试、UnixBench跑分测试
wget -N --no-check-certificate https://raw.githubusercontent.com/91yun/91yuntest/master/test.sh && bash test.sh -i "io,bandwidth,chinabw,download,traceroute,backtraceroute,allping"
```

## BBR加速

```bash
wget -N --no-check-certificate "https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh" && chmod +x tcp.sh && ./tcp.sh
```

## 线路测试

```bash
curl https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh -sSf | sh
```

## IP质量检测

```bash
bash <(curl -Ls IP.Check.Place)
```

## DD Debian12

```bash
apt update && apt install -y curl wget ca-certificates && \
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh && \
bash reinstall.sh debian 12 --username root --password '修改成你的新密码' --ssh-port 22
```

DD 重装脚本准备完成后执行重启：

```bash
reboot
```

查看实时安装进度：

```bash
tail -f /var/log/syslog
```

## NAT 申请 SSL 证书

适用于 Debian / NAT VPS / 低内存 Podman / LXC，使用 Cloudflare DNS 验证，无需开放 80 / 443 端口。

一键执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kkx999/jiaoben/main/nat-cert.sh)
```

运行后按提示输入：

- 邮箱
- 要申请证书的域名，例如 `nat.example.com`
- Cloudflare API Token

Cloudflare API Token 至少需要目标域名对应 Zone 的 DNS 编辑权限。

申请成功后证书默认保存到：

```text
/root/cert/你的域名/fullchain.pem
/root/cert/你的域名/privkey.pem
```

脚本会安装并配置 `acme.sh` 自动续期；如果系统使用 x-ui，证书续期完成后会自动尝试重启 x-ui。

## IPv6 一键管理

适用于 Debian 及大多数使用 `sysctl` 的 Linux 系统。启动后会先检测当前 IPv4、IPv6 和 IPv6 协议栈状态，再进行管理。

一键执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kkx999/jiaoben/main/ipv6-manager.sh)
```

运行后会先显示当前公网 IPv4 / IPv6；公网检测失败时会回退显示本机全局地址，然后进入菜单：

```text
1. 禁用 IPv6
2. 恢复 IPv6
3. 重新检测当前状态
0. 退出
```

禁用 IPv6 前脚本会再次检测网络：当前没有 IPv6 时会提示无需禁用；如果检测到 IPv6 但没有可用 IPv4，为避免关闭 IPv6 后 SSH 或网络中断，脚本不会执行禁用操作。

脚本使用 `/etc/sysctl.d/99-ipv6-closure.conf` 管理配置，并会清理旧版写入 `/etc/sysctl.conf` 的三条重复 IPv6 禁用配置，避免反复执行后不断追加相同内容。

## Swap 一键管理

适用于 Debian / Ubuntu 及大多数常见 Linux VPS。脚本会先检测系统盘总容量、已用空间、可用空间、物理内存和当前 Swap，再允许自定义创建或调整 `/swapfile`。

功能包括：

- 自动检测当前硬盘容量和剩余空间
- 自动检测物理内存和现有 Swap
- 支持直接输入数字作为 GB，例如 `1` = 1GB、`2` = 2GB、`1.5` = 1.5GB；同时兼容 `512M`、`1G` 等写法
- 根据内存容量给出建议值
- 自动计算当前最大安全可创建容量
- 创建前保留必要的系统磁盘空间，避免把系统盘占满
- 支持重新调整 `/swapfile` 大小
- 支持删除 `/swapfile`
- 自动写入 `/etc/fstab`，重启后继续生效
- 只管理 `/swapfile`，不会删除或修改其他 Swap 分区或 Swap 文件

一键执行：

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/kkx999/jiaoben/main/swap-manager.sh?v=$(date +%s)")
```
