#!/usr/bin/env bash
set -Eeuo pipefail

# BBR 一键管理脚本
# 仓库：https://github.com/kkx999/jiaoben
# 只管理系统自带 BBR，不自动安装、删除或替换 Linux 内核。

SCRIPT_VERSION="1.0.0"
CONF_FILE="/etc/sysctl.d/99-bbr.conf"
MODULE_FILE="/etc/modules-load.d/99-bbr.conf"
STATE_DIR="/var/lib/jiaoben-bbr-manager"
STATE_FILE="$STATE_DIR/state.conf"
MANAGED_MARKER="# Managed by kkx999/jiaoben bbr-manager.sh"

if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用 root 用户运行。"
    exit 1
fi

for cmd in awk cat grep mkdir rm sysctl uname; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "错误：缺少必要命令：$cmd"
        exit 1
    fi
done

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

get_os_name() {
    if [ -r /etc/os-release ]; then
        awk -F= '
            $1 == "PRETTY_NAME" {
                value=$2
                gsub(/^"/, "", value)
                gsub(/"$/, "", value)
                print value
                exit
            }
        ' /etc/os-release
    else
        echo "Unknown Linux"
    fi
}

get_virtualization() {
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        local virt
        virt="$(systemd-detect-virt 2>/dev/null || true)"
        [ -n "$virt" ] && echo "$virt" || echo "none"
    else
        echo "unknown"
    fi
}

sysctl_value() {
    sysctl -n "$1" 2>/dev/null || true
}

current_cc() {
    sysctl_value net.ipv4.tcp_congestion_control
}

available_cc() {
    sysctl_value net.ipv4.tcp_available_congestion_control
}

current_qdisc() {
    sysctl_value net.core.default_qdisc
}

word_in_list() {
    local needle="$1"
    shift
    local word

    for word in $*; do
        [ "$word" = "$needle" ] && return 0
    done

    return 1
}

bbr_available() {
    word_in_list "bbr" "$(available_cc)"
}

managed_file() {
    local file="$1"
    [ -f "$file" ] && grep -Fqx "$MANAGED_MARKER" "$file"
}

check_managed_path_safe() {
    local file="$1"

    if [ -L "$file" ]; then
        echo "错误：检测到 $file 是符号链接，为安全起见拒绝修改。"
        return 1
    fi

    if [ -e "$file" ] && [ ! -f "$file" ]; then
        echo "错误：$file 已存在且不是普通文件，为安全起见拒绝修改。"
        return 1
    fi

    if [ -f "$file" ] && ! managed_file "$file"; then
        echo "错误：$file 已存在，但不是本脚本创建的配置。"
        echo "为避免覆盖其他程序的配置，本次不执行操作。"
        return 1
    fi
}

save_original_state() {
    [ -f "$STATE_FILE" ] && return 0

    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"

    {
        echo "qdisc=$(current_qdisc)"
        echo "congestion=$(current_cc)"
    } > "$STATE_FILE"

    chmod 600 "$STATE_FILE"
}

read_saved_value() {
    local key="$1"

    [ -r "$STATE_FILE" ] || return 0
    awk -F= -v k="$key" '$1 == k {sub(/^[^=]*=/, ""); print; exit}' "$STATE_FILE"
}

try_load_bbr() {
    bbr_available && return 0

    if ! command -v modprobe >/dev/null 2>&1; then
        return 1
    fi

    modprobe tcp_bbr >/dev/null 2>&1 || return 1
    bbr_available
}

persist_bbr_module_if_needed() {
    [ -d /etc/modules-load.d ] || return 0
    command -v modinfo >/dev/null 2>&1 || return 0

    local filename
    filename="$(modinfo -F filename tcp_bbr 2>/dev/null || true)"

    if [ -n "$filename" ] && [ "$filename" != "(builtin)" ]; then
        check_managed_path_safe "$MODULE_FILE" || return 1
        {
            echo "$MANAGED_MARKER"
            echo "tcp_bbr"
        } > "$MODULE_FILE"
    fi
}

restore_original_state() {
    local saved_cc saved_qdisc avail fallback

    saved_cc="$(read_saved_value congestion)"
    saved_qdisc="$(read_saved_value qdisc)"
    avail="$(available_cc)"

    if [ -n "$saved_cc" ] && word_in_list "$saved_cc" "$avail"; then
        sysctl -w "net.ipv4.tcp_congestion_control=$saved_cc" >/dev/null 2>&1 || true
    else
        fallback=""
        for fallback in cubic reno; do
            if word_in_list "$fallback" "$avail"; then
                sysctl -w "net.ipv4.tcp_congestion_control=$fallback" >/dev/null 2>&1 || true
                break
            fi
        done
    fi

    if [ -n "$saved_qdisc" ]; then
        sysctl -w "net.core.default_qdisc=$saved_qdisc" >/dev/null 2>&1 || true
    fi
}

show_status() {
    local cc avail qdisc support active managed os virt

    os="$(get_os_name)"
    virt="$(get_virtualization)"
    cc="$(current_cc)"
    avail="$(available_cc)"
    qdisc="$(current_qdisc)"

    if bbr_available; then
        support="支持 ✓"
    elif command -v modinfo >/dev/null 2>&1 && modinfo tcp_bbr >/dev/null 2>&1; then
        support="内核包含 BBR 模块，但当前未加载"
    else
        support="当前不可用"
    fi

    if [ "$cc" = "bbr" ]; then
        active="已启用 ✓"
    else
        active="未启用"
    fi

    if managed_file "$CONF_FILE"; then
        managed="已写入 ✓"
    elif [ -f "$CONF_FILE" ]; then
        managed="存在其他配置（本脚本不会覆盖）"
    else
        managed="未写入"
    fi

    section_header "BBR / 系统状态"
    echo "脚本版本：$SCRIPT_VERSION"
    echo "系统：$os"
    echo "内核：$(uname -r)"
    echo "虚拟化：$virt"
    echo
    echo "BBR 支持：$support"
    echo "BBR 状态：$active"
    echo "当前拥塞控制：${cc:-无法读取}"
    echo "可用拥塞控制：${avail:-无法读取}"
    echo "当前队列算法：${qdisc:-无法读取}"
    echo "持久化配置：$managed"
    section_footer
}

enable_bbr() {
    local old_cc old_qdisc

    section_header "操作：开启 BBR"

    check_managed_path_safe "$CONF_FILE" || return 1

    old_cc="$(current_cc)"
    old_qdisc="$(current_qdisc)"

    if [ -z "$old_cc" ] || [ -z "$old_qdisc" ]; then
        echo "错误：当前环境无法读取 TCP 拥塞控制或默认队列算法。"
        echo "这通常发生在受限容器/OpenVZ 环境中。"
        return 1
    fi

    if [ "$old_cc" = "bbr" ]; then
        if managed_file "$CONF_FILE"; then
            echo "BBR 当前已经由本脚本启用，无需重复操作。"
        else
            echo "检测到 BBR 当前已经启用。"
            echo "它不是由本脚本的 $CONF_FILE 配置启用，本脚本不会重复接管或覆盖。"
        fi
        section_footer
        return 0
    fi

    echo "正在检测内核 BBR 支持..."

    if ! try_load_bbr; then
        echo "错误：当前内核无法提供 BBR。"
        echo "本脚本不会自动替换、安装或删除 Linux 内核。"
        echo "请先使用支持 BBR 的发行版内核后再执行。"
        section_footer
        return 1
    fi

    save_original_state

    if command -v modprobe >/dev/null 2>&1; then
        modprobe sch_fq >/dev/null 2>&1 || true
    fi

    echo "正在应用 fq + BBR..."

    if ! sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1; then
        echo "错误：当前内核或虚拟化环境不允许设置 fq。"
        restore_original_state
        section_footer
        return 1
    fi

    if ! sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1; then
        echo "错误：当前环境不允许启用 BBR。"
        restore_original_state
        section_footer
        return 1
    fi

    {
        echo "$MANAGED_MARKER"
        echo "net.core.default_qdisc=fq"
        echo "net.ipv4.tcp_congestion_control=bbr"
    } > "$CONF_FILE"

    if ! persist_bbr_module_if_needed; then
        echo "错误：无法安全写入 BBR 模块持久化配置。"
        rm -f "$CONF_FILE"
        restore_original_state
        section_footer
        return 1
    fi

    if [ "$(current_cc)" != "bbr" ] || [ "$(current_qdisc)" != "fq" ]; then
        echo "错误：配置已写入，但 fq + BBR 未完全生效，正在回滚。"
        rm -f "$CONF_FILE"
        managed_file "$MODULE_FILE" && rm -f "$MODULE_FILE"
        restore_original_state
        section_footer
        return 1
    fi

    echo "BBR 已开启 ✓"
    echo "队列算法：$(current_qdisc)"
    echo "拥塞控制：$(current_cc)"
    section_footer
}

disable_bbr() {
    local cc

    section_header "操作：关闭 BBR"

    check_managed_path_safe "$CONF_FILE" || return 1

    if managed_file "$CONF_FILE"; then
        rm -f "$CONF_FILE"
        echo "已删除本脚本的 BBR 持久化配置。"
    else
        echo "未发现本脚本创建的 BBR 持久化配置。"
    fi

    if managed_file "$MODULE_FILE"; then
        rm -f "$MODULE_FILE"
    fi

    restore_original_state
    cc="$(current_cc)"

    if [ "$cc" = "bbr" ]; then
        echo "警告：当前仍然是 BBR。"
        echo "可能还有其他 sysctl 配置在启用 BBR，或没有可用的替代拥塞控制算法。"
        echo "本脚本不会删除其他程序的配置。"
        section_footer
        return 1
    fi

    rm -f "$STATE_FILE"
    rmdir "$STATE_DIR" >/dev/null 2>&1 || true

    echo "BBR 已关闭 ✓"
    echo "当前拥塞控制：${cc:-无法读取}"
    echo "当前队列算法：$(current_qdisc)"
    section_footer
}

show_menu() {
    while true; do
        clear_screen
        show_status

        section_header "BBR 一键管理"
        echo "1. 开启 BBR"
        echo "2. 关闭 BBR"
        echo "3. 重新检测当前状态"
        echo "0. 退出"
        section_footer

        read -rp "请选择 [0-3]: " choice

        case "$choice" in
            1)
                clear_screen
                if enable_bbr; then
                    echo
                    show_status
                else
                    echo
                    echo "操作未完成，请根据上方提示检查。"
                fi
                ;;
            2)
                clear_screen
                if disable_bbr; then
                    echo
                    show_status
                else
                    echo
                    echo "操作未完全完成，请根据上方提示检查。"
                fi
                ;;
            3)
                clear_screen
                show_status
                ;;
            0)
                clear_screen
                echo "已退出。"
                exit 0
                ;;
            *)
                echo
                echo "错误：无效选项，请输入 0-3。"
                ;;
        esac

        echo
        echo "------------------------------------------------------------"
        read -rp "按回车键返回主菜单..." _
    done
}

case "${1:-}" in
    enable|on)
        enable_bbr
        show_status
        ;;
    disable|off)
        disable_bbr
        show_status
        ;;
    status)
        show_status
        ;;
    "")
        show_menu
        ;;
    *)
        echo "用法：$0 [enable|disable|status]"
        exit 1
        ;;
esac
