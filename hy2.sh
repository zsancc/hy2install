#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查是否为 root 用户
[[ $EUID -ne 0 ]] && echo -e "${RED}错误: ${PLAIN}必须使用root用户运行此脚本！\n" && exit 1

# 检查系统类型
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /etc/os-release | grep -Eqi "alpine"; then
    release="alpine"
else
    echo -e "${RED}未检测到系统版本，请联系脚本作者！${PLAIN}\n" && exit 1
fi

# 安装基础工具
install_base() {
    if [[ ${release} == "centos" ]]; then
        yum install wget curl tar -y
    elif [[ ${release} == "alpine" ]]; then
        apk add wget curl tar shadow # 添加 shadow 包以获取用户管理命令
    else
        apt install wget curl tar -y
    fi
}

# 安装 Hysteria2
install_hysteria() {
    echo -e "${GREEN}开始安装 Hysteria 2...${PLAIN}"
    
    if [[ ${release} == "alpine" ]]; then
        # Alpine 专用安装流程
        apk add --no-cache curl wget tar openssl openrc
        
        # 下载最新版本
        echo -e "${GREEN}下载 Hysteria 2...${PLAIN}"
        wget -O /usr/local/bin/hysteria https://download.hysteria.network/app/latest/hysteria-linux-amd64 --no-check-certificate
        
        if [[ $? != 0 ]]; then
            echo -e "${RED}下载 Hysteria2 失败，请检查网络${PLAIN}"
            exit 1
        fi
        chmod +x /usr/local/bin/hysteria

        # 创建目录
        mkdir -p /etc/hysteria
        mkdir -p /var/log/hysteria

        # 创建 OpenRC service 文件
        cat > /etc/init.d/hysteria << 'EOF'
#!/sbin/openrc-run

name="hysteria"
command="/usr/local/bin/hysteria"
command_args="server --config /etc/hysteria/config.yaml"
pidfile="/var/run/${name}.pid"
command_background="yes"

depend() {
    need networking
}

start_pre() {
    checkpath --directory --mode 0755 /var/log/hysteria
}
EOF
        chmod +x /etc/init.d/hysteria
        rc-update add hysteria default
        
        echo -e "${GREEN}Hysteria2 安装完成！${PLAIN}"
    else
        # 其他系统使用官方脚本
        export FORCE_NO_SYSTEMD=2
        bash <(curl -fsSL https://get.hy2.sh/)
        if [[ $? != 0 ]]; then
            echo -e "${RED}Hysteria2 安装失败，请检查错误信息${PLAIN}"
            exit 1
        fi
    fi
}

# 生成配置文件
generate_config() {
    echo -e "${GREEN}开始配置 Hysteria 2...${PLAIN}"
    
    # 端口配置
    read -p "请输入监听端口 [1-65535] (默认: 5525): " port
    [[ -z "${port}" ]] && port=5525
    
    # 域名配置
    read -p "是否配置域名 (y/n) (默认: n): " use_domain
    if [[ "${use_domain}" == "y" ]]; then
        read -p "请输入域名: " domain
        read -p "请输入邮箱 (用于ACME申请证书): " email
        
        if [[ -z "${domain}" || -z "${email}" ]]; then
            echo -e "${RED}域名和邮箱不能为空${PLAIN}"
            exit 1
        fi
    fi
    
    # 密码配置
    read -p "请输入认证密码 (默认随机生成): " auth_pass
    [[ -z "${auth_pass}" ]] && auth_pass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    
    # 伪装配置
    read -p "请输入伪装网站URL (默认: https://news.ycombinator.com/): " masq_url
    [[ -z "${masq_url}" ]] && masq_url="https://news.ycombinator.com/"
    
    # 生成基础配置
    cat > /etc/hysteria/config.yaml << EOF
listen: :${port}

auth:
  type: password
  password: ${auth_pass}

masquerade:
  type: proxy
  proxy:
    url: ${masq_url}
    rewriteHost: true

sniff:
  enable: true
  timeout: 2s
  rewriteDomain: false
EOF

    # 如果配置了域名，添加ACME配置
    if [[ "${use_domain}" == "y" ]]; then
        cat >> /etc/hysteria/config.yaml << EOF

acme:
  domains:
    - ${domain}
  email: ${email}
EOF
    fi
    
    # 询问是否配置ACL
    read -p "是否配置访问控制(ACL)规则? (y/n) (默认: n): " use_acl
    if [[ "${use_acl}" == "y" ]]; then
        configure_acl
    fi
    
    echo -e "${GREEN}配置文件已生成！${PLAIN}"
    generate_uri
    generate_qr
}

# 添加 ACL 配置函数
configure_acl() {
    echo -e "${GREEN}开始配置ACL规则...${PLAIN}"
    echo -e "1. 屏蔽中国IP和广告域名"
    echo -e "2. 自定义规则"
    read -p "请选择 (1-2): " acl_choice
    
    case "${acl_choice}" in
        1)
            cat >> /etc/hysteria/config.yaml << EOF

acl:
  rules:
    # 屏蔽中国IP
    - reject(geoip:cn)
    # 屏蔽广告域名
    - reject(geosite:category-ads)
    # 直连内网IP
    - direct(private)
    # 其他流量直连
    - direct(all)
EOF
            ;;
        2)
            echo "请输入ACL规则，每行一条，输入EOF结束："
            echo "示例："
            echo "reject(geoip:cn)"
            echo "reject(geosite:category-ads)"
            echo "direct(private)"
            echo "direct(all)"
            
            rules=""
            while read -p "> " rule; do
                [[ "${rule}" == "EOF" ]] && break
                rules="${rules}    - ${rule}\n"
            done
            
            if [[ ! -z "${rules}" ]]; then
                echo -e "\nacl:\n  rules:\n${rules}" >> /etc/hysteria/config.yaml
            fi
            ;;
    esac
}

# 添加生成二维码函数
generate_qr() {
    if ! command -v qrencode &> /dev/null; then
        if [[ ${release} == "alpine" ]]; then
            apk add qrencode
        elif [[ ${release} == "centos" ]]; then
            yum install qrencode -y
        else
            apt install qrencode -y
        fi
    fi
    
    echo -e "${GREEN}分享二维码:${PLAIN}"
    qrencode -t ANSIUTF8 "${share_link}"
}

# 生成分享链接
generate_uri() {
    ip=$(curl -s4m8 ip.sb) || ip=$(curl -s6m8 ip.sb)
    
    if [[ -z "${domain}" ]]; then
        share_link="hy2://${auth_pass}@${ip}:${port}"
    else
        share_link="hy2://${auth_pass}@${domain}:${port}"
    fi
    
    echo -e "分享链接: ${GREEN}${share_link}${PLAIN}"
}

# 主菜单
show_menu() {
    echo -e "
  ${GREEN}Hysteria 2 管理脚本${PLAIN}
  ${GREEN}1.${PLAIN}  安装 Hysteria 2
  ${GREEN}2.${PLAIN}  更新 Hysteria 2
  ${GREEN}3.${PLAIN}  卸载 Hysteria 2
  ${GREEN}4.${PLAIN}  启动 Hysteria 2
  ${GREEN}5.${PLAIN}  停止 Hysteria 2
  ${GREEN}6.${PLAIN}  重启 Hysteria 2
  ${GREEN}7.${PLAIN}  查看运行状态
  ${GREEN}8.${PLAIN}  查看配置
  ${GREEN}9.${PLAIN}  修改配置
  ${GREEN}10.${PLAIN} 查看日志
  ${GREEN}11.${PLAIN} 查看分享链接
  ${GREEN}12.${PLAIN} 显示分享二维码
  ${GREEN}0.${PLAIN}  退出脚本
 "
    echo && read -p "请输入选择 [0-12]: " num
    
    case "${num}" in
        1) install_hysteria && generate_config && start_service ;;
        2) install_hysteria ;;
        3) remove_hysteria ;;
        4) start_service ;;
        5) stop_service ;;
        6) restart_service ;;
        7) check_status ;;
        8) cat /etc/hysteria/config.yaml ;;
        9) generate_config && restart_service ;;
        10) check_logs ;;
        11) generate_uri ;;
        12) generate_qr ;;
        0) exit 0 ;;
        *) echo -e "${RED}请输入正确的数字 [0-12]${PLAIN}" ;;
    esac
}

# 创建命令链接
create_command_link() {
    rm -f /usr/bin/hy2
    ln -s $0 /usr/bin/hy2
    chmod +x /usr/bin/hy2
}

# 添加服务控制函数
start_service() {
    if [[ ${release} == "alpine" ]]; then
        rc-service hysteria start
    else
        systemctl start hysteria-server.service
    fi
}

stop_service() {
    if [[ ${release} == "alpine" ]]; then
        rc-service hysteria stop
    else
        systemctl stop hysteria-server.service
    fi
}

restart_service() {
    if [[ ${release} == "alpine" ]]; then
        rc-service hysteria restart
    else
        systemctl restart hysteria-server.service
    fi
}

check_status() {
    if [[ ${release} == "alpine" ]]; then
        rc-service hysteria status
    else
        systemctl status hysteria-server.service
    fi
}

check_logs() {
    if [[ ${release} == "alpine" ]]; then
        tail -f /var/log/messages | grep hysteria
    else
        journalctl -xen -u hysteria-server.service
    fi
}

remove_hysteria() {
    if [[ ${release} == "alpine" ]]; then
        rc-service hysteria stop
        rc-update del hysteria default
        rm -f /usr/local/bin/hysteria
        rm -f /etc/init.d/hysteria
        rm -rf /etc/hysteria
        rm -rf /var/log/hysteria
        echo -e "${GREEN}Hysteria2 已卸载！${PLAIN}"
    else
        export FORCE_NO_SYSTEMD=2
        bash <(curl -fsSL https://get.hy2.sh/) --remove
    fi
}

# 主程序
main() {
    [[ ! -f /usr/bin/hy2 ]] && create_command_link
    show_menu
}

main 