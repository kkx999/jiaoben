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

## Windows 浏览器无痕模式剪贴板历史（AutoHotkey v2）

支持 Chrome、Edge、Firefox 的 Ctrl+C 文字复制快捷键，尝试让无痕模式复制的文字进入 Windows 10 的 Win+V 剪贴板历史。

- [下载 fuzhi.ahk](./fuzhi.ahk)（也可[直接下载原始脚本](https://raw.githubusercontent.com/kkx999/jiaoben/main/fuzhi.ahk)）
- 使用方法：安装 AutoHotkey v2，下载后双击运行 `fuzhi.ahk`。
- 注意：是否能进入 Win+V 历史取决于浏览器和 Windows 的行为；脚本仅处理快捷键复制，不处理右键复制。使用前建议关闭 Windows 剪贴板的跨设备同步。
