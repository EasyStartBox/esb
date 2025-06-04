#!/bin/bash

# SSL证书申请脚本
# 使用acme.sh进行HTTP端口验证申请证书

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 全局变量
restart_services=()
docker_containers=""
manual_killed=()
domain=""
target_path=""
is_test=false

# 显示帮助信息
show_help() {
    echo -e "${BLUE}SSL证书申请脚本使用说明${NC}"
    echo "=============================================="
    echo "用法: $0 [选项] <域名>"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示帮助信息"
    echo "  -t, --test     申请测试证书"
    echo "  -p, --path     指定证书保存路径 (默认: /etc/ssl/certs/\$domain)"
    echo ""
    echo "示例:"
    echo "  $0 example.com"
    echo "  $0 -t example.com"
    echo "  $0 -p /path/to/certs example.com"
    echo ""
    echo "说明:"
    echo "  - 使用HTTP端口验证方式申请证书"
    echo "  - 需要确保域名已正确解析到本机IP"
    echo "  - 需要80端口可用(会自动处理端口占用)"
    echo "  - 证书将保存为软链接形式"
    exit 0
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                ;;
            -t|--test)
                is_test=true
                shift
                ;;
            -p|--path)
                target_path="$2"
                shift 2
                ;;
            -*)
                echo -e "${RED}未知选项: $1${NC}"
                show_help
                ;;
            *)
                if [ -z "$domain" ]; then
                    domain="$1"
                else
                    echo -e "${RED}只能指定一个域名${NC}"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [ -z "$domain" ]; then
        show_help
    fi

    # 设置默认证书路径
    if [ -z "$target_path" ]; then
        target_path="/etc/ssl/certs/$domain"
    fi
}

# 检查acme.sh安装状态
check_acme_installation() {
    echo -e "${BLUE}检查 acme.sh 安装状态...${NC}"
    
    if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
        echo -e "${YELLOW}acme.sh 未安装，正在自动安装...${NC}"
        
        # 安装acme.sh
        curl https://get.acme.sh | sh -s email=153848050@qq.com || {
            echo -e "${RED}acme.sh 安装失败${NC}"
            exit 1
        }
        
        # 重新加载环境变量
        source ~/.bashrc
        
        echo -e "${GREEN}acme.sh 安装完成${NC}"
    else
        echo -e "${GREEN}acme.sh 已安装${NC}"
    fi
}

# 获取本机IP信息
get_ips() {
    declare -A seen_public_ipv4 seen_public_ipv6
    public_ipv4=()
    public_ipv6=()
    private_ipv4=()
    private_ipv6=()

    is_ipv4() {
        local ip=$1
        [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
    }

    echo -e "${BLUE}正在检测公网IPv4...${NC}"
    for service in "ifconfig.me" "ip.sb" "ipinfo.io/ip" "api.ipify.org"; do
        ip=$(curl -4 -s -m 5 "$service" 2>/dev/null || echo "")
        if [[ -n "$ip" && -z "${seen_public_ipv4[$ip]}" ]] && is_ipv4 "$ip"; then
            public_ipv4+=("$ip")
            seen_public_ipv4["$ip"]=1
        fi
    done

    echo -e "${BLUE}正在检测公网IPv6...${NC}"
    for service in "ifconfig.co" "ipv6.icanhazip.com"; do
        ip=$(curl -6 -s -m 5 "$service" 2>/dev/null || echo "")
        if [[ -n "$ip" && -z "${seen_public_ipv6[$ip]}" ]]; then
            public_ipv6+=("$ip")
            seen_public_ipv6["$ip"]=1
        fi
    done

    echo -e "${BLUE}正在检测内网IPv4...${NC}"
    while IFS= read -r line; do
        [[ "$line" != "127.0.0.1" ]] && private_ipv4+=("$line")
    done < <(ip -o -4 addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1)

    echo -e "${BLUE}正在检测内网IPv6...${NC}"
    while IFS= read -r line; do
        [[ "$line" != "::1" ]] && private_ipv6+=("$line")
    done < <(ip -o -6 addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
}

# 显示IP信息
show_ip_info() {
    echo -e "\n${YELLOW}=== 本机IP信息 ===${NC}"
    
    if [ ${#public_ipv4[@]} -gt 0 ]; then
        echo -e "${GREEN}公网IPv4:${NC}"
        printf "  %s\n" "${public_ipv4[@]}"
    else
        echo -e "${RED}未检测到公网IPv4${NC}"
    fi
    
    if [ ${#public_ipv6[@]} -gt 0 ]; then
        echo -e "${GREEN}公网IPv6:${NC}"
        printf "  %s\n" "${public_ipv6[@]}"
    fi
    
    if [ ${#private_ipv4[@]} -gt 0 ]; then
        echo -e "${BLUE}内网IPv4:${NC}"
        printf "  %s\n" "${private_ipv4[@]}"
    fi
}

# 检查域名解析
check_domain_resolution() {
    echo -e "\n${YELLOW}=== 检查域名解析 ===${NC}"
    echo -e "${BLUE}域名: $domain${NC}"
    
    # 检查A记录
    domain_ipv4=$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    if [ -n "$domain_ipv4" ]; then
        echo -e "${GREEN}域名IPv4解析: $domain_ipv4${NC}"
    else
        echo -e "${RED}未检测到域名IPv4解析${NC}"
    fi
    
    # 检查AAAA记录
    domain_ipv6=$(dig +short AAAA "$domain" 2>/dev/null | head -1)
    if [ -n "$domain_ipv6" ]; then
        echo -e "${GREEN}域名IPv6解析: $domain_ipv6${NC}"
    fi
}

# 检查并清理端口占用
check_and_clear_port() {
    local port=$1
    echo -e "\n${BLUE}检查端口 $port 占用情况...${NC}"
    
    # 检查端口占用
    port_in_use=$(lsof -i:$port -t 2>/dev/null || true)
    restart_services=()
    docker_containers=""
    manual_killed=()

    if [ -n "$port_in_use" ]; then
        echo -e "${YELLOW}检测到$port端口被以下进程占用：${NC}"
        lsof -i:$port

        # 自动停止常见服务并记录
        if systemctl is-active --quiet nginx 2>/dev/null; then
            echo -e "${YELLOW}检测到 Nginx，正在停止...${NC}"
            systemctl stop nginx
            restart_services+=("nginx")
        elif systemctl is-active --quiet apache2 2>/dev/null; then
            echo -e "${YELLOW}检测到 Apache2，正在停止...${NC}"
            systemctl stop apache2
            restart_services+=("apache2")
        fi

        if command -v docker &>/dev/null; then
            docker_containers=$(docker ps -q --filter "publish=$port" 2>/dev/null || true)
            if [ -n "$docker_containers" ]; then
                echo -e "${YELLOW}检测到 Docker 容器，正在停止...${NC}"
                docker stop $docker_containers
                restart_services+=("docker")
            fi
        fi

        # 再次检查端口占用
        port_in_use=$(lsof -i:$port -t 2>/dev/null | xargs || true)
        if [ -n "$port_in_use" ]; then
            echo -e "${YELLOW}$port端口仍被以下进程占用：${NC}"
            lsof -i:$port

            read -p "是否终止这些进程以便申请证书? (回车默认停止): " ans
            ans="${ans:-y}"
            if [[ "$ans" =~ ^[Yy]$ ]]; then
                while IFS= read -r pid; do
                    if [ -z "$pid" ]; then continue; fi
                    proc_info=$(ps -p $pid -o comm=,args= 2>/dev/null || echo "进程已结束")
                    if kill -9 "$pid" 2>/dev/null; then
                        echo -e "${GREEN}已终止进程PID: $pid (${proc_info})${NC}"
                        manual_killed+=("$proc_info")
                    fi
                done <<< "$port_in_use"
                sleep 2
            else
                echo -e "${RED}无法使用$port端口，申请证书可能失败。${NC}"
                return 1
            fi
        fi
    else
        echo -e "${GREEN}端口 $port 未被占用${NC}"
    fi
    return 0
}

# 恢复自动停止的服务
restore_services() {
    echo -e "\n${BLUE}恢复服务...${NC}"
    
    if [[ "${restart_services[*]}" =~ "nginx" ]]; then
        echo -e "${YELLOW}正在恢复 Nginx 服务...${NC}"
        systemctl start nginx
    elif [[ "${restart_services[*]}" =~ "apache2" ]]; then
        echo -e "${YELLOW}正在恢复 Apache2 服务...${NC}"
        systemctl start apache2
    fi

    if [[ "${restart_services[*]}" =~ "docker" ]] && [ -n "$docker_containers" ]; then
        echo -e "${YELLOW}正在恢复 Docker 容器...${NC}"
        docker start $docker_containers
    fi

    # 提示手动终止的进程
    if [ ${#manual_killed[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}以下进程被手动终止，可能需要手动重启：${NC}"
        printf "  %s\n" "${manual_killed[@]}"
    fi
}

# 申请证书
request_certificate() {
    echo -e "\n${BLUE}开始申请证书...${NC}"
    
    local acme_cmd="$HOME/.acme.sh/acme.sh --issue -d $domain --standalone --keylength ec-256"
    
    if [ "$is_test" = true ]; then
        acme_cmd="$acme_cmd --staging"
        echo -e "${YELLOW}使用测试模式申请证书${NC}"
    fi
    
    echo -e "${BLUE}执行命令: $acme_cmd${NC}"
    
    if eval "$acme_cmd"; then
        echo -e "${GREEN}证书申请成功！${NC}"
        return 0
    else
        echo -e "${RED}证书申请失败！请检查防火墙、DNS解析、80端口等。${NC}"
        return 1
    fi
}

# 安装证书
install_certificate() {
    echo -e "\n${BLUE}安装证书到指定目录...${NC}"
    
    mkdir -p "${target_path}"
    
    # 获取 acme.sh 证书目录
    acme_cert_dir="$HOME/.acme.sh/${domain}_ecc"
    
    if [ ! -d "$acme_cert_dir" ]; then
        echo -e "${RED}证书目录不存在: $acme_cert_dir${NC}"
        return 1
    fi
    
    # 创建软链接
    ln -sf "$acme_cert_dir/${domain}.key" "${target_path}/privkey.pem"
    ln -sf "$acme_cert_dir/fullchain.cer" "${target_path}/fullchain.pem"
    
    echo -e "${GREEN}证书已安装到: ${target_path}${NC}"
    echo -e "${GREEN}私钥文件: ${target_path}/privkey.pem${NC}"
    echo -e "${GREEN}证书链文件: ${target_path}/fullchain.pem${NC}"
    
    if [ "$is_test" = true ]; then
        echo -e "${YELLOW}注意：这是一个测试证书，不被浏览器信任，仅用于测试！${NC}"
    fi
}

# 询问是否创建证书链接
ask_create_links() {
    echo -e "\n${YELLOW}是否创建证书的其他格式链接？${NC}"
    read -p "创建更多格式的证书链接 (y/n, 默认n): " create_links
    
    if [[ "$create_links" =~ ^[Yy]$ ]]; then
        acme_cert_dir="$HOME/.acme.sh/${domain}_ecc"
        
        # 创建更多格式的链接
        [ -f "$acme_cert_dir/ca.cer" ] && ln -sf "$acme_cert_dir/ca.cer" "${target_path}/ca.pem"
        [ -f "$acme_cert_dir/${domain}.cer" ] && ln -sf "$acme_cert_dir/${domain}.cer" "${target_path}/cert.pem"
        
        echo -e "${GREEN}已创建额外的证书链接${NC}"
    fi
}

# 显示管理命令
show_management_commands() {
    echo -e "\n${YELLOW}=== 证书管理命令 ===${NC}"
    echo -e "${BLUE}吊销证书命令:${NC}"
    echo "  ~/.acme.sh/acme.sh --revoke -d $domain --ecc"
    
    echo -e "\n${BLUE}删除证书命令:${NC}"
    echo "  ~/.acme.sh/acme.sh --remove -d $domain --ecc && rm -rf ${target_path}"
    
    echo -e "\n${BLUE}续期证书命令:${NC}"
    echo "  ~/.acme.sh/acme.sh --renew -d $domain --ecc --force"
    
    echo -e "\n${BLUE}查看证书信息:${NC}"
    echo "  ~/.acme.sh/acme.sh --info -d $domain --ecc"
}

# 主函数
main() {
    # 解析参数
    parse_args "$@"
    
    echo -e "${GREEN}SSL证书申请脚本${NC}"
    echo "域名: $domain"
    echo "证书路径: $target_path"
    echo "测试模式: $is_test"
    echo "=============================="
    
    # 检查acme.sh安装
    check_acme_installation
    
    # 获取IP信息
    get_ips
    show_ip_info
    
    # 检查域名解析
    check_domain_resolution
    
    # 询问是否继续
    echo -e "\n${YELLOW}请确认域名已正确解析到本机IP地址${NC}"
    read -p "是否继续申请证书？(回车默认继续): " continue_apply
    continue_apply="${continue_apply:-y}"
    
    if [[ ! "$continue_apply" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}已取消申请${NC}"
        exit 0
    fi
    
    # 检查和清理端口
    if ! check_and_clear_port 80; then
        echo -e "${RED}端口检查失败，退出${NC}"
        exit 1
    fi
    
    # 申请证书
    if request_certificate; then
        # 安装证书
        install_certificate
        
        # 恢复服务
        restore_services
        
        # 询问创建链接
        ask_create_links
        
        # 显示管理命令
        show_management_commands
        
        echo -e "\n${GREEN}证书申请完成！${NC}"
    else
        # 恢复服务
        restore_services
        exit 1
    fi
}

# 如果没有参数，显示帮助
if [ $# -eq 0 ]; then
    show_help
fi

# 运行主函数
main "$@"
