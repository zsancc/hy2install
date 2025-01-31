#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 全局变量
HY_VERSION="2.0.0"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/hysteria"
LOG_DIR="/var/log/hysteria"
DATA_DIR="/var/lib/hysteria"
SERVICE_DIR="/etc/init.d"
DEFAULT_PORT=5525
DEFAULT_MASQ="https://news.ycombinator.com/"
GITHUB_API_URL="https://api.github.com/repos/apernet/hysteria"

# 错误处理
error() {
    echo -e "${RED}错误${PLAIN}: $1"
    exit 1
}

info() {
    echo -e "${GREEN}信息${PLAIN}: $1"
}

warn() {
    echo -e "${YELLOW}警告${PLAIN}: $1"
}

confirm() {
    read -p "$1 [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 检查root权限
check_root() {
    [[ $EUID -ne 0 ]] && error "必须使用root用户运行此脚本！"
}

# 检查依赖是否已安装
check_package() {
    local pkg=$1
    case "$PKG_MANAGER" in
        "apk")
            apk info -e "$pkg" > /dev/null 2>&1
            ;;
        "apt")
            dpkg -l "$pkg" > /dev/null 2>&1
            ;;
        "yum"|"dnf")
            rpm -q "$pkg" > /dev/null 2>&1
            ;;
    esac
}

# 检查系统类型
check_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            "alpine")
                PKG_MANAGER="apk"
                PKG_UPDATE="apk update"
                PKG_INSTALL="apk add"
                USE_OPENRC=true
                ;;
            "debian"|"ubuntu")
                PKG_MANAGER="apt"
                PKG_UPDATE="apt update"
                PKG_INSTALL="apt install -y"
                USE_OPENRC=false
                ;;
            "centos"|"rhel"|"fedora")
                if command -v dnf >/dev/null 2>&1; then
                    PKG_MANAGER="dnf"
                    PKG_UPDATE="dnf check-update"
                    PKG_INSTALL="dnf install -y"
                else
                    PKG_MANAGER="yum"
                    PKG_UPDATE="yum check-update"
                    PKG_INSTALL="yum install -y"
                fi
                USE_OPENRC=false
                ;;
            *)
                error "不支持的系统: $ID"
                ;;
        esac
    else
        error "无法确定系统类型"
    fi
}

# 安装依赖
install_deps() {
    local missing_deps=()
    
    # 定义基础依赖
    local base_deps="curl wget tar unzip"
    
    # 定义系统特定依赖
    case "$PKG_MANAGER" in
        "apk")
            base_deps="$base_deps libqrencode bash coreutils openssl iptables"
            if ! grep -q "^http.*community" /etc/apk/repositories; then
                echo "https://dl-cdn.alpinelinux.org/alpine/latest-stable/community" >> /etc/apk/repositories
            fi
            ;;
        "apt")
            base_deps="$base_deps qrencode"
            ;;
        "yum"|"dnf")
            base_deps="$base_deps qrencode"
            ;;
    esac
    
    # 检查缺少的依赖
    for pkg in $base_deps; do
        if ! check_package "$pkg"; then
            missing_deps+=("$pkg")
        fi
    done
    
    # 如果有缺少的依赖，则安装
    if [ ${#missing_deps[@]} -gt 0 ]; then
        info "正在安装缺少的依赖: ${missing_deps[*]}"
        if [ "$PKG_MANAGER" = "apk" ]; then
            if ! $PKG_UPDATE; then
                error "更新包索引失败，请检查网络连接和源配置"
            fi
            for pkg in "${missing_deps[@]}"; do
                if ! $PKG_INSTALL "$pkg"; then
                    error "安装 $pkg 失败"
                fi
            done
        else
            $PKG_UPDATE
            if ! $PKG_INSTALL "${missing_deps[@]}"; then
                error "依赖安装失败: ${missing_deps[*]}"
            fi
        fi
        info "依赖安装完成"
    fi
}

# 配置防火墙
configure_firewall() {
    local port=$1
    
    # 检查是否已安装防火墙
    if command -v firewall-cmd >/dev/null 2>&1; then
        info "配置 firewalld..."
        firewall-cmd --permanent --add-port=$port/tcp
        firewall-cmd --permanent --add-port=$port/udp
        firewall-cmd --reload
    elif command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        info "配置 ufw..."
        ufw allow $port/tcp
        ufw allow $port/udp
    elif command -v iptables >/dev/null 2>&1 && ! command -v nft >/dev/null 2>&1; then
        # 只在使用传统 iptables 而不是 nftables 时配置
        info "配置 iptables..."
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
        iptables -I INPUT -p udp --dport "$port" -j ACCEPT
        
        # 只在存在保存规则的目录时保存
        if [ -d "/etc/iptables" ]; then
            iptables-save > /etc/iptables/rules.v4
        fi
    else
        info "未检测到活动的防火墙，跳过防火墙配置"
    fi
}

# 创建 ACL 配置
create_acl_config() {
    local type=$1
    local acl_file="${CONFIG_DIR}/acl.yaml"
    
    case "$type" in
        "default")
            cat > "$acl_file" <<EOF
# 默认 ACL 配置
rules:
  - domain_suffix:
      - ad.com
      - ads.com
    action: block
  - ip_cidr:
      - 1.1.1.1/32
      - 8.8.8.8/32
    action: direct
  - domain_suffix:
      - google.com
      - facebook.com
    action: proxy
EOF
            ;;
        "block_ads")
            cat > "$acl_file" <<EOF
# 广告屏蔽 ACL 配置
rules:
  - domain_suffix:
      - ad.com
      - ads.com
      - doubleclick.net
      - googleadservices.com
    action: block
EOF
            ;;
        "block_cn")
            curl -s https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt | sed 's/^/  - /g' > /tmp/cn_ips
            cat > "$acl_file" <<EOF
# 中国 IP 屏蔽配置
rules:
  - ip_cidr:
$(cat /tmp/cn_ips)
    action: block
EOF
            rm -f /tmp/cn_ips
            ;;
        *)
            error "未知的 ACL 类型: $type"
            ;;
    esac
    
    chmod 644 "$acl_file"
    chown hysteria:hysteria "$acl_file"
}

# 管理 ACL 规则
manage_acl() {
    echo -e "\nACL 规则管理\n"
    echo "1. 使用默认规则"
    echo "2. 使用广告屏蔽规则"
    echo "3. 屏蔽中国 IP"
    echo "4. 编辑自定义规则"
    echo "0. 返回主菜单"
    
    read -p "请选择 [0-4]: " choice
    
    case "$choice" in
        1) create_acl_config "default" ;;
        2) create_acl_config "block_ads" ;;
        3) create_acl_config "block_cn" ;;
        4) 
            local editor
            if command -v nano >/dev/null 2>&1; then
                editor=nano
            else
                editor=vi
            fi
            $editor "${CONFIG_DIR}/acl.yaml"
            ;;
        0) return ;;
        *) warn "无效的选择" ;;
    esac
    
    if confirm "是否需要重启服务以应用新的 ACL 规则？"; then
        service_control restart
    fi
}

# 证书管理
manage_cert() {
    echo -e "\n证书管理\n"
    echo "1. 申请新证书"
    echo "2. 更新证书"
    echo "3. 查看证书信息"
    echo "0. 返回主菜单"
    
    read -p "请选择 [0-3]: " choice
    
    case "$choice" in
        1)
            read -p "请输入域名: " domain
            read -p "请输入邮箱: " email
            
            # 修改配置文件添加 ACME 配置
            local config_file="${CONFIG_DIR}/config.yaml"
            sed -i '/^acme:/,/^[^ ]/d' "$config_file"
            sed -i "1i\\
acme:\\
  domains:\\
    - $domain\\
  email: $email\\
" "$config_file"
            
            service_control restart
            ;;
        2)
            if [ -f "${CONFIG_DIR}/acme.json" ]; then
                service_control restart
                info "证书更新请求已发送"
            else
                warn "未找到现有的证书配置"
            fi
            ;;
        3)
            if [ -f "${CONFIG_DIR}/cert.crt" ]; then
                openssl x509 -in "${CONFIG_DIR}/cert.crt" -text -noout
            else
                warn "未找到证书文件"
            fi
            ;;
        0) return ;;
        *) warn "无效的选择" ;;
    esac
}

# 备份/恢复配置
backup_restore() {
    echo -e "\n备份/恢复\n"
    echo "1. 备份配置"
    echo "2. 恢复配置"
    echo "0. 返回主菜单"
    
    read -p "请选择 [0-2]: " choice
    
    case "$choice" in
        1)
            local backup_file="hysteria_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
            tar -czf "$backup_file" -C / "${CONFIG_DIR#/}" "${LOG_DIR#/}" 2>/dev/null
            info "配置已备份到: $backup_file"
            ;;
        2)
            read -p "请输入备份文件路径: " backup_file
            if [ -f "$backup_file" ]; then
                service_control stop
                tar -xzf "$backup_file" -C /
                service_control start
                info "配置已恢复"
            else
                error "备份文件不存在"
            fi
            ;;
        0) return ;;
        *) warn "无效的选择" ;;
    esac
}

# 检查服务是否已安装
is_installed() {
    if [ -f "$INSTALL_DIR/hysteria" ] && [ -f "$CONFIG_DIR/config.yaml" ]; then
        return 0
    fi
    return 1
}

# 生成自签名证书
generate_cert() {
    if [ ! -f "$CONFIG_DIR/server.crt" ] || [ ! -f "$CONFIG_DIR/server.key" ]; then
        info "生成自签名证书..."
        openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
            -keyout "$CONFIG_DIR/server.key" \
            -out "$CONFIG_DIR/server.crt" \
            -subj "/CN=bing.com" -days 36500
    fi
}

# 交互式配置函数
configure_server() {
    echo -e "\n配置 Hysteria 2 服务器\n"
    
    # 配置端口
    local port="$DEFAULT_PORT"
    read -p "请输入端口 [默认: $DEFAULT_PORT]: " input_port
    if [ -n "$input_port" ]; then
        port="$input_port"
    fi
    
    # 配置密码
    local password="$(generate_password)"
    read -p "请输入密码 [默认: $password]: " input_password
    if [ -n "$input_password" ]; then
        password="$input_password"
    fi
    
    # 配置域名（可选）
    local domain=""
    read -p "请输入域名 [可选，回车跳过]: " domain
    
    echo "$port|$password|$domain"
}

# 生成随机密码
generate_password() {
    tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c 16
}

# 服务管理函数
service_control() {
    local action=$1
    if [ "$USE_OPENRC" = true ]; then
        if [ ! -f "${SERVICE_DIR}/hysteria" ]; then
            error "服务未安装"
        fi
        rc-service hysteria $action
    else
        if [ ! -f "/etc/systemd/system/hysteria.service" ]; then
            error "服务未安装"
        fi
        systemctl $action hysteria
    fi
}

# 安装 Hysteria 2
install_hysteria() {
    info "开始安装 Hysteria 2..."
    
    # 检查是否已安装
    if [ -f "$INSTALL_DIR/hysteria" ]; then
        if ! confirm "Hysteria 2 已经安装，是否重新安装？"; then
            return
        fi
    fi
    
    local arch=$(uname -m)
    case $arch in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="arm" ;;
        *) error "不支持的架构: $arch" ;;
    esac
    
    # 获取最新版本
    info "检查最新版本..."
    local latest_version
    latest_version=$(curl -s "$GITHUB_API_URL/releases/latest" | grep '"tag_name":' | cut -d'"' -f4)
    [ -z "$latest_version" ] && error "无法获取最新版本信息"
    
    info "下载 Hysteria 2 $latest_version..."
    local download_url="$GITHUB_API_URL/releases/download/$latest_version/hysteria-linux-$arch"
    curl -L "$download_url" -o "${INSTALL_DIR}/hysteria" || error "下载失败"
    chmod +x "${INSTALL_DIR}/hysteria"
    
    # 创建用户和目录
    info "创建用户和目录..."
    if ! getent group hysteria >/dev/null; then
        addgroup -S hysteria
    fi
    if ! getent passwd hysteria >/dev/null; then
        adduser -S -H -s /sbin/nologin -G hysteria -g hysteria hysteria
    fi
    
    mkdir -p $CONFIG_DIR $LOG_DIR $DATA_DIR
    chown -R hysteria:hysteria $CONFIG_DIR $LOG_DIR $DATA_DIR
    chmod -R 755 $LOG_DIR
    
    # 获取用户配置
    local config
    config=$(configure_server)
    local port password domain
    IFS='|' read -r port password domain <<< "$config"
    
    # 生成配置
    info "生成配置文件..."
    create_config "$port" "$password" "$domain"
    
    # 创建服务
    info "配置系统服务..."
    if [ "$USE_OPENRC" = true ]; then
        create_openrc_service
        rc-update add hysteria default
    else
        create_systemd_service
        systemctl daemon-reload
        systemctl enable hysteria
    fi
    
    # 配置防火墙
    info "配置防火墙..."
    configure_firewall "$port"
    
    # 启动服务
    info "启动服务..."
    service_control start
    
    info "Hysteria 2 安装完成！"
    echo "端口: $port"
    echo "密码: $password"
    if [ -n "$domain" ]; then
        echo "域名: $domain"
    fi
    show_share_link
}

# 主程序入口
main() {
    check_root
    check_system
    install_deps
    
    # 创建 hy2 命令链接
    if [ ! -f "/usr/local/bin/hy2" ]; then
        cp "$0" "/usr/local/bin/hy2"
        chmod +x "/usr/local/bin/hy2"
    fi
    
    if [ "$1" ]; then
        case "$1" in
            start|stop|restart) service_control "$1" ;;
            status) check_status ;;
            *) show_menu ;;
        esac
    else
        show_menu
    fi
}

# 主菜单
show_menu() {
    echo -e "\nHysteria 2 管理脚本\n"
    echo "1. 安装 Hysteria 2"
    echo "2. 更新 Hysteria 2"
    echo "3. 卸载 Hysteria 2"
    echo "4. 启动 Hysteria 2"
    echo "5. 停止 Hysteria 2"
    echo "6. 重启 Hysteria 2"
    echo "7. 查看运行状态"
    echo "8. 查看配置"
    echo "9. 修改配置"
    echo "10. 查看日志"
    echo "11. 查看分享链接"
    echo "12. 显示分享二维码"
    echo "13. 管理 ACL 规则"
    echo "14. 证书管理"
    echo "15. 备份/恢复"
    echo "0. 退出"
    
    read -p "请选择操作 [0-15]: " choice
    
    case "$choice" in
        1) install_hysteria ;;
        2) update_hysteria ;;
        3) uninstall_hysteria ;;
        4) service_control start ;;
        5) service_control stop ;;
        6) service_control restart ;;
        7) check_status ;;
        8) view_config ;;
        9) modify_config ;;
        10) view_logs ;;
        11) show_share_link ;;
        12) show_qr_code ;;
        13) manage_acl ;;
        14) manage_cert ;;
        15) backup_restore ;;
        0) exit 0 ;;
        *) warn "无效的选择" ;;
    esac
}

# 更新 Hysteria 2
update_hysteria() {
    service_control stop
    install_hysteria
    service_control start
    echo "Hysteria 2 已更新到最新版本"
}

# 卸载 Hysteria 2
uninstall_hysteria() {
    if ! is_installed; then
        warn "Hysteria 2 未安装"
        return
    fi
    
    info "开始卸载 Hysteria 2..."
    
    service_control stop 2>/dev/null
    
    if [ "$USE_OPENRC" = true ]; then
        rc-update del hysteria default 2>/dev/null
        rm -f "${SERVICE_DIR}/hysteria"
    else
        systemctl disable hysteria 2>/dev/null
        rm -f /etc/systemd/system/hysteria.service
    fi
    
    rm -f "${INSTALL_DIR}/hysteria"
    rm -rf $CONFIG_DIR $LOG_DIR $DATA_DIR
    
    if getent passwd hysteria >/dev/null; then
        deluser hysteria 2>/dev/null
    fi
    
    info "Hysteria 2 已卸载"
}

# 检查运行状态
check_status() {
    if [ "$USE_OPENRC" = true ]; then
        rc-service hysteria status
    else
        systemctl status hysteria
    fi
}

# 查看配置
view_config() {
    cat "${CONFIG_DIR}/config.yaml"
}

# 修改配置
modify_config() {
    local editor
    if command -v nano >/dev/null 2>&1; then
        editor=nano
    else
        editor=vi
    fi
    
    $editor "${CONFIG_DIR}/config.yaml"
    
    echo "配置已修改，需要重启服务生效"
    read -p "是否现在重启服务？[y/N] " answer
    case $answer in
        [Yy]*) service_control restart ;;
    esac
}

# 查看日志
view_logs() {
    echo "访问日志:"
    tail -n 50 "${LOG_DIR}/access.log"
    echo -e "\n错误日志:"
    tail -n 50 "${LOG_DIR}/error.log"
}

# 生成分享链接
generate_share_link() {
    local config_file="${CONFIG_DIR}/config.yaml"
    if [ ! -f "$config_file" ]; then
        error "配置文件不存在"
    fi
    
    local server_addr=$(curl -s -4 ifconfig.co)
    local port=$(sed -n 's/^listen: :\([0-9]*\)/\1/p' "$config_file")
    local password=$(sed -n 's/^  password: \(.*\)/\1/p' "$config_file")
    local domain=$(sed -n '/^acme:/,/^[^ ]/s/^    - \(.*\)/\1/p' "$config_file" | head -1)
    
    # 添加调试信息
    info "正在生成分享链接..."
    info "检测到的配置："
    [ -n "$server_addr" ] && echo "服务器地址: $server_addr"
    [ -n "$port" ] && echo "端口: $port"
    [ -n "$password" ] && echo "密码: $password"
    [ -n "$domain" ] && echo "域名: $domain"
    
    if [ -n "$domain" ]; then
        server_addr=$domain
    fi
    
    if [ -z "$server_addr" ]; then
        error "无法获取服务器地址"
    fi
    if [ -z "$port" ]; then
        error "无法获取端口信息"
    fi
    if [ -z "$password" ]; then
        error "无法获取密码信息"
    fi
    
    echo "hy2://${password}@${server_addr}:${port}"
}

# 显示分享链接
show_share_link() {
    local link=$(generate_share_link)
    echo "分享链接: $link"
}

# 显示分享二维码
show_qr_code() {
    local link=$(generate_share_link)
    echo "$link" | qrencode -t ANSI
}

main "$@" 