#!/usr/bin/env bash
set -Eeuo pipefail

# IPv6 一键管理脚本
# 适用于 Debian 及大多数使用 procps/sysctl 的 Linux 系统

CONF_FILE="/etc/sysctl.d/99-ipv6-closure.conf"
SYSCTL_CONF="/etc/sysctl.conf"

if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用 root 用户运行"
    exit 1
fi

if ! command -v sysctl >/dev/null 2>&1; then
    echo "错误：未找到 sysctl 命令"
    exit 1
fi

clean_legacy_lines() {
    [ -f "$SYSCTL_CONF" ] || return 0

    sed -i \
        -e '/^[[:space:]]*net\.ipv6\.conf\.all\.disable_ipv6[[:space:]]*=[[:space:]]*1[[:space:]]*$/d' \
        -e '/^[[:space:]]*net\.ipv6\.conf\.default\.disable_ipv6[[:space:]]*=[[:space:]]*1[[:space:]]*$/d' \
        -e '/^[[:space:]]*net\.ipv6\.conf\.lo\.disable_ipv6[[:space:]]*=[[:space:]]*1[[:space:]]*$/d' \
        "$SYSCTL_CONF"
}

ipv6_status_value() {
    cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo "unknown"
}

show_status() {
    local value
    value="$(ipv6_status_value)"

    echo
    echo "========================================"
    echo " IPv6 当前状态"
    echo "========================================"

    case "$value" in
        1)
            echo "状态：已禁用 ✓"
            ;;
        0)
            echo "状态：已启用 ✓"
            ;;
        *)
            echo "状态：无法判断"
            ;;
    esac

    echo "disable_ipv6 = $value"
    echo "========================================"
}

disable_ipv6() {
    echo "正在禁用 IPv6..."

    clean_legacy_lines

    cat > "$CONF_FILE" <<'EOF'
# Managed by kkx999/jiaoben ipv6-manager.sh
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
EOF

    sysctl -p "$CONF_FILE" >/dev/null

    if [ "$(ipv6_status_value)" = "1" ]; then
        echo "IPv6 已禁用 ✓"
    else
        echo "错误：IPv6 禁用未完全生效"
        exit 1
    fi
}

enable_ipv6() {
    echo "正在恢复 IPv6..."

    clean_legacy_lines
    rm -f "$CONF_FILE"

    sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null
    sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null
    sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null

    if [ "$(ipv6_status_value)" = "0" ]; then
        echo "IPv6 已恢复 ✓"
    else
        echo "错误：IPv6 恢复未完全生效"
        echo "可能还有其他 sysctl 配置或内核启动参数在禁用 IPv6。"
        exit 1
    fi
}

show_menu() {
    echo "========================================"
    echo " IPv6 一键管理脚本"
    echo "========================================"
    echo "1. 禁用 IPv6"
    echo "2. 恢复 IPv6"
    echo "3. 查看当前状态"
    echo "0. 退出"
    echo "========================================"
    read -rp "请选择 [0-3]: " choice

    case "$choice" in
        1) disable_ipv6; show_status ;;
        2) enable_ipv6; show_status ;;
        3) show_status ;;
        0) exit 0 ;;
        *) echo "错误：无效选项"; exit 1 ;;
    esac
}

case "${1:-}" in
    disable|off)
        disable_ipv6
        show_status
        ;;
    enable|on)
        enable_ipv6
        show_status
        ;;
    status)
        show_status
        ;;
    "")
        show_menu
        ;;
    *)
        echo "用法：$0 [disable|enable|status]"
        exit 1
        ;;
esac
