#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# 检查root权限
[[ $EUID -ne 0 ]] && echo -e "${red}严重错误：${plain} 请使用root权限运行此脚本 \n " && exit 1

# 检查操作系统并设置发行版变量
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
    elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "无法检测系统操作系统，请联系作者！" >&2
    exit 1
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
        *) echo -e "${green}不支持的CPU架构！${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "系统架构：$(arch)"

install_base() {
    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum -y update && yum install -y wget curl tar tzdata
            else
                dnf -y update && dnf install -y -q wget curl tar tzdata
            fi
        ;;
        arch | manjaro | parch)
            pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata
        ;;
        opensuse-tumbleweed | opensuse-leap)
            zypper refresh && zypper -q install -y wget curl tar timezone
        ;;
        alpine)
            apk update && apk add wget curl tar tzdata
        ;;
        *)
            apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    esac
}

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

config_after_install() {
    local existing_hasDefaultCredential=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}')
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    local URL_lists=(
        "https://api4.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://v4.api.ipinfo.io/ip"
        "https://ipv4.myexternalip.com/raw"
        "https://4.ident.me"
        "https://check-host.net/ip"
    )
    local server_ip=""
    for ip_address in "${URL_lists[@]}"; do
        server_ip=$(curl -s --max-time 3 "${ip_address}" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "${server_ip}" ]]; then
            break
        fi
    done
    
    if [[ ${#existing_webBasePath} -lt 4 ]]; then
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_webBasePath=$(gen_random_string 18)
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)
            
            read -rp "是否自定义面板端口设置？(如果不设置，将使用随机端口) [y/n]: " config_confirm
            if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
                read -rp "请设置面板端口: " config_port
                echo -e "${yellow}您的面板端口: ${config_port}${plain}"
            else
                local config_port=$(shuf -i 1024-62000 -n 1)
                echo -e "${yellow}生成的随机端口: ${config_port}${plain}"
            fi
            
            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}" -port "${config_port}" -webBasePath "${config_webBasePath}"
            echo -e "这是全新安装，为安全考虑生成随机登录信息："
            echo -e "###############################################"
            echo -e "${green}用户名: ${config_username}${plain}"
            echo -e "${green}密码: ${config_password}${plain}"
            echo -e "${green}端口: ${config_port}${plain}"
            echo -e "${green}WebBasePath: ${config_webBasePath}${plain}"
            echo -e "${green}访问地址: http://${server_ip}:${config_port}/${config_webBasePath}${plain}"
            echo -e "###############################################"
        else
            local config_webBasePath=$(gen_random_string 18)
            echo -e "${yellow}WebBasePath 缺失或太短。生成新的路径...${plain}"
            /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}"
            echo -e "${green}新的 WebBasePath: ${config_webBasePath}${plain}"
            echo -e "${green}访问地址: http://${server_ip}:${existing_port}/${config_webBasePath}${plain}"
        fi
    else
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)
            
            echo -e "${yellow}检测到默认凭据。需要安全更新...${plain}"
            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}"
            echo -e "已生成新的随机登录凭据："
            echo -e "###############################################"
            echo -e "${green}用户名: ${config_username}${plain}"
            echo -e "${green}密码: ${config_password}${plain}"
            echo -e "###############################################"
        else
            echo -e "${green}用户名、密码和WebBasePath已正确设置。退出...${plain}"
        fi
    fi
    
    /usr/local/x-ui/x-ui migrate
}

# 汉化管理菜单函数
chinese_menu() {
    local xui_file="/usr/bin/x-ui"
    
    if [ ! -f "$xui_file" ]; then
        echo -e "${yellow}警告：$xui_file 文件不存在，跳过汉化${plain}"
        return 1
    fi
    
    echo -e "${green}正在汉化管理菜单...${plain}"
    
    # 备份原文件
    cp "$xui_file" "${xui_file}.backup.$(date +%Y%m%d%H%M%S)" >/dev/null 2>&1
    
    # 汉化主要菜单项
    sed -i 's/3X-UI Panel Management Script/3X-UI 面板管理脚本/g' "$xui_file"
    sed -i 's/Exit Script/退出脚本/g' "$xui_file"
    sed -i 's/Install/安装/g' "$xui_file"
    sed -i 's/Update/更新/g' "$xui_file"
    sed -i 's/Update Menu/更新菜单/g' "$xui_file"
    sed -i 's/Legacy Version/旧版本/g' "$xui_file"
    sed -i 's/Uninstall/卸载/g' "$xui_file"
    sed -i 's/Reset Username \& Password/重置用户名和密码/g' "$xui_file"
    sed -i 's/Reset Web Base Path/重置Web基础路径/g' "$xui_file"
    sed -i 's/Reset Settings/重置设置/g' "$xui_file"
    sed -i 's/Change Port/更改端口/g' "$xui_file"
    sed -i 's/View Current Settings/查看当前设置/g' "$xui_file"
    sed -i 's/Start/启动/g' "$xui_file"
    sed -i 's/Stop/停止/g' "$xui_file"
    sed -i 's/Restart/重启/g' "$xui_file"
    sed -i 's/Check Status/检查状态/g' "$xui_file"
    sed -i 's/Logs Management/日志管理/g' "$xui_file"
    sed -i 's/Enable Autostart/启用自启动/g' "$xui_file"
    sed -i 's/Disable Autostart/禁用自启动/g' "$xui_file"
    sed -i 's/SSL Certificate Management/SSL证书管理/g' "$xui_file"
    sed -i 's/Cloudflare SSL Certificate/Cloudflare SSL证书/g' "$xui_file"
    sed -i 's/IP Limit Management/IP限制管理/g' "$xui_file"
    sed -i 's/Firewall Management/防火墙管理/g' "$xui_file"
    sed -i 's/SSH Port Forwarding Management/SSH端口转发管理/g' "$xui_file"
    sed -i 's/Enable BBR/启用BBR/g' "$xui_file"
    sed -i 's/Update Geo Files/更新Geo文件/g' "$xui_file"
    sed -i 's/Speedtest by Ookla/Ookla速度测试/g' "$xui_file"
    sed -i 's/Panel state:/面板状态:/g' "$xui_file"
    sed -i 's/Start automatically:/自启动:/g' "$xui_file"
    sed -i 's/xray state:/xray状态:/g' "$xui_file"
    sed -i 's/Please enter your selection/请输入您的选择/g' "$xui_file"
    
    # 汉化子菜单和选项
    sed -i 's/Version:/版本:/g' "$xui_file"
    sed -i 's/Domain:/域名:/g' "$xui_file"
    sed -i 's/Port:/端口:/g' "$xui_file"
    sed -i 's/Username:/用户名:/g' "$xui_file"
    sed -i 's/Password:/密码:/g' "$xui_file"
    sed -i 's/Base URI Path:/基础URI路径:/g' "$xui_file"
    sed -i 's/Web Base Path:/网页基础路径:/g' "$xui_file"
    sed -i 's/Cert File:/证书文件:/g' "$xui_file"
    sed -i 's/Key File:/密钥文件:/g' "$xui_file"
    sed -i 's/DNS Provider:/DNS提供商:/g' "$xui_file"
    sed -i 's/Email:/邮箱:/g' "$xui_file"
    sed -i 's/API Token:/API令牌:/g' "$xui_file"
    sed -i 's/Enter your selection/请输入您的选择/g' "$xui_file"
    sed -i 's/Invalid option/无效选项/g' "$xui_file"
    sed -i 's/Operation cancelled/操作已取消/g' "$xui_file"
    sed -i 's/Successfully/成功/g' "$xui_file"
    sed -i 's/Failed/失败/g' "$xui_file"
    sed -i 's/Error/错误/g' "$xui_file"
    sed -i 's/Warning/警告/g' "$xui_file"
    sed -i 's/Info/信息/g' "$xui_file"
    sed -i 's/Confirm/确认/g' "$xui_file"
    sed -i 's/Cancel/取消/g' "$xui_file"
    sed -i 's/Back/返回/g' "$xui_file"
    sed -i 's/Next/下一步/g' "$xui_file"
    sed -i 's/Finish/完成/g' "$xui_file"
    sed -i 's/Are you sure/您确定吗/g' "$xui_file"
    sed -i 's/Yes/是/g' "$xui_file"
    sed -i 's/No/否/g' "$xui_file"
    sed -i 's/Processing/处理中/g' "$xui_file"
    sed -i 's/Completed/已完成/g' "$xui_file"
    sed -i 's/Running/运行中/g' "$xui_file"
    sed -i 's/Stopped/已停止/g' "$xui_file"
    sed -i 's/Enabled/已启用/g' "$xui_file"
    sed -i 's/Disabled/已禁用/g' "$xui_file"
    
    echo -e "${green}管理菜单已汉化完成！${plain}"
}

install_x-ui() {
    cd /usr/local/
    
    # 下载资源
    if [ $# == 0 ]; then
        tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$tag_version" ]]; then
            echo -e "${yellow}尝试使用IPv4获取版本...${plain}"
            tag_version=$(curl -4 -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
            if [[ ! -n "$tag_version" ]]; then
                echo -e "${red}获取 x-ui 版本失败，可能是由于GitHub API限制，请稍后重试${plain}"
                exit 1
            fi
        fi
        echo -e "获取到 x-ui 最新版本: ${tag_version}，开始安装..."
        wget --inet4-only -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 x-ui 失败，请确保您的服务器可以访问 GitHub ${plain}"
            exit 1
        fi
    else
        tag_version=$1
        tag_version_numeric=${tag_version#v}
        min_version="2.3.5"
        
        if [[ "$(printf '%s\n' "$min_version" "$tag_version_numeric" | sort -V | head -n1)" != "$min_version" ]]; then
            echo -e "${red}请使用更新版本（至少 v2.3.5）。退出安装。${plain}"
            exit 1
        fi
        
        url="https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz"
        echo -e "开始安装 x-ui $1"
        wget --inet4-only -N -O /usr/local/x-ui-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 x-ui $1 失败，请检查版本是否存在 ${plain}"
            exit 1
        fi
    fi
    
    # 首先下载原始英文版脚本
    echo -e "${green}下载 x-ui 管理脚本...${plain}"
    wget --inet4-only -O /usr/bin/x-ui-temp https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载 x-ui.sh 失败${plain}"
        exit 1
    fi
    
    # 停止x-ui服务并移除旧资源
    if [[ -e /usr/local/x-ui/ ]]; then
        if [[ $release == "alpine" ]]; then
            rc-service x-ui stop
        else
            systemctl stop x-ui
        fi
        rm /usr/local/x-ui/ -rf
    fi
    
    # 解压资源并设置权限
    tar zxvf x-ui-linux-$(arch).tar.gz
    rm x-ui-linux-$(arch).tar.gz -f
    
    cd x-ui
    chmod +x x-ui
    chmod +x x-ui.sh
    
    # 检查系统架构并相应重命名文件
    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi
    chmod +x x-ui bin/xray-linux-$(arch)
    
    # 更新x-ui cli并设置权限
    mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
    chmod +x /usr/bin/x-ui
    
    # 安装后配置
    config_after_install
    
    # 自动汉化管理菜单
    chinese_menu
    
    if [[ $release == "alpine" ]]; then
        wget --inet4-only -O /etc/init.d/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.rc
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 x-ui.rc 失败${plain}"
            exit 1
        fi
        chmod +x /etc/init.d/x-ui
        rc-update add x-ui
        rc-service x-ui start
    else
        cp -f x-ui.service /etc/systemd/system/
        systemctl daemon-reload
        systemctl enable x-ui
        systemctl start x-ui
    fi
    
    echo -e "${green}x-ui ${tag_version}${plain} 安装完成，正在运行中..."
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
    
    echo -e ""
    echo -e "${green}提示：管理菜单已自动汉化，运行 'x-ui' 查看中文菜单${plain}"
}

echo -e "${green}正在运行...${plain}"
install_base
install_x-ui $1
