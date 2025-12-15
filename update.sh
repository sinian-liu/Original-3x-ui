#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

# 请不要编辑此配置
b_source="${BASH_SOURCE[0]}"
while [ -h "$b_source" ]; do
    b_dir="$(cd -P "$(dirname "$b_source")" >/dev/null 2>&1 && pwd || pwd -P)"
    b_source="$(readlink "$b_source")"
    [[ $b_source != /* ]] && b_source="$b_dir/$b_source"
done
cur_dir="$(cd -P "$(dirname "$b_source")" >/dev/null 2>&1 && pwd || pwd -P)"
script_name=$(basename "$0")

# 检查命令是否存在函数
_command_exists() {
    type "$1" &>/dev/null
}

# 失败、记录并退出脚本函数
_fail() {
    local msg=${1}
    echo -e "${red}${msg}${plain}"
    exit 2
}

# 检查root权限
[[ $EUID -ne 0 ]] && _fail "严重错误：请使用root权限运行此脚本。"

if _command_exists wget; then
    wget_bin=$(which wget)
else
    _fail "错误：未找到'wget'命令。"
fi

if _command_exists curl; then
    curl_bin=$(which curl)
else
    _fail "错误：未找到'curl'命令。"
fi

# 检查操作系统并设置发行版变量
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
    elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    _fail "无法检测系统操作系统，请联系作者！"
fi
echo "操作系统发行版：$release"

arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
        armv7* | armv7 | arm) echo 'armv7' ;;
        armv6* | armv6) echo 'armv6' ;;
        armv5* | armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo -e "${red}不支持的CPU架构！${plain}" && rm -f "${cur_dir}/${script_name}" >/dev/null 2>&1 && exit 2;;
    esac
}

echo "系统架构：$(arch)"

install_base() {
    echo -e "${green}正在更新和安装依赖包...${plain}"
    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update >/dev/null 2>&1 && apt-get install -y -q wget curl tar tzdata >/dev/null 2>&1
        ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf -y update >/dev/null 2>&1 && dnf install -y -q wget curl tar tzdata >/dev/null 2>&1
        ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum -y update >/dev/null 2>&1 && yum install -y -q wget curl tar tzdata >/dev/null 2>&1
            else
                dnf -y update >/dev/null 2>&1 && dnf install -y -q wget curl tar tzdata >/dev/null 2>&1
            fi
        ;;
        arch | manjaro | parch)
            pacman -Syu >/dev/null 2>&1 && pacman -Syu --noconfirm wget curl tar tzdata >/dev/null 2>&1
        ;;
        opensuse-tumbleweed | opensuse-leap)
            zypper refresh >/dev/null 2>&1 && zypper -q install -y wget curl tar timezone >/dev/null 2>&1
        ;;
        alpine)
            apk update >/dev/null 2>&1 && apk add wget curl tar tzdata >/dev/null 2>&1
        ;;
        *)
            apt-get update >/dev/null 2>&1 && apt install -y -q wget curl tar tzdata >/dev/null 2>&1
        ;;
    esac
}

config_after_update() {
    echo -e "${yellow}x-ui 设置信息：${plain}"
    /usr/local/x-ui/x-ui setting -show true
    /usr/local/x-ui/x-ui migrate
}

update_x-ui() {
    cd /usr/local/
    
    if [ -f "/usr/local/x-ui/x-ui" ]; then
        current_xui_version=$(/usr/local/x-ui/x-ui -v)
        echo -e "${green}当前 x-ui 版本：${current_xui_version}${plain}"
    else
        _fail "错误：当前 x-ui 版本：未知"
    fi
    
    echo -e "${green}正在下载新版本 x-ui...${plain}"
    
    tag_version=$(${curl_bin} -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ ! -n "$tag_version" ]]; then
        echo -e "${yellow}正在尝试使用IPv4获取版本...${plain}"
        tag_version=$(${curl_bin} -4 -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$tag_version" ]]; then
            _fail "错误：获取 x-ui 版本失败，可能是由于GitHub API限制，请稍后重试"
        fi
    fi
    echo -e "获取到 x-ui 最新版本：${tag_version}，开始安装..."
    ${wget_bin} -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${yellow}正在尝试使用IPv4获取版本...${plain}"
        ${wget_bin} --inet4-only -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz 2>/dev/null
        if [[ $? -ne 0 ]]; then
            _fail "错误：下载 x-ui 失败，请确保您的服务器可以访问 GitHub"
        fi
    fi
    
    if [[ -e /usr/local/x-ui/ ]]; then
        echo -e "${green}正在停止 x-ui 服务...${plain}"
        if [[ $release == "alpine" ]]; then
            if [ -f "/etc/init.d/x-ui" ]; then
                rc-service x-ui stop >/dev/null 2>&1
                rc-update del x-ui >/dev/null 2>&1
                echo -e "${green}正在移除旧版本服务单元...${plain}"
                rm -f /etc/init.d/x-ui >/dev/null 2>&1
            else
                rm x-ui-linux-$(arch).tar.gz -f >/dev/null 2>&1
                _fail "错误：x-ui 服务单元未安装。"
            fi
        else
            if [ -f "/etc/systemd/system/x-ui.service" ]; then
                systemctl stop x-ui >/dev/null 2>&1
                systemctl disable x-ui >/dev/null 2>&1
                echo -e "${green}正在移除旧版本systemd单元...${plain}"
                rm /etc/systemd/system/x-ui.service -f >/dev/null 2>&1
                systemctl daemon-reload >/dev/null 2>&1
            else
                rm x-ui-linux-$(arch).tar.gz -f >/dev/null 2>&1
                _fail "错误：x-ui systemd单元未安装。"
            fi
        fi
        echo -e "${green}正在移除旧版本 x-ui...${plain}"
        rm /usr/bin/x-ui -f >/dev/null 2>&1
        rm /usr/local/x-ui/x-ui.service -f >/dev/null 2>&1
        rm /usr/local/x-ui/x-ui -f >/dev/null 2>&1
        rm /usr/local/x-ui/x-ui.sh -f >/dev/null 2>&1
        echo -e "${green}正在移除旧版本 xray...${plain}"
        rm /usr/local/x-ui/bin/xray-linux-amd64 -f >/dev/null 2>&1
        echo -e "${green}正在移除旧的README和LICENSE文件...${plain}"
        rm /usr/local/x-ui/bin/README.md -f >/dev/null 2>&1
        rm /usr/local/x-ui/bin/LICENSE -f >/dev/null 2>&1
    else
        rm x-ui-linux-$(arch).tar.gz -f >/dev/null 2>&1
        _fail "错误：x-ui 未安装。"
    fi
    
    echo -e "${green}正在安装新版本 x-ui...${plain}"
    tar zxvf x-ui-linux-$(arch).tar.gz >/dev/null 2>&1
    rm x-ui-linux-$(arch).tar.gz -f >/dev/null 2>&1
    cd x-ui >/dev/null 2>&1
    chmod +x x-ui >/dev/null 2>&1
    
    # 检查系统架构并相应重命名文件
    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm >/dev/null 2>&1
        chmod +x bin/xray-linux-arm >/dev/null 2>&1
    fi
    
    chmod +x x-ui bin/xray-linux-$(arch) >/dev/null 2>&1
    
    echo -e "${green}正在下载并安装 x-ui.sh 脚本...${plain}"
    ${wget_bin} -O /usr/bin/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo -e "${yellow}正在尝试使用IPv4获取 x-ui...${plain}"
        ${wget_bin} --inet4-only -O /usr/bin/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh >/dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            _fail "错误：下载 x-ui.sh 脚本失败，请确保您的服务器可以访问 GitHub"
        fi
    fi
    
    chmod +x /usr/local/x-ui/x-ui.sh >/dev/null 2>&1
    chmod +x /usr/bin/x-ui >/dev/null 2>&1
    
    echo -e "${green}正在更改所有者...${plain}"
    chown -R root:root /usr/local/x-ui >/dev/null 2>&1
    
    if [ -f "/usr/local/x-ui/bin/config.json" ]; then
        echo -e "${green}正在更改配置文件权限...${plain}"
        chmod 640 /usr/local/x-ui/bin/config.json >/dev/null 2>&1
    fi
    
    if [[ $release == "alpine" ]]; then
        echo -e "${green}正在下载并安装启动单元 x-ui.rc...${plain}"
        ${wget_bin} -O /etc/init.d/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.rc >/dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            ${wget_bin} --inet4-only -O /etc/init.d/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.rc >/dev/null 2>&1
            if [[ $? -ne 0 ]]; then
                _fail "错误：下载启动单元 x-ui.rc 失败，请确保您的服务器可以访问 GitHub"
            fi
        fi
        chmod +x /etc/init.d/x-ui >/dev/null 2>&1
        chown root:root /etc/init.d/x-ui >/dev/null 2>&1
        rc-update add x-ui >/dev/null 2>&1
        rc-service x-ui start >/dev/null 2>&1
    else
        echo -e "${green}正在安装 systemd 单元...${plain}"
        cp -f x-ui.service /etc/systemd/system/ >/dev/null 2>&1
        chown root:root /etc/systemd/system/x-ui.service >/dev/null 2>&1
        systemctl daemon-reload >/dev/null 2>&1
        systemctl enable x-ui >/dev/null 2>&1
        systemctl start x-ui >/dev/null 2>&1
    fi
    
    config_after_update
    
    echo -e "${green}x-ui ${tag_version}${plain} 更新完成，正在运行中..."
    echo -e ""
    echo -e "┌───────────────────────────────────────────────────────┐
│  ${blue}x-ui 控制菜单使用方法（子命令）:${plain}              │
│                                                       │
│  ${blue}x-ui${plain}              - 管理脚本                   │
│  ${blue}x-ui start${plain}        - 启动服务                   │
│  ${blue}x-ui stop${plain}         - 停止服务                   │
│  ${blue}x-ui restart${plain}      - 重启服务                   │
│  ${blue}x-ui status${plain}       - 服务状态                   │
│  ${blue}x-ui settings${plain}     - 当前设置                   │
│  ${blue}x-ui enable${plain}       - 启用开机自启动             │
│  ${blue}x-ui disable${plain}      - 禁用开机自启动             │
│  ${blue}x-ui log${plain}          - 查看日志                   │
│  ${blue}x-ui banlog${plain}       - 查看Fail2ban封禁日志       │
│  ${blue}x-ui update${plain}       - 更新                       │
│  ${blue}x-ui legacy${plain}       - 旧版本                     │
│  ${blue}x-ui install${plain}      - 安装                       │
│  ${blue}x-ui uninstall${plain}    - 卸载                       │
└───────────────────────────────────────────────────────┘"
}

echo -e "${green}正在运行...${plain}"
install_base
update_x-ui $1
