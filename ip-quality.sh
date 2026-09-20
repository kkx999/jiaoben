#!/usr/bin/env bash
set -Eeuo pipefail

# 多库 IP 质量检测脚本
# 仓库：https://github.com/kkx999/jiaoben
# 无广告、无推广；不修改系统配置。

SCRIPT_VERSION="1.1.0"
CURL_TIMEOUT=10
IPAPI_IS_KEY="${IPAPI_IS_KEY:-}"

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

bool_text() {
    case "${1:-}" in
        true) echo "是" ;;
        false) echo "否" ;;
        *) echo "未知" ;;
    esac
}

risk_text() {
    case "${1:-}" in
        true) echo "检测到" ;;
        false) echo "未检测到" ;;
        *) echo "未知" ;;
    esac
}

get_public_ipv4() {
    local ip=""
    ip="$(curl -4 -fsS --connect-timeout 4 --max-time 7 https://api.ipify.org 2>/dev/null || true)"
    [ -n "$ip" ] || ip="$(curl -4 -fsS --connect-timeout 4 --max-time 7 https://icanhazip.com 2>/dev/null || true)"
    ip="$(trim "$ip")"

    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf '%s' "$ip"
    fi
}

get_public_ipv6() {
    local ip=""
    ip="$(curl -6 -fsS --connect-timeout 4 --max-time 7 https://api6.ipify.org 2>/dev/null || true)"
    [ -n "$ip" ] || ip="$(curl -6 -fsS --connect-timeout 4 --max-time 7 https://icanhazip.com 2>/dev/null || true)"
    ip="$(trim "$ip")"

    if [[ "$ip" =~ ^[0-9A-Fa-f:]+$ ]] && [[ "$ip" == *:* ]]; then
        printf '%s' "$ip"
    fi
}

json_get() {
    local json="$1"
    local path="$2"

    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$json" | python3 -c '
import json, sys
path = sys.argv[1].split(".")
try:
    obj = json.load(sys.stdin)
    for key in path:
        if isinstance(obj, dict):
            obj = obj.get(key)
        else:
            obj = None
            break
    if obj is None:
        print("")
    elif isinstance(obj, bool):
        print("true" if obj else "false")
    elif isinstance(obj, (dict, list)):
        print(json.dumps(obj, ensure_ascii=False))
    else:
        print(obj)
except Exception:
    print("")
' "$path" 2>/dev/null
        return
    fi

    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" | jq -r --arg p "$path" '
            getpath($p | split(".")) // empty
        ' 2>/dev/null || true
    fi
}

query_ip_api() {
    local ip="$1"
    local fields
    fields="status,message,query,country,countryCode,regionName,city,isp,org,as,asname,mobile,proxy,hosting"

    curl -fsS         --connect-timeout 5         --max-time "$CURL_TIMEOUT"         -A "kkx999-jiaoben-ip-quality/$SCRIPT_VERSION"         --get         --data-urlencode "fields=$fields"         --data-urlencode "lang=zh-CN"         "http://ip-api.com/line/$ip"         2>/dev/null || true
}

query_ipapi_is() {
    local ip="$1"

    if [ -n "$IPAPI_IS_KEY" ]; then
        curl -fsS             --connect-timeout 5             --max-time "$CURL_TIMEOUT"             -A "kkx999-jiaoben-ip-quality/$SCRIPT_VERSION"             --get             --data-urlencode "q=$ip"             --data-urlencode "key=$IPAPI_IS_KEY"             "https://api.ipapi.is/"             2>/dev/null || true
    else
        curl -fsS             --connect-timeout 5             --max-time "$CURL_TIMEOUT"             -A "kkx999-jiaoben-ip-quality/$SCRIPT_VERSION"             --get             --data-urlencode "q=$ip"             "https://api.ipapi.is/"             2>/dev/null || true
    fi
}

query_ipapi_co() {
    local ip="$1"
    curl -fsS         --connect-timeout 5         --max-time "$CURL_TIMEOUT"         -A "kkx999-jiaoben-ip-quality/$SCRIPT_VERSION"         "https://ipapi.co/$ip/json/"         2>/dev/null || true
}

query_dbip() {
    local ip="$1"
    curl -fsS         --connect-timeout 5         --max-time "$CURL_TIMEOUT"         -A "kkx999-jiaoben-ip-quality/$SCRIPT_VERSION"         "http://api.db-ip.com/v2/free/$ip"         2>/dev/null || true
}

show_ip_api() {
    local ip="$1"
    local response=""
    local -a lines=()

    response="$(query_ip_api "$ip")"
    [ -n "$response" ] || {
        echo "[IP-API] 查询失败"
        return 1
    }

    mapfile -t lines <<< "$response"
    [ "${lines[0]:-}" = "success" ] || {
        echo "[IP-API] 查询失败：${lines[1]:-未知原因}"
        return 1
    }

    IPAPI_COUNTRY="${lines[3]:-}"
    IPAPI_COUNTRY_CODE="${lines[4]:-}"
    IPAPI_REGION="${lines[5]:-}"
    IPAPI_CITY="${lines[6]:-}"
    IPAPI_ISP="${lines[7]:-}"
    IPAPI_ORG="${lines[8]:-}"
    IPAPI_ASN="${lines[9]:-}"
    IPAPI_ASNAME="${lines[10]:-}"
    IPAPI_MOBILE="${lines[11]:-}"
    IPAPI_PROXY="${lines[12]:-}"
    IPAPI_HOSTING="${lines[13]:-}"

    echo "[IP-API]"
    echo "  地区：${IPAPI_COUNTRY:-未知} ${IPAPI_REGION:-} ${IPAPI_CITY:-}"
    echo "  ASN ：${IPAPI_ASN:-未知}"
    echo "  ISP ：${IPAPI_ISP:-未知}"
    echo "  组织：${IPAPI_ORG:-未知}"
    echo "  机房：$(bool_text "$IPAPI_HOSTING")"
    echo "  代理：$(risk_text "$IPAPI_PROXY")"
    echo "  移动：$(bool_text "$IPAPI_MOBILE")"
}

show_ipapi_is() {
    local ip="$1"
    local response=""

    response="$(query_ipapi_is "$ip")"
    [ -n "$response" ] || {
        echo "[ipapi.is] 查询失败"
        return 1
    }

    IPAPIIS_COUNTRY="$(json_get "$response" country)"
    IPAPIIS_REGION="$(json_get "$response" region)"
    IPAPIIS_CITY="$(json_get "$response" city)"
    IPAPIIS_COMPANY="$(json_get "$response" company)"
    IPAPIIS_ASN="$(json_get "$response" asn)"
    IPAPIIS_DATACENTER="$(json_get "$response" is_datacenter)"
    IPAPIIS_VPN="$(json_get "$response" is_vpn)"
    IPAPIIS_PROXY="$(json_get "$response" is_proxy)"
    IPAPIIS_TOR="$(json_get "$response" is_tor)"
    IPAPIIS_ABUSER="$(json_get "$response" is_abuser)"

    if [ -z "$IPAPIIS_COUNTRY" ] && [ -z "$IPAPIIS_ASN" ]; then
        echo "[ipapi.is] 已返回数据，但当前系统缺少 python3/jq，无法解析 JSON"
        return 1
    fi

    echo "[ipapi.is]"
    echo "  地区：${IPAPIIS_COUNTRY:-未知} ${IPAPIIS_REGION:-} ${IPAPIIS_CITY:-}"
    echo "  ASN ：${IPAPIIS_ASN:-未知}"
    echo "  公司：${IPAPIIS_COMPANY:-未知}"

    if [ -n "$IPAPI_IS_KEY" ]; then
        echo "  机房：$(bool_text "$IPAPIIS_DATACENTER")"
        echo "  VPN ：$(risk_text "$IPAPIIS_VPN")"
        echo "  代理：$(risk_text "$IPAPIIS_PROXY")"
        echo "  Tor ：$(risk_text "$IPAPIIS_TOR")"
        echo "  滥用：$(risk_text "$IPAPIIS_ABUSER")"
    else
        echo "  风险：匿名接口不提供 VPN/代理/Tor/滥用字段"
    fi
}

show_ipapi_co() {
    local ip="$1"
    local response=""

    response="$(query_ipapi_co "$ip")"
    [ -n "$response" ] || {
        echo "[ipapi.co] 查询失败"
        return 1
    }

    IPAPICO_COUNTRY="$(json_get "$response" country_name)"
    IPAPICO_CODE="$(json_get "$response" country_code)"
    IPAPICO_REGION="$(json_get "$response" region)"
    IPAPICO_CITY="$(json_get "$response" city)"
    IPAPICO_ASN="$(json_get "$response" asn)"
    IPAPICO_ORG="$(json_get "$response" org)"

    if [ -z "$IPAPICO_COUNTRY" ] && [ -z "$IPAPICO_ASN" ]; then
        echo "[ipapi.co] 查询失败或当前系统缺少 python3/jq"
        return 1
    fi

    echo "[ipapi.co]"
    echo "  地区：${IPAPICO_COUNTRY:-未知} ${IPAPICO_REGION:-} ${IPAPICO_CITY:-}"
    echo "  ASN ：${IPAPICO_ASN:-未知}"
    echo "  组织：${IPAPICO_ORG:-未知}"
}

show_dbip() {
    local ip="$1"
    local response=""

    response="$(query_dbip "$ip")"
    [ -n "$response" ] || {
        echo "[DB-IP]"
        echo "  查询失败"
        return 1
    }

    DBIP_COUNTRY="$(json_get "$response" countryName)"
    DBIP_CODE="$(json_get "$response" countryCode)"
    DBIP_REGION="$(json_get "$response" stateProv)"
    DBIP_CITY="$(json_get "$response" city)"

    if [ -z "$DBIP_COUNTRY" ]; then
        echo "[DB-IP] 查询失败或当前系统缺少 python3/jq"
        return 1
    fi

    echo "[DB-IP]"
    echo "  地区：${DBIP_COUNTRY:-未知} ${DBIP_REGION:-} ${DBIP_CITY:-}"
}

show_summary() {
    local risk_found="false"
    local hosting_found="false"

    [ "${IPAPI_PROXY:-}" = "true" ] && risk_found="true"
    [ "${IPAPIIS_PROXY:-}" = "true" ] && risk_found="true"
    [ "${IPAPIIS_VPN:-}" = "true" ] && risk_found="true"
    [ "${IPAPIIS_TOR:-}" = "true" ] && risk_found="true"
    [ "${IPAPIIS_ABUSER:-}" = "true" ] && risk_found="true"

    [ "${IPAPI_HOSTING:-}" = "true" ] && hosting_found="true"
    [ "${IPAPIIS_DATACENTER:-}" = "true" ] && hosting_found="true"

    section_header "多库综合结果"

    if [ "$hosting_found" = "true" ]; then
        echo "网络属性：至少一个质量库判定为机房 / 托管网络"
    else
        echo "网络属性：当前质量库未明确标记为机房 / 托管网络"
    fi

    if [ "$risk_found" = "true" ]; then
        echo "匿名 / 风险：至少一个质量库检测到代理、VPN、Tor 或滥用特征"
    else
        echo "匿名 / 风险：当前已返回的质量库未检测到明确风险特征"
    fi

    if [ -n "${IPAPI_COUNTRY_CODE:-}" ] && [ -n "${IPAPICO_CODE:-}" ] && [ -n "${DBIP_CODE:-}" ]; then
        if [ "$IPAPI_COUNTRY_CODE" = "$IPAPICO_CODE" ] && [ "$IPAPI_COUNTRY_CODE" = "$DBIP_CODE" ]; then
            echo "国家定位：IP-API / ipapi.co / DB-IP 三库一致（$IPAPI_COUNTRY_CODE）"
        else
            echo "国家定位：多库存在差异（IP-API=$IPAPI_COUNTRY_CODE, ipapi.co=$IPAPICO_CODE, DB-IP=$DBIP_CODE）"
        fi
    fi

    echo
    echo "说明：多库结果是交叉参考，不代表绝对准确；代理/VPN/机房数据库可能存在更新延迟。"
    section_footer
}

show_ip_info() {
    local label="$1"
    local ip="$2"

    IPAPI_COUNTRY=""
    IPAPI_COUNTRY_CODE=""
    IPAPI_REGION=""
    IPAPI_CITY=""
    IPAPI_ISP=""
    IPAPI_ORG=""
    IPAPI_ASN=""
    IPAPI_ASNAME=""
    IPAPI_MOBILE=""
    IPAPI_PROXY=""
    IPAPI_HOSTING=""

    IPAPIIS_COUNTRY=""
    IPAPIIS_REGION=""
    IPAPIIS_CITY=""
    IPAPIIS_COMPANY=""
    IPAPIIS_ASN=""
    IPAPIIS_DATACENTER=""
    IPAPIIS_VPN=""
    IPAPIIS_PROXY=""
    IPAPIIS_TOR=""
    IPAPIIS_ABUSER=""

    IPAPICO_COUNTRY=""
    IPAPICO_CODE=""
    IPAPICO_REGION=""
    IPAPICO_CITY=""
    IPAPICO_ASN=""
    IPAPICO_ORG=""

    DBIP_COUNTRY=""
    DBIP_CODE=""
    DBIP_REGION=""
    DBIP_CITY=""

    section_header "$label 多库 IP 质量检测"

    if [ -z "$ip" ]; then
        echo "状态：未检测到可用 $label"
        section_footer
        return 0
    fi

    echo "公网 IP：$ip"
    section_footer

    echo
    show_ip_api "$ip" || true
    echo
    show_ipapi_is "$ip" || true
    echo
    show_ipapi_co "$ip" || true
    echo
    show_dbip "$ip" || true

    show_summary
}

main() {
    local ipv4 ipv6

    ipv4="$(get_public_ipv4)"
    ipv6="$(get_public_ipv6)"

    clear 2>/dev/null || true

    section_header "多库 IP 质量检测"
    echo "脚本版本：$SCRIPT_VERSION"
    echo "数据源：IP-API / ipapi.is / ipapi.co / DB-IP"
    echo "无广告 · 无推广 · 不修改系统配置"
    if [ -n "$IPAPI_IS_KEY" ]; then
        echo "ipapi.is：已启用完整风险字段"
    else
        echo "ipapi.is：匿名模式（可选设置 IPAPI_IS_KEY 获取完整风险字段）"
    fi
    section_footer

    show_ip_info "IPv4" "$ipv4"
    show_ip_info "IPv6" "$ipv6"
}

main "$@"
