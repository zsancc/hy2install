#!/bin/sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Default values
DEFAULT_PORT=5525
DEFAULT_PASSWORD=$(dd if=/dev/random bs=18 count=1 status=none | base64)
DEFAULT_DOMAIN=""
DEFAULT_MASQ_SITE="https://news.ycombinator.com/"

# Show menu
show_menu() {
    clear
    echo -e "${GREEN}Hysteria 2 管理脚本${NC}"
    echo "------------------------"
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
    echo "0. 退出"
    echo "------------------------"
    read -p "请选择操作 [0-12]: " choice
    
    case "$choice" in
        1) install_hysteria ;;
        2) update_hysteria ;;
        3) uninstall_hysteria ;;
        4) service hysteria start ;;
        5) service hysteria stop ;;
        6) service hysteria restart ;;
        7) service hysteria status ;;
        8) [ -f "/etc/hysteria/config.yaml" ] && cat /etc/hysteria/config.yaml || echo "配置文件不存在" ;;
        9) modify_config ;;
        10) view_logs ;;
        11) [ -f "/usr/local/bin/hy2" ] && /usr/local/bin/hy2 share || echo "Hysteria 2 未安装" ;;
        12) [ -f "/usr/local/bin/hy2" ] && /usr/local/bin/hy2 share || echo "Hysteria 2 未安装" ;;
        0) exit 0 ;;
        *) echo "无效选项" && sleep 2 && show_menu ;;
    esac
}

# View logs function
view_logs() {
    if [ -f "/var/log/hysteria.log" ]; then
        tail -f /var/log/hysteria.log
    else
        echo "日志文件不存在"
    fi
}

# Modify config function
modify_config() {
    if [ ! -f "/etc/hysteria/config.yaml" ]; then
        echo "配置文件不存在"
        return
    fi
    get_user_input
    generate_config
    service hysteria restart
    echo "配置已更新"
}

# Update function
update_hysteria() {
    wget -O /usr/local/bin/hysteria https://download.hysteria.network/app/latest/hysteria-linux-amd64
    chmod +x /usr/local/bin/hysteria
    service hysteria restart
    echo "更新完成"
}

# Install function
install_hysteria() {
    # 检查是否已安装
    if [ -f "/usr/local/bin/hysteria" ] || [ -f "/etc/init.d/hysteria" ]; then
        echo -e "${YELLOW}检测到已安装 Hysteria 2${NC}"
        echo -e "请选择操作："
        echo "1. 卸载重装"
        echo "2. 返回主菜单"
        read -p "请输入选项 [1-2]: " choice
        case "$choice" in
            1) uninstall_hysteria ;;
            2) show_menu ;;
            *) echo "无效选项" && sleep 2 && show_menu ;;
        esac
    fi
    
    echo -e "${GREEN}开始安装 Hysteria 2...${NC}"
    
    # 检查必要命令
    if ! command -v wget >/dev/null 2>&1; then
        apk add wget
    fi
    
    # Install dependencies
    apk update
    apk add curl git openssh openssl openrc
    # 单独安装并验证 qrencode
    if ! apk add libqrencode-tools; then
        echo -e "${RED}安装 qrencode 失败，尝试从社区仓库安装${NC}"
        apk add --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community libqrencode-tools
    fi
    
    # 验证 qrencode 是否安装成功
    if ! command -v qrencode >/dev/null 2>&1; then
        echo -e "${YELLOW}警告: qrencode 安装失败，二维码功能将不可用${NC}"
    fi
    
    get_user_input
    
    # Download Hysteria 2
    wget -O /usr/local/bin/hysteria https://download.hysteria.network/app/latest/hysteria-linux-amd64
    chmod +x /usr/local/bin/hysteria
    
    # Create config directory
    mkdir -p /etc/hysteria/
    
    # Generate self-signed cert if no domain provided
    if [ -z "$DOMAIN" ]; then
        openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
            -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
            -subj "/CN=bing.com" -days 36500
    fi
    
    generate_config
    generate_service
    generate_hy2_command
    
    # Enable and start service
    rc-update add hysteria default
    service hysteria start
    
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
    
    sleep 3
    show_menu
}

# Check if Hysteria 2 is already installed
check_installed() {
    if [ -f "/usr/local/bin/hysteria" ] || [ -f "/etc/init.d/hysteria" ]; then
        echo -e "${YELLOW}检测到已安装 Hysteria 2${NC}"
        echo -e "请选择操作："
        echo "1. 卸载重装"
        echo "2. 退出"
        read -p "请输入选项 [1-2]: " choice
        
        case "$choice" in
            1)
                uninstall_hysteria
                ;;
            2)
                echo "退出安装"
                exit 0
                ;;
            *)
                echo "无效选项，退出"
                exit 1
                ;;
        esac
    fi
}

# Uninstall function
uninstall_hysteria() {
    echo -e "${YELLOW}开始卸载 Hysteria 2...${NC}"
    service hysteria stop
    rc-update del hysteria default
    rm -f /usr/local/bin/hysteria
    rm -f /usr/local/bin/hy2
    rm -f /etc/init.d/hysteria
    rm -rf /etc/hysteria
    echo -e "${GREEN}卸载完成${NC}"
}

# Install dependencies
install_dependencies() {
    apk update
    apk add wget curl git openssh openssl openrc
    # 单独安装并验证 qrencode
    if ! apk add libqrencode-tools; then
        echo -e "${RED}安装 qrencode 失败，尝试从社区仓库安装${NC}"
        apk add --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community libqrencode-tools
    fi
    
    # 验证 qrencode 是否安装成功
    if ! command -v qrencode >/dev/null 2>&1; then
        echo -e "${YELLOW}警告: qrencode 安装失败，二维码功能将不可用${NC}"
    fi
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
            echo -e "${YELLOW}请输入 Cloudflare API Token (在 Cloudflare 面板中: 我的个人资料->API令牌->创建Token->使用 Edit zone DNS 模板->权限类型：Zone / DNS / Edit,资源：Include / Specific zone / 选择你的域名，如 baidu.com):${NC}"
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

# Generate OpenRC service file with proper server mode and logging
generate_service() {
    cat > /etc/init.d/hysteria << EOF
#!/sbin/openrc-run

name="hysteria"
command="/usr/local/bin/hysteria"
command_args="server --config /etc/hysteria/config.yaml"
command_background="yes"
pidfile="/var/run/\${name}.pid"
output_log="/var/log/hysteria.log"
error_log="/var/log/hysteria.error.log"

start_pre() {
    checkpath -f \$output_log
    checkpath -f \$error_log
    chmod 644 \$output_log
    chmod 644 \$error_log
}

depend() {
    need net
    after firewall
}

start() {
    ebegin "Starting \$name"
    start-stop-daemon --start --quiet --background \
        --make-pidfile --pidfile \$pidfile \
        --stdout \$output_log --stderr \$error_log \
        --exec \$command -- \$command_args
    eend \$?
}
EOF
    chmod +x /etc/init.d/hysteria
}

# Generate hy2 command
generate_hy2_command() {
    cat > /usr/local/bin/hy2 << 'EOF'
#!/bin/sh

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${GREEN}Hysteria 2 管理菜单${NC}"
    echo "------------------------"
    echo "1. 更新 Hysteria 2"
    echo "2. 卸载 Hysteria 2"
    echo "3. 启动服务"
    echo "4. 停止服务"
    echo "5. 重启服务"
    echo "6. 查看状态"
    echo "7. 查看配置"
    echo "8. 修改配置"
    echo "9. 查看日志"
    echo "10. 查看分享链接"
    echo "11. 显示分享二维码"
    echo "0. 退出"
    echo "------------------------"
    read -p "请选择操作 [0-11]: " choice

    case "$choice" in
        1) 
            echo -e "${YELLOW}更新 Hysteria 2...${NC}"
            wget -O /usr/local/bin/hysteria https://download.hysteria.network/app/latest/hysteria-linux-amd64
            chmod +x /usr/local/bin/hysteria
            service hysteria restart
            echo -e "${GREEN}更新完成${NC}"
            ;;
        2) 
            echo -e "${YELLOW}卸载 Hysteria 2...${NC}"
            service hysteria stop
            rc-update del hysteria default
            rm -f /usr/local/bin/hysteria
            rm -f /usr/local/bin/hy2
            rm -f /etc/init.d/hysteria
            rm -rf /etc/hysteria
            echo -e "${GREEN}卸载完成${NC}"
            exit 0
            ;;
        3) 
            echo -e "${YELLOW}启动服务...${NC}"
            service hysteria stop >/dev/null 2>&1  # 先停止服务以防端口占用
            /usr/local/bin/hysteria server --config /etc/hysteria/config.yaml --disable-update-check
            if [ $? -eq 0 ]; then
                service hysteria start
            else
                echo -e "${RED}启动失败${NC}"
            fi
            ;;
        4) 
            echo -e "${YELLOW}停止服务...${NC}"
            service hysteria stop
            ;;
        5) 
            echo -e "${YELLOW}重启服务...${NC}"
            service hysteria stop
            /usr/local/bin/hysteria server --config /etc/hysteria/config.yaml --disable-update-check
            if [ $? -eq 0 ]; then
                service hysteria start
            else
                echo -e "${RED}启动失败${NC}"
            fi
            ;;
        6) 
            echo -e "${YELLOW}服务状态:${NC}"
            service hysteria status
            if [ -f "/var/run/hysteria.pid" ]; then
                echo -e "\n${YELLOW}程序输出:${NC}"
                /usr/local/bin/hysteria server --config /etc/hysteria/config.yaml --disable-update-check
            fi
            ;;
        7) cat /etc/hysteria/config.yaml ;;
        8) 
            # 重新运行安装脚本的配置部分
            bash <(curl -fsSL https://raw.githubusercontent.com/zsancc/hy2install/main/alpinehy2install.sh) config
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
                } || echo "qrencode not found. Please install with: apk add libqrencode-tools"
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

# Main installation process
main() {
    # 检查是否已安装
    check_installed
    
    echo -e "${GREEN}开始安装 Hysteria 2...${NC}"
    
    install_dependencies
    get_user_input
    
    # Download Hysteria 2
    echo -e "${YELLOW}下载 Hysteria 2...${NC}"
    wget -O /usr/local/bin/hysteria https://download.hysteria.network/app/latest/hysteria-linux-amd64
    chmod +x /usr/local/bin/hysteria
    
    # Create config directory
    mkdir -p /etc/hysteria/
    
    # Generate self-signed cert if needed
    if [ "$TLS_TYPE" = "1" ]; then
        echo -e "${YELLOW}使用自定义证书...${NC}"
        # 检查证书文件是否存在
        if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
            echo -e "${RED}证书文件不存在${NC}"
            exit 1
        fi
    fi
    
    echo -e "${YELLOW}生成配置文件...${NC}"
    generate_config
    
    echo -e "${YELLOW}配置系统服务...${NC}"
    generate_service
    generate_hy2_command
    
    # Enable and start service
    echo -e "${YELLOW}启动服务...${NC}"
    rc-update add hysteria default
    service hysteria start
    
    # 等待服务启动并获取日志
    sleep 2
    if [ -f "/var/log/hysteria.log" ]; then
        echo -e "${YELLOW}服务启动日志:${NC}"
        tail -n 10 /var/log/hysteria.log
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
