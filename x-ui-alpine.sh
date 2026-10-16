#!/bin/sh
set -eu

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

REPO="alireza0/x-ui"
MENU_URL="https://raw.githubusercontent.com/kkx999/jiaoben/main/x-ui-alpine-menu.sh"

if [ "$(id -u)" -ne 0 ]; then
    printf "%b\n" "${red}Fatal error: ${plain} Please run this script with root privilege"
    exit 1
fi

if [ ! -f /etc/alpine-release ]; then
    printf "%b\n" "${red}Fatal error: ${plain} This script is only for Alpine Linux."
    exit 1
fi

arch() {
    case "$(uname -m)" in
        x86_64|x64|amd64) echo amd64 ;;
        i*86|x86) echo 386 ;;
        armv8*|armv8|arm64|aarch64) echo arm64 ;;
        armv7*|armv7|arm) echo armv7 ;;
        armv6*|armv6) echo armv6 ;;
        armv5*|armv5) echo armv5 ;;
        s390x) echo s390x ;;
        *) printf "%b\n" "${red}Unsupported CPU architecture! ${plain}"; exit 1 ;;
    esac
}

gen_random_string() {
    length="$1"
    LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1
}

random_port() {
    n="$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"
    echo $((1024 + n % 60977))
}

read_tty() {
    var="$1"
    if [ -e /dev/tty ]; then
        IFS= read -r "$var" </dev/tty || true
    else
        IFS= read -r "$var" || true
    fi
}

install_dependencies() {
    echo "Installing Alpine dependencies..."
    apk add --no-cache bash wget curl tar tzdata ca-certificates nftables openrc
    update-ca-certificates >/dev/null 2>&1 || true
}

config_after_install() {
    existing_username=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null | grep -Eo 'username: .+' | awk '{print $2}' || true)
    existing_password=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null | grep -Eo 'password: .+' | awk '{print $2}' || true)
    existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null | grep -Eo 'webBasePath: .+' | awk '{print $2}' || true)

    if [ ${#existing_webBasePath} -lt 4 ]; then
        if [ "$existing_username" = "admin" ] && [ "$existing_password" = "admin" ]; then
            config_webBasePath="${XUI_WEB_BASE_PATH:-$(gen_random_string 15)}"
            config_username="${XUI_USERNAME:-$(gen_random_string 10)}"
            config_password="${XUI_PASSWORD:-$(gen_random_string 10)}"
            config_port="${XUI_PANEL_PORT:-}"

            if [ -n "$config_port" ]; then
                echo -e "${yellow}Your Panel Port is: ${config_port}${plain}"
            elif [ "${XUI_NONINTERACTIVE:-0}" != "1" ]; then
                config_confirm=""
                printf "Would you like to customize the Panel Port settings? (If not, random port will be applied) [y/n]: "
                read_tty config_confirm
                if [ "$config_confirm" = "y" ] || [ "$config_confirm" = "Y" ]; then
                    while :; do
                        printf "Please set up the panel port: "
                        read_tty config_port
                        case "$config_port" in
                            ''|*[!0-9]*) echo "Invalid port, please try again."; continue ;;
                        esac
                        if [ "$config_port" -ge 1 ] && [ "$config_port" -le 65535 ]; then
                            break
                        fi
                        echo "Invalid port, please try again."
                    done
                    echo -e "${yellow}Your Panel Port is: ${config_port}${plain}"
                else
                    config_port="$(random_port)"
                    echo -e "${yellow}Generated random port: ${config_port}${plain}"
                fi
            else
                config_port="$(random_port)"
                echo -e "${yellow}Generated random port: ${config_port}${plain}"
            fi

            /usr/local/x-ui/x-ui setting -username "$config_username" -password "$config_password" -port "$config_port" -webBasePath "$config_webBasePath"
            echo "This is a fresh installation, generating random login info for security concerns:"
            echo "###############################################"
            echo -e "${green}Username: ${config_username}${plain}"
            echo -e "${green}Password: ${config_password}${plain}"
            echo -e "${green}Port: ${config_port}${plain}"
            echo -e "${green}WebBasePath: ${config_webBasePath}${plain}"
            echo "###############################################"
            echo -e "${yellow}If you forgot your login info, you can type 'x-ui settings' to check${plain}"
        else
            config_webBasePath="$(gen_random_string 15)"
            echo -e "${yellow}WebBasePath is missing or too short. Generating a new one...${plain}"
            /usr/local/x-ui/x-ui setting -webBasePath "$config_webBasePath"
            echo -e "${green}New WebBasePath: ${config_webBasePath}${plain}"
        fi
    else
        if [ "$existing_username" = "admin" ] && [ "$existing_password" = "admin" ]; then
            config_username="$(gen_random_string 10)"
            config_password="$(gen_random_string 10)"
            echo -e "${yellow}Default credentials detected. Security update required...${plain}"
            /usr/local/x-ui/x-ui setting -username "$config_username" -password "$config_password"
            echo "Generated new random login credentials:"
            echo "###############################################"
            echo -e "${green}Username: ${config_username}${plain}"
            echo -e "${green}Password: ${config_password}${plain}"
            echo "###############################################"
            echo -e "${yellow}If you forgot your login info, you can type 'x-ui settings' to check${plain}"
        else
            echo -e "${green}Username, Password, and WebBasePath are properly set. Exiting...${plain}"
        fi
    fi

    /usr/local/x-ui/x-ui migrate
}

create_openrc_service() {
    cat > /etc/init.d/x-ui <<'EOF'
#!/sbin/openrc-run

name="x-ui"
description="X-UI Panel"
command="/usr/local/x-ui/x-ui"
command_args=""
directory="/usr/local/x-ui"
command_background="true"
pidfile="/run/x-ui.pid"
output_log="/var/log/x-ui.log"
error_log="/var/log/x-ui-error.log"
supervisor="supervise-daemon"
respawn_delay=5
export XRAY_VMESS_AEAD_FORCED=false

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath --directory /var/log
    touch /var/log/x-ui.log /var/log/x-ui-error.log
    chmod 600 /var/log/x-ui.log /var/log/x-ui-error.log
}

extra_started_commands="reload"

reload() {
    ebegin "Reloading x-ui"
    start-stop-daemon --signal HUP --pidfile "$pidfile"
    eend $?
}
EOF
    chmod 755 /etc/init.d/x-ui
}

install_x_ui() {
    if [ -d /usr/local/x-ui-backup ]; then
        if [ "${XUI_NONINTERACTIVE:-0}" = "1" ]; then
            restore_confirm="n"
        else
            printf "Failed installation detected. Do you want to restore previously installed version? [y/n]? "
            read_tty restore_confirm
        fi
        if [ "$restore_confirm" = "y" ] || [ "$restore_confirm" = "Y" ]; then
            rc-service x-ui stop >/dev/null 2>&1 || true
            if [ -f /usr/local/x-ui-backup/x-ui.db ]; then
                mv -f /usr/local/x-ui-backup/x-ui.db /etc/x-ui/
            fi
            rm -rf /usr/local/x-ui
            mv -f /usr/local/x-ui-backup /usr/local/x-ui
            rc-service x-ui start >/dev/null 2>&1 || true
            echo -e "${green}previous installed x-ui restored successfully${plain}, it is up and running now..."
            exit 0
        else
            echo -e "Continuing installing x-ui ..."
        fi
    fi

    cd /usr/local/

    if [ "$#" -eq 0 ]; then
        last_version="$(curl -Ls "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | head -n 1)"
        if [ -z "$last_version" ]; then
            echo -e "${red}Failed to fetch x-ui version, it maybe due to Github API restrictions, please try it later${plain}"
            exit 1
        fi
        echo -e "Got x-ui latest version: ${last_version}, beginning the installation..."
        url="https://github.com/${REPO}/releases/download/${last_version}/x-ui-linux-$(arch).tar.gz"
    else
        last_version="$1"
        url="https://github.com/${REPO}/releases/download/${last_version}/x-ui-linux-$(arch).tar.gz"
        echo -e "Beginning to install x-ui ${last_version}"
    fi

    package="/usr/local/x-ui-linux-$(arch).tar.gz"
    wget -N --no-check-certificate -O "$package" "$url"
    if [ "$?" -ne 0 ]; then
        echo -e "${red}Downloading x-ui failed, please be sure that your server can access Github ${plain}"
        exit 1
    fi

    if [ -d /usr/local/x-ui ]; then
        rc-service x-ui stop >/dev/null 2>&1 || true
        rm -rf /usr/local/x-ui-backup
        mv /usr/local/x-ui /usr/local/x-ui-backup
        if [ -f /etc/x-ui/x-ui.db ]; then
            cp -f /etc/x-ui/x-ui.db /usr/local/x-ui-backup/x-ui.db
        fi
    fi

    tar zxvf "$package" -C /usr/local
    rm -f "$package"

    if [ ! -x /usr/local/x-ui/x-ui ]; then
        echo -e "${red}X-UI extraction failed.${plain}"
        exit 1
    fi

    chmod +x /usr/local/x-ui/x-ui /usr/local/x-ui/x-ui.sh 2>/dev/null || true
    chmod +x /usr/local/x-ui/bin/xray-linux-* 2>/dev/null || true

    if [ "$(arch)" = "armv7" ] && [ -f /usr/local/x-ui/bin/xray-linux-armv7 ]; then
        mv -f /usr/local/x-ui/bin/xray-linux-armv7 /usr/local/x-ui/bin/xray-linux-arm
        chmod +x /usr/local/x-ui/bin/xray-linux-arm
    fi

    mkdir -p /etc/x-ui
    create_openrc_service

    if ! wget --no-check-certificate -O /usr/bin/x-ui "$MENU_URL"; then
        echo -e "${red}Failed to download Alpine x-ui management script.${plain}"
        exit 1
    fi
    chmod +x /usr/bin/x-ui

    if [ -f /usr/local/x-ui-backup/x-ui.db ]; then
        cp -f /usr/local/x-ui-backup/x-ui.db /etc/x-ui/x-ui.db
        chmod 600 /etc/x-ui/x-ui.db
    fi

    config_after_install
    rm -rf /usr/local/x-ui-backup

    rc-update add x-ui default >/dev/null 2>&1 || true
    rc-service x-ui start

    echo -e "${green}x-ui ${last_version}${plain} installation finished, it is up and running now..."
    echo
    echo -e "You may access the Panel with following URL(s):${yellow}"
    /usr/local/x-ui/x-ui uri
    echo -e "${plain}"
    echo "X-UI Control Menu Usage"
    echo "------------------------------------------"
    echo "x-ui              - Admin Management Script"
    echo "x-ui start        - Start"
    echo "x-ui stop         - Stop"
    echo "x-ui restart      - Restart"
    echo "x-ui status       - Current Status"
    echo "x-ui settings     - Current Settings"
    echo "x-ui enable      - Enable Autostart on OS Startup"
    echo "x-ui disable     - Disable Autostart on OS Startup"
    echo "x-ui log          - Check Logs"
    echo "x-ui update       - Update"
    echo "x-ui install      - Install"
    echo "x-ui uninstall    - Uninstall"
    echo "x-ui help         - Control Menu Usage"
    echo "------------------------------------------"
}

echo -e "${green}Running...${plain}"
install_dependencies
install_x_ui "$@"
