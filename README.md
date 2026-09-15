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

## 三网测速

```bash
bash <(curl -Lso- https://raw.githubusercontent.com/uxh/superspeed/master/superspeed.sh)
```

## 线路测试

```bash
curl https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh -sSf | sh
bash <(curl -Lso- https://raw.githubusercontent.com/flyzy2005/shell/master/autoBestTrace.sh)
bash <(curl -Lso- https://raw.githubusercontent.com/nanqinlang-script/testrace/master/testrace.sh)
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
