#!/usr/bin/env bash
set -Eeuo pipefail

# IP 质量检测脚本
# 仓库：https://github.com/kkx999/jiaoben
# 无广告、无推广；仅进行公网 IP 与网络属性检测。

SCRIPT_VERSION="1.0.0"
CURL_TIMEOUT=10

if ! command -v curl >/dev/null 2>&1; then
    echo "错误：未找到 curl，请先安装 curl。"
    exit 1
fi

section_header() {
    echo
    echo "============================================================"
    echo "  $1"
    echo "------------------------------------------------------------"
}

section_footer() {
    echo "============================================================"
}

trim() {
    local value="$1"
    value="${value//$'\r'/}"
    value="${value//$'\n'/}"
    printf '%s' "$value"
}

get_public_ipv4() {
    local ip=""

    ip="$(curl -4 -fsS --connect-timeout 4 --max-time 7 https://api.ipify.org 2>/dev/null || true)"
    if [ -z "$ip" ]; then
        ip="$(curl -4 -fsS --connect-timeout 4 --max-time 7 https://icanhazip.com 2>/dev/null || true)"
    fi

    ip="$(trim "$ip")"

    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf '%s' "$ip"
    fi
}

get_public_ipv6() {
    local ip=""

    ip="$(curl -6 -fsS --connect-timeout 4 --max-time 7 https://api6.ipify.org 2>/dev/null || true)"
    if [ -z "$ip" ]; then
        ip="$(curl -6 -fsS --connect-timeout 4 --max-time 7 https://icanhazip.com 2>/dev/null || true)"
    fi

    ip="$(trim "$ip")"

    if [[ "$ip" =~ ^[0-9A-Fa-f:]+$ ]] && [[ "$ip" == *:* ]]; then
        printf '%s' "$ip"
    fi
}

query_ip_api() {
    local ip="$1"
    local encoded
    local fields

    encoded="${ip//:/%3A}"
    fields="status,message,query,country,regionName,city,isp,org,as,asname,mobile,proxy,hosting"

    curl -fsS         --connect-timeout 5         --max-time "$CURL_TIMEOUT"         -A "kkx999-jiaoben-ip-quality/$SCRIPT_VERSION"         "http://ip-api.com/line/${encoded}?fields=${fields}&lang=zh-CN"         2>/dev/null || true
}

bool_text() {
    case "$1" in
        true) echo "是" ;;
        false) echo "否" ;;
        *) echo "未知" ;;
    esac
}

network_type() {
    local mobile="$1"
    local hosting="$2"

    if [ "$hosting" = "true" ]; then
        echo "机房 / 托管网络"
    elif [ "$mobile" = "true" ]; then
        echo "移动网络"
    else
        echo "非机房网络（住宅 / 企业等）"
    fi
}

proxy_text() {
    case "$1" in
        true) echo "检测到（可能为代理 / VPN / Tor）" ;;
        false) echo "未检测到" ;;
        *) echo "未知" ;;
    esac
}

show_ip_info() {
    local label="$1"
    local ip="$2"
    local response=""
    local -a lines=()

    section_header "$label"

    if [ -z "$ip" ]; then
        echo "状态：未检测到可用 $label"
        section_footer
        return 0
    fi

    echo "公网 IP：$ip"
    echo "正在获取网络属性..."

    response="$(query_ip_api "$ip")"

    if [ -z "$response" ]; then
        echo
        echo "网络属性：查询失败"
        echo "公网 IP 检测正常，但第三方信息接口暂时不可用。"
        section_footer
        return 0
    fi

    mapfile -t lines <<< "$response"

    if [ "${lines[0]:-}" != "success" ]; then
        echo
        echo "网络属性：查询失败"
        if [ -n "${lines[1]:-}" ]; then
            echo "原因：${lines[1]}"
        fi
        section_footer
        return 0
    fi

    local query="${lines[2]:-$ip}"
    local country="${lines[3]:-未知}"
    local region="${lines[4]:-未知}"
    local city="${lines[5]:-未知}"
    local isp="${lines[6]:-未知}"
    local org="${lines[7]:-未知}"
    local asn="${lines[8]:-未知}"
    local asname="${lines[9]:-未知}"
    local mobile="${lines[10]:-}"
    local proxy="${lines[11]:-}"
    local hosting="${lines[12]:-}"

    echo
    echo "IP：$query"
    echo "国家 / 地区：$country"
    echo "州 / 省：$region"
    echo "城市：$city"
    echo "ISP：$isp"
    echo "组织：$org"
    echo "ASN：$asn"
    echo "ASN 名称：$asname"
    echo
    echo "网络类型：$(network_type "$mobile" "$hosting")"
    echo "机房 / 托管：$(bool_text "$hosting")"
    echo "移动网络：$(bool_text "$mobile")"
    echo "代理特征：$(proxy_text "$proxy")"

    section_footer
}

main() {
    local ipv4 ipv6

    ipv4="$(get_public_ipv4)"
    ipv6="$(get_public_ipv6)"

    clear 2>/dev/null || true

    section_header "IP 质量检测"
    echo "脚本版本：$SCRIPT_VERSION"
    echo "无广告 · 无推广 · 不修改系统配置"
    section_footer

    show_ip_info "IPv4" "$ipv4"
    show_ip_info "IPv6" "$ipv6"

    echo
    echo "说明：IP 地理位置、网络类型和代理识别来自第三方数据库，仅供参考。"
}

main "$@"
