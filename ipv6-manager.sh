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

get_local_ipv4() {
    if command -v ip >/dev/null 2>&1; then
        ip -o -4 addr show scope global 2>/dev/null \
            | awk '{print $4}' \
            | cut -d/ -f1 \
            | paste -sd ', ' -
    fi
}

get_local_ipv6() {
    if command -v ip >/dev/null 2>&1; then
        ip -o -6 addr show scope global 2>/dev/null \
            | awk '{print $4}' \
            | cut -d/ -f1 \
            | paste -sd ', ' -
    fi
}

get_public_ipv4() {
    command -v curl >/dev/null 2>&1 || return 0
    curl -4 -fsS --connect-timeout 3 --max-time 5 https://api.ipify.org 2>/dev/null || true
}

get_public_ipv6() {
    command -v curl >/dev/null 2>&1 || return 0
    curl -6 -fsS --connect-timeout 3 --max-time 5 https://api6.ipify.org 2>/dev/null || true
}

has_ipv4() {
    [ -n "$(get_public_ipv4)" ] || [ -n "$(get_local_ipv4)" ]
}

has_ipv6() {
    [ -n "$(get_public_ipv6)" ] || [ -n "$(get_local_ipv6)" ]
}

show_network_info() {
    local public4 public6 local4 local6 ipv6_disabled

    public4="$(get_public_ipv4)"
    local4="$(get_local_ipv4)"
    ipv6_disabled="$(ipv6_status_value)"

    if [ "$ipv6_disabled" = "1" ]; then
        public6=""
        local6=""
    else
        public6="$(get_public_ipv6)"
        local6="$(get_local_ipv6)"
    fi

    echo
    echo "========================================"
    echo " 当前 IP 检测"
    echo "========================================"

    if [ -n "$public4" ]; then
        echo "公网 IPv4：$public4"
    elif [ -n "$local4" ]; then
        echo "IPv4：$local4（公网检测失败/可能为 NAT）"
    else
        echo "IPv4：未检测到"
    fi

    if [ "$ipv6_disabled" = "1" ]; then
        echo "IPv6：已禁用 ✓"
    elif [ -n "$public6" ]; then
        echo "公网 IPv6：$public6"
    elif [ -n "$local6" ]; then
        echo "IPv6：$local6（公网连通性未确认）"
    else
        echo "IPv6：未检测到"
    fi

    echo "========================================"
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
            if has_ipv6; then
                echo "状态：已启用，检测到 IPv6 ✓"
            else
                echo "状态：协议栈已启用，但当前未检测到 IPv6"
            fi
            ;;
        *)
            echo "状态：无法判断"
            ;;
    esac

    echo "disable_ipv6 = $value"
    echo "========================================"
}

disable_ipv6() {
    echo
    echo "正在检测当前网络..."
    show_network_info

    if [ "$(ipv6_status_value)" = "1" ]; then
        echo "IPv6 当前已经处于禁用状态，无需重复操作。"
        return 0
    fi

    if ! has_ipv6; then
        echo "当前未检测到可用 IPv6，无需禁用。"
        return 0
    fi

    if ! has_ipv4; then
        echo "警告：检测到 IPv6，但未检测到可用 IPv4。"
        echo "为避免关闭 IPv6 后 SSH/网络连接中断，本次不执行禁用操作。"
        return 1
    fi

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
        echo "正在重新检测禁用后的网络状态..."
        show_network_info
    else
        echo "错误：IPv6 禁用未完全生效"
        return 1
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
        return 1
    fi
}

show_menu() {
    while true; do
        show_network_info
        show_status

        echo
        echo "========================================"
        echo " IPv6 一键管理脚本"
        echo "========================================"
        echo "1. 禁用 IPv6"
        echo "2. 恢复 IPv6"
        echo "3. 重新检测当前状态"
        echo "0. 退出"
        echo "========================================"
        read -rp "请选择 [0-3]: " choice

        case "$choice" in
            1)
                if disable_ipv6; then
                    show_status
                else
                    echo "操作未完成，请根据上方提示检查。"
                fi
                ;;
            2)
                if enable_ipv6; then
                    show_network_info
                    show_status
                else
                    echo "操作未完成，请根据上方提示检查。"
                fi
                ;;
            3)
                show_network_info
                show_status
                ;;
            0)
                echo "已退出。"
                exit 0
                ;;
            *)
                echo "错误：无效选项，请输入 0-3。"
                ;;
        esac

        echo
        read -rp "按回车键返回菜单..." _
    done
}

case "${1:-}" in
    disable|off)
        disable_ipv6
        show_status
        ;;
    enable|on)
        enable_ipv6
        show_network_info
        show_status
        ;;
    status)
        show_network_info
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
