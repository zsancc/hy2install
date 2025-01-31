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
                ADDITIONAL_DEPS="openrc curl wget tar unzip libqrencode bash coreutils openssl iptables"
                
                if ! grep -q "^http.*community" /etc/apk/repositories; then
                    echo "https://dl-cdn.alpinelinux.org/alpine/latest-stable/community" >> /etc/apk/repositories
                fi
                ;;
            "debian"|"ubuntu")
                PKG_MANAGER="apt"
                PKG_UPDATE="apt update"
                PKG_INSTALL="apt install -y"
                USE_OPENRC=false
                ADDITIONAL_DEPS="curl wget tar unzip qrencode"
                ;;
            "centos"|"rhel"|"fedora")
                PKG_MANAGER="yum"
                PKG_UPDATE="yum update -y"
                PKG_INSTALL="yum install -y"
                USE_OPENRC=false
                ADDITIONAL_DEPS="curl wget tar unzip qrencode"
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
    info "正在安装依赖..."
    if [ "$USE_OPENRC" = true ]; then
        if ! $PKG_UPDATE; then
            error "更新包索引失败，请检查网络连接和源配置"
        fi
        
        for pkg in $ADDITIONAL_DEPS; do
            info "安装 $pkg..."
            if ! $PKG_INSTALL $pkg; then
                error "安装 $pkg 失败"
            fi
        done
    else
        $PKG_UPDATE
        if ! $PKG_INSTALL $ADDITIONAL_DEPS; then
            error "依赖安装失败"
        fi
    fi
    
    info "依赖安装完成"
}

# 配置防火墙
configure_firewall() {
    local port=$1
    
    if [ "$USE_OPENRC" = true ]; then
        if command -v iptables >/dev/null; then
            iptables -I INPUT -p tcp --dport $port -j ACCEPT
            iptables -I INPUT -p udp --dport $port -j ACCEPT
            
            # 保存防火墙规则
            if [ -f "/etc/iptables/rules-save" ]; then
                iptables-save > /etc/iptables/rules-save
            fi
        fi
    else
        if command -v firewall-cmd >/dev/null; then
            firewall-cmd --permanent --add-port=$port/tcp
            firewall-cmd --permanent --add-port=$port/udp
            firewall-cmd --reload
        elif command -v ufw >/dev/null; then
            ufw allow $port/tcp
            ufw allow $port/udp
        fi
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

# 创建 OpenRC 服务文件
create_openrc_service() {
    cat > "${SERVICE_DIR}/hysteria" <<EOF
#!/sbin/openrc-run

name="hysteria"
description="Hysteria 2 Proxy Server"
command="/usr/local/bin/hysteria"
command_args="server --config /etc/hysteria/config.yaml"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/hysteria/access.log"
error_log="/var/log/hysteria/error.log"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath -d -m 0755 -o hysteria:hysteria /var/log/hysteria
}
EOF
    chmod +x "${SERVICE_DIR}/hysteria"
}

# 创建基础配置文件
create_config() {
    local port=$1
    local password=$2
    local domain=$3
    
    mkdir -p $CONFIG_DIR
    
    if [ -n "$domain" ]; then
        cat > "${CONFIG_DIR}/config.yaml" <<EOF
listen: :${port}

acme:
  domains:
    - ${domain}
  email: admin@${domain}

auth:
  type: password
  password: ${password}

masquerade:
  type: proxy
  proxy:
    url: ${DEFAULT_MASQ}
    rewriteHost: true

acl:
  file: ${CONFIG_DIR}/acl.yaml
EOF
    else
        cat > "${CONFIG_DIR}/config.yaml" <<EOF
listen: :${port}

auth:
  type: password
  password: ${password}

masquerade:
  type: proxy
  proxy:
    url: ${DEFAULT_MASQ}
    rewriteHost: true

acl:
  file: ${CONFIG_DIR}/acl.yaml
EOF
    fi
}

# 生成随机密码
generate_password() {
    tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c 16
}

# 服务管理函数
service_control() {
    local action=$1
    if [ "$USE_OPENRC" = true ]; then
        rc-service hysteria $action
    else
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
    latest_version=$(curl -s "$GITHUB_API_URL/releases/latest" | grep -o '"tag_name": ".*"' | cut -d'"' -f4)
    [ -z "$latest_version" ] && error "无法获取最新版本信息"
    
    info "下载 Hysteria 2 $latest_version..."
    local download_url="$GITHUB_API_URL/releases/download/$latest_version/hysteria-linux-$arch"
    curl -L "$download_url" -o "${INSTALL_DIR}/hysteria" || error "下载失败"
    chmod +x "${INSTALL_DIR}/hysteria"
    
    # 创建用户和目录
    info "创建用户和目录..."
    if [ "$USE_OPENRC" = true ]; then
        adduser -S -H -s /sbin/nologin hysteria 2>/dev/null
    else
        useradd -r -s /sbin/nologin hysteria 2>/dev/null
    fi
    
    mkdir -p $CONFIG_DIR $LOG_DIR $DATA_DIR
    chown -R hysteria:hysteria $CONFIG_DIR $LOG_DIR $DATA_DIR
    
    # 生成配置
    info "生成配置文件..."
    local password=$(generate_password)
    create_config $DEFAULT_PORT $password
    
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
    configure_firewall $DEFAULT_PORT
    
    # 启动服务
    info "启动服务..."
    service_control start
    
    info "Hysteria 2 安装完成！"
    echo "默认端口: $DEFAULT_PORT"
    echo "默认密码: $password"
    show_share_link
}

# 主程序入口
main() {
    check_root
    check_system
    install_deps
    
    # 创建 hy2 命令链接
    ln -sf "$0" /usr/local/bin/hy2
    
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
    service_control stop
    
    if [ "$USE_OPENRC" = true ]; then
        rc-update del hysteria default
        rm -f "${SERVICE_DIR}/hysteria"
    else
        systemctl disable hysteria
        rm -f /etc/systemd/system/hysteria.service
    fi
    
    rm -f "${INSTALL_DIR}/hysteria"
    rm -rf $CONFIG_DIR $LOG_DIR $DATA_DIR
    deluser hysteria
    
    echo "Hysteria 2 已卸载"
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
    local server_addr=$(curl -s ipv4.icanhazip.com)
    local port=$(grep -oP 'listen: :\K\d+' "$config_file")
    local password=$(grep -oP 'password: \K.*' "$config_file")
    local domain=$(grep -oP 'domains:.*\n.*- \K.*' "$config_file" || echo "")
    
    if [ -n "$domain" ]; then
        server_addr=$domain
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