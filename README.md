# 常用脚本

## VPS性能测试

```bash
wget -qO- bench.sh | bash
```

## BBR 一键管理

检测并开启系统自带 `fq + BBR`，不更换或删除内核。

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/kkx999/jiaoben/main/bbr-manager.sh?v=$(date +%s)")
```

## 线路测试

```bash
curl https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh -sSf | sh
```

## IP质量检测

```bash
bash <(curl -Ls IP.Check.Place)
```

## NAT 申请 SSL 证书

使用 Cloudflare DNS 验证申请 SSL 证书，并自动续期。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kkx999/jiaoben/main/nat-cert.sh)
```

## IPv6 一键管理

检测并管理 IPv6，支持禁用、恢复和状态检测。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kkx999/jiaoben/main/ipv6-manager.sh)
```

## Swap 一键管理

检测磁盘和内存，支持自定义创建、调整和删除 Swap。

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/kkx999/jiaoben/main/swap-manager.sh?v=$(date +%s)")
```
