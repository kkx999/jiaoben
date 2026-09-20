#!/usr/bin/env bash
set -Eeuo pipefail

# Swap 一键管理脚本
# 仓库：https://github.com/kkx999/jiaoben
# 只管理 /swapfile，不会删除或修改其他 Swap 分区/文件。

SCRIPT_VERSION="1.0.1"
SWAP_FILE="/swapfile"
FSTAB="/etc/fstab"
MIN_SWAP_MB=128

if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用 root 用户运行。"
    exit 1
fi

for cmd in awk df mkswap swapon swapoff chmod rm grep du wc mktemp cat dd; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "错误：缺少必要命令：$cmd"
        exit 1
    fi
done

format_mb() {
    awk -v mb="$1" 'BEGIN {
        if (mb >= 1024) {
            printf "%.1f GB", mb / 1024
        } else {
            printf "%d MB", mb
        }
    }'
}

disk_total_mb() {
    df -Pm / | awk 'NR==2 {print $2}'
}

disk_used_mb() {
    df -Pm / | awk 'NR==2 {print $3}'
}

disk_avail_mb() {
    df -Pm / | awk 'NR==2 {print $4}'
}

reserve_mb() {
    local total
    total="$(disk_total_mb)"

    if [ "$total" -lt 4096 ]; then
        echo 512
    else
        echo 1024
    fi
}

swapfile_allocated_mb() {
    if [ -f "$SWAP_FILE" ]; then
        du -Pm "$SWAP_FILE" 2>/dev/null | awk 'NR==1 {print $1}'
    else
        echo 0
    fi
}

swapfile_active() {
    awk -v f="$SWAP_FILE" 'NR > 1 && $1 == f {found=1} END {exit !found}' /proc/swaps
}

parse_size_mb() {
    local input="$1"

    awk -v s="$input" '
        BEGIN {
            gsub(/[[:space:]]/, "", s)

            # 纯数字或小数默认按 GB 处理，例如：1 = 1GB，1.5 = 1.5GB
            if (s ~ /^[0-9]+([.][0-9]+)?$/) {
                mb = (s + 0) * 1024
            } else if (s ~ /^[0-9]+([.][0-9]+)?[gG]$/) {
                num = substr(s, 1, length(s) - 1) + 0
                mb = num * 1024
            } else if (s ~ /^[0-9]+([.][0-9]+)?[mM]$/) {
                mb = substr(s, 1, length(s) - 1) + 0
            } else {
                exit 1
            }

            mb = int(mb + 0.5)

            if (mb < 1) {
                exit 1
            }

            print mb
        }
    '
}

recommended_swap_mb() {
    local ram_mb
    ram_mb="$(awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo)"

    if [ "$ram_mb" -le 1024 ]; then
        echo 2048
    elif [ "$ram_mb" -le 2048 ]; then
        echo 2048
    elif [ "$ram_mb" -le 4096 ]; then
        echo 1024
    else
        echo 1024
    fi
}

safe_max_mb() {
    local avail reclaim reserve max
    avail="$(disk_avail_mb)"
    reclaim="$(swapfile_allocated_mb)"
    reserve="$(reserve_mb)"
    max=$((avail + reclaim - reserve))

    if [ "$max" -lt 0 ]; then
        max=0
    fi

    echo "$max"
}

show_status() {
    local total used avail reserve reclaim max ram_total ram_avail swap_total swap_free recommendation

    total="$(disk_total_mb)"
    used="$(disk_used_mb)"
    avail="$(disk_avail_mb)"
    reserve="$(reserve_mb)"
    reclaim="$(swapfile_allocated_mb)"
    max="$(safe_max_mb)"

    ram_total="$(awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo)"
    ram_avail="$(awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo)"
    swap_total="$(awk '/^SwapTotal:/ {print int($2 / 1024)}' /proc/meminfo)"
    swap_free="$(awk '/^SwapFree:/ {print int($2 / 1024)}' /proc/meminfo)"
    recommendation="$(recommended_swap_mb)"

    echo
    echo "========================================"
    echo " Swap / 系统资源状态"
    echo "版本：${SCRIPT_VERSION}"
    echo "========================================"
    echo "系统盘总容量：$(format_mb "$total")"
    echo "系统盘已使用：$(format_mb "$used")"
    echo "系统盘可用空间：$(format_mb "$avail")"
    echo "安全预留空间：$(format_mb "$reserve")"
    echo
    echo "物理内存总量：$(format_mb "$ram_total")"
    echo "物理内存可用：$(format_mb "$ram_avail")"
    echo "当前 Swap 总量：$(format_mb "$swap_total")"
    echo "当前 Swap 可用：$(format_mb "$swap_free")"

    if [ -f "$SWAP_FILE" ]; then
        if swapfile_active; then
            echo "/swapfile：已存在并启用 ✓"
        else
            echo "/swapfile：已存在，但当前未启用"
        fi
        echo "/swapfile 占用磁盘：$(format_mb "$reclaim")"
    else
        echo "/swapfile：不存在"
    fi

    echo
    echo "建议 Swap：$(format_mb "$recommendation")"
    echo "当前最大安全可创建：$(format_mb "$max")"
    echo "========================================"

    if [ -s /proc/swaps ] && [ "$(wc -l < /proc/swaps)" -gt 1 ]; then
        echo
        echo "当前已启用的 Swap："
        swapon --show || true
    fi
}

ensure_swapfile_safe_to_replace() {
    if [ -L "$SWAP_FILE" ]; then
        echo "错误：检测到 $SWAP_FILE 是符号链接，为安全起见拒绝覆盖。"
        exit 1
    fi

    if [ -e "$SWAP_FILE" ] && [ ! -f "$SWAP_FILE" ]; then
        echo "错误：$SWAP_FILE 已存在且不是普通文件，为安全起见拒绝覆盖。"
        exit 1
    fi
}

remove_fstab_entry() {
    [ -f "$FSTAB" ] || return 0

    local tmp
    tmp="$(mktemp)"

    awk -v f="$SWAP_FILE" '
        {
            line=$0
            stripped=$0
            sub(/^[[:space:]]*/, "", stripped)

            if (stripped ~ /^#/ || stripped == "") {
                print line
                next
            }

            split(stripped, fields, /[[:space:]]+/)
            if (fields[1] != f) {
                print line
            }
        }
    ' "$FSTAB" > "$tmp"

    cat "$tmp" > "$FSTAB"
    rm -f "$tmp"
}

update_fstab() {
    remove_fstab_entry
    echo "$SWAP_FILE none swap sw 0 0" >> "$FSTAB"
}

create_swap_storage() {
    local size_mb="$1"
    local mode="${2:-fast}"
    local fs_type=""

    if command -v findmnt >/dev/null 2>&1; then
        fs_type="$(findmnt -no FSTYPE -T / 2>/dev/null || true)"
    fi

    rm -f "$SWAP_FILE"

    if [ "$fs_type" = "btrfs" ]; then
        if ! command -v chattr >/dev/null 2>&1; then
            echo "错误：Btrfs 创建 Swap 需要 chattr 命令。"
            return 1
        fi

        : > "$SWAP_FILE"
        chattr +C "$SWAP_FILE"
    fi

    if [ "$mode" = "fast" ] && command -v fallocate >/dev/null 2>&1; then
        fallocate -l "${size_mb}M" "$SWAP_FILE"
    else
        dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$size_mb" status=progress
    fi

    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE" >/dev/null
}

create_or_resize_swap() {
    local input size_mb max_mb reserve recommendation

    ensure_swapfile_safe_to_replace
    show_status

    recommendation="$(recommended_swap_mb)"
    max_mb="$(safe_max_mb)"
    reserve="$(reserve_mb)"

    echo
    read -rp "请输入 Swap 大小（单位默认 GB，例如 1、2、4、1.5；直接回车使用建议值 $(format_mb "$recommendation")）： " input

    if [ -z "$input" ]; then
        size_mb="$recommendation"
    else
        if ! size_mb="$(parse_size_mb "$input")"; then
            echo "错误：容量格式不正确。直接输入 1、2、4 代表 GB；也支持 512M、1.5G。"
            return 1
        fi
    fi

    if [ "$size_mb" -lt "$MIN_SWAP_MB" ]; then
        echo "错误：Swap 至少需要 $(format_mb "$MIN_SWAP_MB")。"
        return 1
    fi

    if [ "$size_mb" -gt "$max_mb" ]; then
        echo "错误：磁盘空间不足。"
        echo "你要创建：$(format_mb "$size_mb")"
        echo "最大安全值：$(format_mb "$max_mb")"
        echo "脚本会至少为系统盘保留：$(format_mb "$reserve")"
        return 1
    fi

    echo
    echo "即将创建/调整 $SWAP_FILE 为 $(format_mb "$size_mb")。"
    echo "其他 Swap 分区或 Swap 文件不会被修改。"
    read -rp "确认继续？[y/N]: " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消。"
        return 0
    fi

    if swapfile_active; then
        echo "正在停用现有 $SWAP_FILE ..."
        if ! swapoff "$SWAP_FILE"; then
            echo "错误：无法停用现有 $SWAP_FILE。"
            echo "通常是因为当前内存不足以接回 Swap 中的数据。"
            return 1
        fi
    fi

    echo "正在创建 $(format_mb "$size_mb") Swap..."

    if ! create_swap_storage "$size_mb" fast; then
        echo "错误：Swap 文件创建失败。"
        remove_fstab_entry
        rm -f "$SWAP_FILE"
        return 1
    fi

    if ! swapon "$SWAP_FILE"; then
        echo "第一次启用失败，正在使用兼容方式重新创建..."

        if ! create_swap_storage "$size_mb" dd || ! swapon "$SWAP_FILE"; then
            echo "错误：Swap 启用失败。当前文件系统或虚拟化环境可能不支持 Swap 文件。"
            remove_fstab_entry
            rm -f "$SWAP_FILE"
            return 1
        fi
    fi

    update_fstab

    echo
    echo "Swap 创建成功 ✓"
    show_status
}

delete_swapfile() {
    ensure_swapfile_safe_to_replace

    if [ ! -e "$SWAP_FILE" ]; then
        echo "当前没有 $SWAP_FILE，无需删除。"
        return 0
    fi

    echo
    echo "只会删除 $SWAP_FILE，不会删除其他 Swap 分区或 Swap 文件。"
    read -rp "确认删除？[y/N]: " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消。"
        return 0
    fi

    if swapfile_active; then
        echo "正在停用 $SWAP_FILE ..."
        if ! swapoff "$SWAP_FILE"; then
            echo "错误：无法停用 $SWAP_FILE。"
            echo "通常是因为当前内存不足以接回 Swap 中的数据。"
            return 1
        fi
    fi

    remove_fstab_entry

    rm -f "$SWAP_FILE"

    echo "已删除 $SWAP_FILE ✓"
    show_status
}

show_menu() {
    while true; do
        show_status

        echo
        echo "========================================"
        echo " Swap 一键管理"
        echo "========================================"
        echo "1. 创建 / 调整 Swap"
        echo "2. 删除 /swapfile"
        echo "3. 重新检测当前状态"
        echo "0. 退出"
        echo "========================================"
        read -rp "请选择 [0-3]: " choice

        case "$choice" in
            1) create_or_resize_swap ;;
            2) delete_swapfile ;;
            3) continue ;;
            0) exit 0 ;;
            *) echo "错误：无效选项。" ;;
        esac

        echo
        read -rp "按回车键继续..." _
    done
}

case "${1:-}" in
    status)
        show_status
        ;;
    "")
        show_menu
        ;;
    *)
        echo "用法：$0 [status]"
        exit 1
        ;;
esac
