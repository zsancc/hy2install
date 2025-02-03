#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Default values
DEFAULT_PORT=5525
DEFAULT_PASSWORD=$(openssl rand -base64 16)
DEFAULT_DOMAIN=""
DEFAULT_MASQ_SITE="https://news.ycombinator.com/"

# Detect package manager and service manager
detect_system() {
    if [ -f /etc/debian_version ]; then
        PKG_MANAGER="apt"
        PKG_UPDATE="apt update"
        PKG_INSTALL="apt install -y"
        if systemctl --version >/dev/null 2>&1; then
            SERVICE_MANAGER="systemd"
        else
            SERVICE_MANAGER="sysvinit"
        fi
    elif [ -f /etc/redhat-release ]; then
        if command -v dnf >/dev/null 2>&1; then
            PKG_MANAGER="dnf"
            PKG_UPDATE="dnf update -y"
            PKG_INSTALL="dnf install -y"
        else
            PKG_MANAGER="yum"
            PKG_UPDATE="yum update -y"
            PKG_INSTALL="yum install -y"
        fi
        if systemctl --version >/dev/null 2>&1; then
            SERVICE_MANAGER="systemd"
        else
            SERVICE_MANAGER="sysvinit"
        fi
    else
        echo "不支持的系统"
        exit 1
    fi
}

# Install dependencies
install_dependencies() {
    echo -e "${YELLOW}安装依赖...${NC}"
    $PKG_UPDATE
    $PKG_INSTALL wget curl openssl
    
    # Install qrencode
    if ! $PKG_INSTALL qrencode; then
        if [ "$PKG_MANAGER" = "yum" ] || [ "$PKG_MANAGER" = "dnf" ]; then
            yum install -y epel-release
            $PKG_INSTALL qrencode
        fi
    fi
    
    if ! command -v qrencode >/dev/null 2>&1; then
        echo -e "${YELLOW}警告: qrencode 安装失败，二维码功能将不可用${NC}"
    fi
}

# Generate service file
generate_service() {
    if [ "$SERVICE_MANAGER" = "systemd" ]; then
        cat > /etc/systemd/system/hysteria.service << EOF
[Unit]
Description=Hysteria 2 Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server --config /etc/hysteria/config.yaml
Restart=on-failure
StandardOutput=append:/var/log/hysteria.log
StandardError=append:/var/log/hysteria.error.log

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    else
        cat > /etc/init.d/hysteria << EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          hysteria
# Required-Start:    \$network \$remote_fs \$syslog
# Required-Stop:     \$network \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Hysteria 2 Server
### END INIT INFO

DAEMON=/usr/local/bin/hysteria
DAEMON_ARGS="server --config /etc/hysteria/config.yaml"
NAME=hysteria
DESC="Hysteria 2 Server"
PIDFILE=/var/run/\$NAME.pid
LOGFILE=/var/log/hysteria.log
ERRFILE=/var/log/hysteria.error.log

test -x \$DAEMON || exit 0

do_start() {
    start-stop-daemon --start --background --make-pidfile --pidfile \$PIDFILE \\
        --exec \$DAEMON -- \$DAEMON_ARGS >> \$LOGFILE 2>> \$ERRFILE
}

do_stop() {
    start-stop-daemon --stop --quiet --pidfile \$PIDFILE
    rm -f \$PIDFILE
}

case "\$1" in
    start)
        echo "Starting \$DESC"
        do_start
        ;;
    stop)
        echo "Stopping \$DESC"
        do_stop
        ;;
    restart)
        echo "Restarting \$DESC"
        do_stop
        sleep 1
        do_start
        ;;
    status)
        if [ -f \$PIDFILE ]; then
            echo "\$DESC is running"
        else
            echo "\$DESC is not running"
        fi
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
EOF
        chmod +x /etc/init.d/hysteria
        if [ -x /sbin/chkconfig ]; then
            chkconfig --add hysteria
            chkconfig hysteria on
        elif [ -x /usr/sbin/update-rc.d ]; then
            update-rc.d hysteria defaults
        fi
    fi
}

# Service control functions
service_start() {
    if [ "$SERVICE_MANAGER" = "systemd" ]; then
        systemctl start hysteria
    else
        service hysteria start
    fi
}

service_stop() {
    if [ "$SERVICE_MANAGER" = "systemd" ]; then
        systemctl stop hysteria
    else
        service hysteria stop
    fi
}

service_restart() {
    if [ "$SERVICE_MANAGER" = "systemd" ]; then
        systemctl restart hysteria
    else
        service hysteria restart
    fi
}

service_status() {
    if [ "$SERVICE_MANAGER" = "systemd" ]; then
        systemctl status hysteria
    else
        service hysteria status
    fi
}

# Generate hy2 command
generate_hy2_command() {
    cat > /usr/local/bin/hy2 << 'EOF'
#!/bin/bash

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${YELLOW}Hysteria 2 管理脚本${NC}"
    echo "------------------------"
    echo -e "${GREEN}1. 更新 Hysteria 2${NC}"
    echo -e "${GREEN}2. 卸载 Hysteria 2${NC}"
    echo -e "${GREEN}3. 启动服务${NC}"
    echo -e "${GREEN}4. 停止服务${NC}"
    echo -e "${GREEN}5. 重启服务${NC}"
    echo -e "${GREEN}6. 查看状态${NC}"
    echo -e "${GREEN}7. 查看配置${NC}"
    echo -e "${GREEN}8. 修改配置${NC}"
    echo -e "${GREEN}9. 查看日志${NC}"
    echo -e "${GREEN}10. 查看分享链接${NC}"
    echo -e "${GREEN}11. 显示分享二维码${NC}"
    echo -e "${GREEN}0. 退出${NC}"
    echo "------------------------"
    read -p "请选择操作 [0-11]: " choice

    case "$choice" in
        1) 
            echo -e "${YELLOW}更新 Hysteria 2...${NC}"
            wget -O /usr/local/bin/hysteria https://download.hysteria.network/app/latest/hysteria-linux-amd64
            chmod +x /usr/local/bin/hysteria
            if [ "$SERVICE_MANAGER" = "systemd" ]; then
                systemctl restart hysteria
            else
                service hysteria restart
            fi
            echo -e "${GREEN}更新完成${NC}"
            ;;
        2) 
            echo -e "${YELLOW}卸载 Hysteria 2...${NC}"
            if [ "$SERVICE_MANAGER" = "systemd" ]; then
                systemctl stop hysteria
                systemctl disable hysteria
                rm -f /etc/systemd/system/hysteria.service
                systemctl daemon-reload
            else
                service hysteria stop
                if [ -x /sbin/chkconfig ]; then
                    chkconfig --del hysteria
                elif [ -x /usr/sbin/update-rc.d ]; then
                    update-rc.d -f hysteria remove
                fi
                rm -f /etc/init.d/hysteria
            fi
            rm -f /usr/local/bin/hysteria
            rm -f /usr/local/bin/hy2
            rm -rf /etc/hysteria
            echo -e "${GREEN}卸载完成${NC}"
            exit 0
            ;;
        3) 
            echo -e "${YELLOW}启动服务...${NC}"
            /usr/local/bin/hysteria server --config /etc/hysteria/config.yaml --disable-update-check
            if [ $? -eq 0 ]; then
                if [ "$SERVICE_MANAGER" = "systemd" ]; then
                    systemctl start hysteria
                else
                    service hysteria start
                fi
            else
                echo -e "${RED}启动失败${NC}"
            fi
            ;;
        4) 
            echo -e "${YELLOW}停止服务...${NC}"
            if [ "$SERVICE_MANAGER" = "systemd" ]; then
                systemctl stop hysteria
            else
                service hysteria stop
            fi
            ;;
        5) 
            echo -e "${YELLOW}重启服务...${NC}"
            /usr/local/bin/hysteria server --config /etc/hysteria/config.yaml --disable-update-check
            if [ $? -eq 0 ]; then
                if [ "$SERVICE_MANAGER" = "systemd" ]; then
                    systemctl restart hysteria
                else
                    service hysteria restart
                fi
            else
                echo -e "${RED}重启失败${NC}"
            fi
            ;;
        6) 
            echo -e "${YELLOW}服务状态:${NC}"
            if [ "$SERVICE_MANAGER" = "systemd" ]; then
                systemctl status hysteria
            else
                service hysteria status
            fi
            ;;
        7) cat /etc/hysteria/config.yaml ;;
        8) 
            echo -e "${YELLOW}修改配置...${NC}"
            configure_hysteria
            ;;
        9) 
            if [ -f "/var/log/hysteria.log" ]; then
                tail -f /var/log/hysteria.log
            else
                echo "日志文件不存在"
            fi
            ;;
        10|11)
            PASSWORD=$(grep "password:" /etc/hysteria/config.yaml | awk '{print $NF}')
            PORT=$(grep listen /etc/hysteria/config.yaml | awk -F: '{print $3}')
            DOMAIN=$(grep domains -A 1 /etc/hysteria/config.yaml | grep - | awk '{print $2}')
            [ -z "$DOMAIN" ] && DOMAIN="bing.com"
            SHARE_LINK="hysteria2://${PASSWORD}@${DOMAIN}:${PORT}/?sni=${DOMAIN}&insecure=0#${DOMAIN}"
            echo
            echo "分享链接:"
            echo "$SHARE_LINK"
            if [ "$choice" = "11" ]; then
                echo
                echo "QR Code:"
                command -v qrencode >/dev/null 2>&1 && {
                    qrencode -t ANSIUTF8 "$SHARE_LINK"
                } || echo "qrencode not found"
            fi
            ;;
        0) exit 0 ;;
        *) 
            echo "无效选项"
            sleep 2
            show_menu
            ;;
    esac
    
    if [ "$choice" != "0" ] && [ "$choice" != "2" ]; then
        echo
        read -p "按回车键返回主菜单"
        show_menu
    fi
}

show_menu
EOF
    chmod +x /usr/local/bin/hy2
}

# Get user input with default values
get_user_input() {
    echo -e "${YELLOW}请输入端口 [默认: $DEFAULT_PORT]:${NC}"
    read PORT
    PORT=${PORT:-$DEFAULT_PORT}

    echo -e "${YELLOW}请输入密码 [默认: $DEFAULT_PASSWORD]:${NC}"
    read PASSWORD
    PASSWORD=${PASSWORD:-$DEFAULT_PASSWORD}

    echo -e "${YELLOW}请选择 TLS 验证方式:${NC}"
    echo "1. 自定义证书 (适用于 NAT VPS 或自定义证书)"
    echo "2. ACME HTTP 验证 (需要 80 端口)"
    echo "3. Cloudflare DNS 验证"
    read -p "请选择 [1-3]: " TLS_TYPE

    case "$TLS_TYPE" in
        1)
            echo -e "${YELLOW}请输入证书路径:${NC}"
            read CERT_PATH
            echo -e "${YELLOW}请输入私钥路径:${NC}"
            read KEY_PATH
            ;;
        2)
            echo -e "${YELLOW}请输入域名:${NC}"
            read DOMAIN
            if [ -z "$DOMAIN" ]; then
                echo "域名不能为空"
                exit 1
            fi
            ;;
        3)
            echo -e "${YELLOW}请输入域名:${NC}"
            read DOMAIN
            echo -e "${YELLOW}请输入邮箱:${NC}"
            read EMAIL
            echo -e "${YELLOW}请输入 Cloudflare API Token (在 Cloudflare 面板中: 我的个人资料->API令牌->Origin CA Key):${NC}"
            echo -e "${YELLOW}如果没有令牌，请先在 Cloudflare 面板中创建${NC}"
            read CF_TOKEN
            if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ] || [ -z "$CF_TOKEN" ]; then
                echo "所有字段都不能为空"
                exit 1
            fi
            ;;
        *)
            echo "无效选项"
            exit 1
            ;;
    esac

    echo -e "${YELLOW}请输入伪装站点 [默认: $DEFAULT_MASQ_SITE]:${NC}"
    read MASQ_SITE
    MASQ_SITE=${MASQ_SITE:-$DEFAULT_MASQ_SITE}
}

# Generate config based on TLS type
generate_config() {
    case "$TLS_TYPE" in
        1)
            cat > /etc/hysteria/config.yaml << EOF
listen: :$PORT

tls:
  cert: $CERT_PATH
  key: $KEY_PATH
  sni_guard: dns-san

auth:
  type: password
  password: $PASSWORD

masquerade:
  type: proxy
  proxy:
    url: $MASQ_SITE
    rewriteHost: true
EOF
            ;;
        2)
            cat > /etc/hysteria/config.yaml << EOF
listen: :$PORT

acme:
  domains:
    - $DOMAIN
  email: admin@$DOMAIN

auth:
  type: password
  password: $PASSWORD

masquerade:
  type: proxy
  proxy:
    url: $MASQ_SITE
    rewriteHost: true
EOF
            ;;
        3)
            cat > /etc/hysteria/config.yaml << EOF
listen: :$PORT

acme:
  domains:
    - $DOMAIN
  email: $EMAIL
  type: dns
  dns:
    name: cloudflare
    config:
      cloudflare_api_token: $CF_TOKEN

auth:
  type: password
  password: $PASSWORD

masquerade:
  type: proxy
  proxy:
    url: $MASQ_SITE
    rewriteHost: true
EOF
            ;;
    esac
}

# Configure function for both install and modify
configure_hysteria() {
    get_user_input
    generate_config
    
    echo -e "${YELLOW}重启服务以应用新配置...${NC}"
    service_stop
    /usr/local/bin/hysteria server --config /etc/hysteria/config.yaml --disable-update-check
    if [ $? -eq 0 ]; then
        service_start
        echo -e "${GREEN}配置修改成功${NC}"
    else
        echo -e "${RED}配置有误，启动失败${NC}"
    fi
}

# Check if Hysteria 2 is already installed
check_installed() {
    if [ -f "/usr/local/bin/hysteria" ] || [ -f "/etc/init.d/hysteria" ] || [ -f "/etc/systemd/system/hysteria.service" ]; then
        echo -e "${YELLOW}检测到已安装 Hysteria 2${NC}"
        echo -e "请选择操作："
        echo "1. 卸载重装"
        echo "2. 返回主菜单"
        read -p "请输入选项 [1-2]: " choice
        case "$choice" in
            1) uninstall_hysteria && return 0 ;;
            2) return 1 ;;
            *) echo "无效选项" && return 1 ;;
        esac
    fi
    return 0
}

# Main installation process
main() {
    # 检查 root 权限
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请使用 root 权限运行此脚本${NC}"
        exit 1
    fi
    
    # 检测系统
    detect_system
    
    # 检查是否已安装
    check_installed
    
    echo -e "${GREEN}开始安装 Hysteria 2...${NC}"
    
    install_dependencies
    
    # Download Hysteria 2
    echo -e "${YELLOW}下载 Hysteria 2...${NC}"
    wget -O /usr/local/bin/hysteria https://download.hysteria.network/app/latest/hysteria-linux-amd64
    chmod +x /usr/local/bin/hysteria
    
    # Create config directory
    mkdir -p /etc/hysteria/
    
    echo -e "${YELLOW}配置 Hysteria 2...${NC}"
    configure_hysteria
    
    echo -e "${YELLOW}生成服务文件...${NC}"
    generate_service
    generate_hy2_command
    
    # Enable and start service
    echo -e "${YELLOW}启动服务...${NC}"
    if [ "$SERVICE_MANAGER" = "systemd" ]; then
        systemctl enable hysteria
        systemctl start hysteria
    else
        service hysteria start
    fi
    
    # 验证安装
    if [ -f "/usr/local/bin/hy2" ] && [ -x "/usr/local/bin/hy2" ]; then
        echo -e "${GREEN}Hysteria 2 安装完成!${NC}"
        echo -e "${YELLOW}配置信息:${NC}"
        echo "端口: $PORT"
        echo "密码: $PASSWORD"
        echo "域名: ${DOMAIN:-bing.com}"
        echo -e "\n使用 'hy2' 命令管理 Hysteria 2"
        echo -e "运行 'hy2' 显示管理菜单\n"
    else
        echo -e "${RED}安装失败，请检查错误信息${NC}"
        exit 1
    fi
}

# 直接运行主函数
main
