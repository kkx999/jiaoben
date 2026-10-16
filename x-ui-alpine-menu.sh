#!/bin/sh
set -u

# X-UI Alpine Linux / OpenRC 管理菜单
# 由 kkx999/jiaoben 的 x-ui-alpine.sh 安装

INSTALL_DIR="/usr/local/x-ui"
DB_DIR="/etc/x-ui"
SERVICE="/etc/init.d/x-ui"
GREEN="$(printf '\033[32m')"
RED="$(printf '\033[31m')"
YELLOW="$(printf '\033[33m')"
PLAIN="$(printf '\033[0m')"

ok()   { printf "%s%s%s\n" "$GREEN" "$*" "$PLAIN"; }
warn() { printf "%s%s%s\n" "$YELLOW" "$*" "$PLAIN"; }
err()  { printf "%s%s%s\n" "$RED" "$*" "$PLAIN" >&2; }

arch() {
    case "$(uname -m)" in
        x86_64|x64|amd64) echo amd64 ;;
        i386|i486|i586|i686|x86) echo 386 ;;
        armv8*|armv8|arm64|aarch64) echo arm64 ;;
        armv7*|armv7|arm) echo armv7 ;;
        armv6*|armv6) echo armv6 ;;
        armv5*|armv5) echo armv5 ;;
        s390x) echo s390x ;;
        *) return 1 ;;
    esac
}

installed() {
    [ -x "$INSTALL_DIR/x-ui" ] && [ -x "$SERVICE" ]
}

running() {
    rc-service x-ui status >/dev/null 2>&1
}

enabled() {
    rc-update show default 2>/dev/null | grep -q 'x-ui'
}

confirm() {
    prompt="$1"
    default="${2:-n}"
    answer=""
    printf "%s [默认 %s]: " "$prompt" "$default"
    if [ -e /dev/tty ]; then
        read -r answer </dev/tty || answer=""
    else
        read -r answer || answer=""
    fi
    [ -z "$answer" ] && answer="$default"
    case "$answer" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

pause_menu() {
    printf "\n按 Enter 返回主菜单..."
    if [ -e /dev/tty ]; then
        read -r _ </dev/tty || true
    else
        read -r _ || true
    fi
}

read_tty() {
    var="$1"
    if [ -e /dev/tty ]; then
        IFS= read -r "$var" </dev/tty || true
    else
        IFS= read -r "$var" || true
    fi
}

random_string() {
    n="$1"
    LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$n"
}

show_status() {
    if ! installed; then
        printf "X-UI 状态：%s未安装%s\n" "$RED" "$PLAIN"
        return
    fi

    if running; then
        printf "X-UI 状态：%s运行中%s\n" "$GREEN" "$PLAIN"
    else
        printf "X-UI 状态：%s未运行%s\n" "$YELLOW" "$PLAIN"
    fi

    if enabled; then
        printf "开机自启：%s是%s\n" "$GREEN" "$PLAIN"
    else
        printf "开机自启：%s否%s\n" "$RED" "$PLAIN"
    fi

    if ps 2>/dev/null | grep '[x]ray-linux-' >/dev/null 2>&1; then
        printf "Xray 状态：%s运行中%s\n" "$GREEN" "$PLAIN"
    else
        printf "Xray 状态：%s未运行%s\n" "$RED" "$PLAIN"
    fi
}

check_install() {
    if ! installed; then
        err "请先安装 X-UI。"
        return 1
    fi
    return 0
}

start_panel() {
    check_install || return
    if running; then
        ok "X-UI 已经在运行。"
    elif rc-service x-ui start; then
        ok "X-UI 启动成功。"
    else
        err "X-UI 启动失败，请检查日志。"
    fi
}

stop_panel() {
    check_install || return
    if ! running; then
        warn "X-UI 已经停止。"
    elif rc-service x-ui stop; then
        ok "X-UI 已停止。"
    else
        err "X-UI 停止失败。"
    fi
}

restart_panel() {
    check_install || return
    if rc-service x-ui restart; then
        ok "X-UI 重启成功。"
    else
        err "X-UI 重启失败，请检查日志。"
    fi
}

restart_xray() {
    check_install || return
    if rc-service x-ui restart; then
        ok "Xray 已通过重启 X-UI 重新加载。"
    else
        err "Xray 重启失败，请检查日志。"
    fi
}

show_settings() {
    check_install || return
    echo
    "$INSTALL_DIR/x-ui" setting -show true || true
    echo
    "$INSTALL_DIR/x-ui" uri || true
}

set_port() {
    check_install || return

    port=""
    printf "请输入面板端口 [1-65535]: "
    read_tty port

    case "$port" in
        ''|*[!0-9]*)
            err "端口无效。"
            return
            ;;
    esac

    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        err "端口必须在 1-65535 范围内。"
        return
    fi

    "$INSTALL_DIR/x-ui" setting -port "$port"
    ok "面板端口已设置为：$port"

    if confirm "是否立即重启 X-UI？" "y"; then
        restart_panel
    fi
}

reset_user() {
    check_install || return

    username=""
    password=""

    printf "请输入新的用户名（直接回车=随机）："
    read_tty username
    [ -z "$username" ] && username="$(random_string 10)"

    printf "请输入新的密码（直接回车=随机）："
    read_tty password
    [ -z "$password" ] && password="$(random_string 18)"

    "$INSTALL_DIR/x-ui" setting -username "$username" -password "$password"

    echo
    ok "新的登录信息："
    echo "用户名：$username"
    echo "密码：  $password"

    if confirm "是否立即重启 X-UI？" "y"; then
        restart_panel
    fi
}

reset_webpath() {
    check_install || return

    path=""
    printf "请输入新的 WebBasePath（直接回车=随机）："
    read_tty path
    [ -z "$path" ] && path="$(random_string 15)"

    "$INSTALL_DIR/x-ui" setting -webBasePath "$path"
    echo
    ok "WebBasePath 已设置为：$path"

    if confirm "是否立即重启 X-UI？" "y"; then
        restart_panel
    fi
}

reset_settings() {
    check_install || return

    if ! confirm "确定重置所有面板设置？账号数据不会丢失。" "n"; then
        return
    fi

    "$INSTALL_DIR/x-ui" setting -reset
    warn "面板设置已恢复默认。"
    if confirm "是否立即重启 X-UI？" "y"; then
        restart_panel
    fi
}

enable_panel() {
    check_install || return
    if rc-update add x-ui default >/dev/null 2>&1; then
        ok "X-UI 已设置为开机自启。"
    else
        err "设置开机自启失败。"
    fi
}

disable_panel() {
    check_install || return
    if rc-update del x-ui default >/dev/null 2>&1; then
        ok "X-UI 开机自启已取消。"
    else
        err "取消开机自启失败。"
    fi
}

show_log() {
    check_install || return
    echo "按 Ctrl+C 返回。"
    echo
    tail -n 100 -f /var/log/x-ui.log /var/log/x-ui-error.log 2>/dev/null || \
        tail -n 200 /var/log/x-ui.log 2>/dev/null || true
}

update_panel() {
    check_install || return

    if ! confirm "确定更新 X-UI？数据库不会删除。" "n"; then
        return
    fi

    XARCH="$(arch)" || {
        err "无法识别 CPU 架构。"
        return
    }

    URL="https://github.com/alireza0/x-ui/releases/latest/download/x-ui-linux-${XARCH}.tar.gz"
    TMP="/usr/local/.x-ui-update"

    rm -rf "$TMP"
    mkdir -p "$TMP"

    echo "正在下载并解压最新 X-UI..."
    if ! wget -qO- "$URL" | tar -xzf - -C "$TMP"; then
        rm -rf "$TMP"
        err "更新包下载或解压失败。"
        return
    fi

    if [ ! -x "$TMP/x-ui/x-ui" ]; then
        rm -rf "$TMP"
        err "更新包结构异常。"
        return
    fi

    chmod +x "$TMP/x-ui/x-ui" "$TMP"/x-ui/bin/xray-linux-* 2>/dev/null || true

    WAS_RUNNING=0
    running && WAS_RUNNING=1

    rc-service x-ui stop >/dev/null 2>&1 || true

    rm -rf /usr/local/x-ui-backup
    mv "$INSTALL_DIR" /usr/local/x-ui-backup

    if ! mv "$TMP/x-ui" "$INSTALL_DIR"; then
        mv /usr/local/x-ui-backup "$INSTALL_DIR"
        rm -rf "$TMP"
        rc-service x-ui start >/dev/null 2>&1 || true
        err "更新失败，已恢复旧版本。"
        return
    fi

    rm -rf "$TMP"

    if [ "$WAS_RUNNING" -eq 1 ]; then
        if ! rc-service x-ui start; then
            err "新版本启动失败，请检查日志。"
            return
        fi
    fi

    rm -rf /usr/local/x-ui-backup
    ok "X-UI 更新完成。"
}

uninstall_panel() {
    check_install || return

    if ! confirm "确定卸载 X-UI？数据库和面板文件都会删除。" "n"; then
        return
    fi

    rc-service x-ui stop >/dev/null 2>&1 || true
    rc-update del x-ui default >/dev/null 2>&1 || true
    rm -f "$SERVICE"
    rm -rf "$INSTALL_DIR" "$DB_DIR"
    rm -f /usr/bin/x-ui

    ok "X-UI 已卸载。"
    exit 0
}

show_menu() {
    clear 2>/dev/null || true
    echo
    echo "=============================================="
    echo "        X-UI Alpine Linux 管理菜单"
    echo "=============================================="
    echo
    echo "  0. 退出"
    echo "----------------------------------------------"
    echo "  1. 安装 X-UI"
    echo "  2. 更新 X-UI"
    echo "  3. 卸载 X-UI"
    echo "----------------------------------------------"
    echo "  4. 重置用户名和密码"
    echo "  5. 重置 WebBasePath"
    echo "  6. 重置面板设置"
    echo "  7. 设置面板端口"
    echo "  8. 查看当前面板设置"
    echo "----------------------------------------------"
    echo "  9. 启动 X-UI"
    echo " 10. 停止 X-UI"
    echo " 11. 重启 X-UI"
    echo " 12. 重启 Xray"
    echo " 13. 查看运行状态"
    echo " 14. 查看日志"
    echo "----------------------------------------------"
    echo " 15. 开启开机自启"
    echo " 16. 关闭开机自启"
    echo "=============================================="
    show_status
    echo "=============================================="
    printf "请输入选项 [0-16]: "

    choice=""
    read_tty choice

    case "$choice" in
        0) exit 0 ;;
        1)
            if installed; then
                warn "X-UI 已经安装，请不要重复安装。"
            else
                err "首次安装请执行："
                echo "wget -qO- https://raw.githubusercontent.com/kkx999/jiaoben/main/x-ui-alpine.sh | sh"
            fi
            pause_menu
            ;;
        2) update_panel; pause_menu ;;
        3) uninstall_panel ;;
        4) reset_user; pause_menu ;;
        5) reset_webpath; pause_menu ;;
        6) reset_settings; pause_menu ;;
        7) set_port; pause_menu ;;
        8) show_settings; pause_menu ;;
        9) start_panel; pause_menu ;;
        10) stop_panel; pause_menu ;;
        11) restart_panel; pause_menu ;;
        12) restart_xray; pause_menu ;;
        13) show_status; pause_menu ;;
        14) show_log ;;
        15) enable_panel; pause_menu ;;
        16) disable_panel; pause_menu ;;
        *) err "请输入正确的选项 [0-16]"; pause_menu ;;
    esac
}

case "${1:-}" in
    start) start_panel ;;
    stop) stop_panel ;;
    restart) restart_panel ;;
    restart-xray) restart_xray ;;
    status) show_status ;;
    settings) show_settings ;;
    enable) enable_panel ;;
    disable) disable_panel ;;
    log) show_log ;;
    update) update_panel ;;
    uninstall) uninstall_panel ;;
    help)
        echo "x-ui              打开管理菜单"
        echo "x-ui start        启动"
        echo "x-ui stop         停止"
        echo "x-ui restart      重启"
        echo "x-ui restart-xray 重启 Xray"
        echo "x-ui status       查看状态"
        echo "x-ui settings     查看设置"
        echo "x-ui enable       开机自启"
        echo "x-ui disable      取消开机自启"
        echo "x-ui log          查看日志"
        echo "x-ui update       更新"
        echo "x-ui uninstall    卸载"
        ;;
    *) show_menu ;;
esac
