#!/usr/bin/env bash
set -Eeuo pipefail

# IPv6 一键管理脚本
# 适用于 Debian 及大多数使用 procps/sysctl 的 Linux 系统
# 只管理本脚本自己的 /etc/sysctl.d 配置，不修改 /etc/sysctl.conf。

SCRIPT_VERSION="1.0.1"
CONF_FILE="/etc/sysctl.d/99-ipv6-closure.conf"
MANAGED_MARKER="# Managed by kkx999/jiaoben ipv6-manager.sh"

if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用 root 用户运行"
    exit 1
fi

if ! command -v sysctl >/dev/null 2>&1; then
    echo "错误：未找到 sysctl 命令"
    exit 1
fi

clear_screen() {
    if [ -t 1 ] && command -v clear >/dev/null 2>&1; then
        clear
    fi
}

section_header() {
    echo
    echo "============================================================"
    echo "  $1"
    echo "------------------------------------------------------------"
}

section_footer() {
    echo "============================================================"
}

managed_file() {
    [ -f "$CONF_FILE" ] && grep -Fqx "$MANAGED_MARKER" "$CONF_FILE"
}

check_managed_path_safe() {
    if [ -L "$CONF_FILE" ]; then
        echo "错误：检测到 $CONF_FILE 是符号链接，为安全起见拒绝修改。"
        return 1
    fi

    if [ -e "$CONF_FILE" ] && [ ! -f "$CONF_FILE" ]; then
        echo "错误：$CONF_FILE 已存在且不是普通文件，为安全起见拒绝修改。"
        return 1
    fi

    if [ -f "$CONF_FILE" ] && ! managed_file; then
        echo "错误：$CONF_FILE 已存在，但不是本脚本创建的配置。"
        echo "为避免覆盖其他程序的设置，本次不执行操作。"
        return 1
    fi
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

ssh_session_uses_ipv6() {
    local server_ip=""

    [ -n "${SSH_CONNECTION:-}" ] || return 1
    server_ip="$(awk '{print $3}' <<< "$SSH_CONNECTION")"
    [[ "$server_ip" == *:* ]]
}

other_ipv6_disable_config() {
    local file

    for file in \
        /etc/sysctl.conf \
        /etc/sysctl.d/*.conf \
        /run/sysctl.d/*.conf \
        /usr/local/lib/sysctl.d/*.conf \
        /usr/lib/sysctl.d/*.conf \
        /lib/sysctl.d/*.conf
    do
        [ -f "$file" ] || continue
        [ "$file" = "$CONF_FILE" ] && continue

        if grep -Eq '^[[:space:]]*net\.ipv6\.conf\.(all|default|lo)\.disable_ipv6[[:space:]]*=[[:space:]]*1([[:space:]]*(#.*)?)?$' "$file"; then
            printf '%s\n' "$file"
        fi
    done | awk '!seen[$0]++'
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

    section_header "当前 IP 检测"

    if [ -n "$public4" ]; then
        echo "公网 IPv4：$public4"
    elif [ -n "$local4" ]; then
        echo "IPv4：$local4（公网检测失败/可能为 NAT）"
    else
        echo "IPv4：未检测到"
    fi

    if [ "$ipv6_disabled" = "1" ]; then
        echo "IPv6：已禁用"
    elif [ -n "$public6" ]; then
        echo "公网 IPv6：$public6"
    elif [ -n "$local6" ]; then
        echo "IPv6：$local6（公网连通性未确认）"
    else
        echo "IPv6：未检测到"
    fi

    section_footer
}

show_status() {
    local value owner
    value="$(ipv6_status_value)"

    if managed_file; then
        owner="由本脚本管理 ✓"
    elif [ -f "$CONF_FILE" ]; then
        owner="存在同名外部配置，本脚本不会覆盖"
    else
        owner="未创建持久化配置"
    fi

    section_header "IPv6 当前状态"
    echo "脚本版本：$SCRIPT_VERSION"

    case "$value" in
        1)
            echo "状态：已禁用"
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
    echo "持久化配置：$owner"
    section_footer
}

disable_ipv6() {
    if [ "$(ipv6_status_value)" = "1" ]; then
        echo "IPv6 当前已经处于禁用状态，无需重复操作。"
        if managed_file; then
            echo "持久化配置由本脚本管理。"
        else
            echo "当前禁用状态不是由本脚本接管，本脚本不会覆盖其他配置。"
        fi
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

    if ssh_session_uses_ipv6; then
        echo "警告：检测到当前 SSH 会话正在通过 IPv6 连接。"
        echo "禁用 IPv6 会直接断开当前 SSH，因此本次拒绝执行。"
        echo "请改用 IPv4 SSH 登录后再运行。"
        return 1
    fi

    check_managed_path_safe || return 1

    echo "正在禁用 IPv6..."

    cat > "$CONF_FILE" <<EOF
$MANAGED_MARKER
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
EOF

    if ! sysctl -p "$CONF_FILE" >/dev/null; then
        echo "错误：应用 IPv6 配置失败，正在移除本脚本配置。"
        rm -f "$CONF_FILE"
        return 1
    fi

    if [ "$(ipv6_status_value)" = "1" ]; then
        echo "IPv6 已禁用 ✓"
    else
        echo "错误：IPv6 禁用未完全生效"
        rm -f "$CONF_FILE"
        return 1
    fi
}

enable_ipv6() {
    local external_configs=""

    check_managed_path_safe || return 1

    if managed_file; then
        echo "正在移除本脚本的 IPv6 禁用配置..."
        rm -f "$CONF_FILE"
    else
        echo "未发现本脚本创建的 IPv6 禁用配置。"
    fi

    external_configs="$(other_ipv6_disable_config || true)"
    if [ -n "$external_configs" ]; then
        echo
        echo "检测到其他配置仍要求禁用 IPv6，本脚本不会覆盖："
        printf '%s\n' "$external_configs"
        echo "请先确认这些配置是否需要保留。"
        return 1
    fi

    echo "正在恢复当前运行状态中的 IPv6..."

    sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null
    sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null
    sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null

    if [ "$(ipv6_status_value)" = "0" ]; then
        echo "IPv6 已恢复 ✓"
    else
        echo "错误：IPv6 恢复未完全生效"
        echo "可能还有内核启动参数、容器限制或其他网络管理程序在禁用 IPv6。"
        return 1
    fi
}

show_menu() {
    while true; do
        clear_screen
        show_network_info
        show_status

        section_header "IPv6 一键管理"
        echo "1. 禁用 IPv6"
        echo "2. 恢复 IPv6"
        echo "3. 重新检测当前状态"
        echo "0. 退出"
        section_footer
        read -rp "请选择 [0-3]: " choice

        clear_screen

        case "$choice" in
            1)
                section_header "操作：禁用 IPv6"
                if disable_ipv6; then
                    echo
                    show_network_info
                    show_status
                else
                    echo
                    echo "操作未完成，请根据上方提示检查。"
                fi
                ;;
            2)
                section_header "操作：恢复 IPv6"
                if enable_ipv6; then
                    echo
                    show_network_info
                    show_status
                else
                    echo
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
        echo "------------------------------------------------------------"
        read -rp "按回车键返回主菜单..." _
    done
}

case "${1:-}" in
    disable|off)
        disable_ipv6
        echo
        show_network_info
        show_status
        ;;
    enable|on)
        enable_ipv6
        echo
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
