#!/usr/bin/env bash
# auto_cert.sh - 全自动申请 Let's Encrypt 证书（支持多种客户端）
# 1. 列出本机检测到的公网IP让用户选择（可包含IPv6）
# 2. 用户输入/自动生成子域名前缀 -> 组成完整域名
# 3. 调用远程 DNS API 添加域名记录
# 4. 检查80端口占用，必要时终止进程
# 5. 根据用户选择使用 certbot 或 acme.sh 验证并签发证书
# 6. 支持测试证书申请、手动吊销证书和手动续期功能

set -e

# 服务器上跑 bind_dns_api_server.py 的地址（可能是你的DNS服务器的公网IP）
DNS_API_SERVER="178.157.56.29"
DNS_API_PORT=5050

# 你在 Bind 配置中管理的子域后缀
DOMAIN_SUFFIX="ns.washvoid.com"

# 检查并安装常用依赖
install_dep() {
    for cmd in jq lsof curl wget socat nc; do
        if ! command -v $cmd &>/dev/null; then
            echo "缺少依赖: $cmd，正在尝试安装..."

            # 检测系统类型，选择合适的包管理器进行安装
            if command -v apt-get &>/dev/null; then
                # Debian/Ubuntu 系列
                echo "检测到 apt-get，使用 apt-get 安装 $cmd"
                apt-get update && apt-get install -y "$cmd"
            elif command -v yum &>/dev/null; then
                # CentOS/RHEL 系列
                echo "检测到 yum，使用 yum 安装 $cmd"
                yum install -y "$cmd"
            elif command -v dnf &>/dev/null; then
                # Fedora 系列
                echo "检测到 dnf，使用 dnf 安装 $cmd"
                dnf install -y "$cmd"
            else
                echo "无法自动安装 $cmd，请手动安装该依赖。"
                exit 1
            fi
        fi
    done
}

# 安装 certbot
install_certbot() {
    if ! command -v certbot &>/dev/null; then
        echo "缺少 certbot，正在尝试安装..."
        
        if command -v apt-get &>/dev/null; then
            # Debian/Ubuntu 系列
            apt-get update && apt-get install -y certbot
        elif command -v yum &>/dev/null; then
            # RHEL/CentOS 系列
            if grep -q "release 7" /etc/redhat-release 2>/dev/null; then
                # CentOS 7 需要 EPEL 仓库
                yum install -y epel-release
            fi
            yum install -y certbot
        elif command -v dnf &>/dev/null; then
            # Fedora 系列
            dnf install -y certbot
        else
            echo "无法自动安装 certbot，请手动安装。"
            exit 1
        fi
    fi
}

# 安装 acme.sh
install_acme() {
    if ! command -v acme.sh &>/dev/null && [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
        echo "缺少 acme.sh，正在安装..."
        curl https://get.acme.sh | sh -s email=admin@example.com
        if [ -f "$HOME/.acme.sh/acme.sh" ]; then
            source "$HOME/.acme.sh/acme.sh.env"
        else 
            echo "acme.sh 安装失败，请手动安装。"
            exit 1
        fi
    elif [ -f "$HOME/.acme.sh/acme.sh" ]; then
        # 确保 acme.sh 在 PATH 中
        source "$HOME/.acme.sh/acme.sh.env"
    fi
}

# 检查端口占用并清理
check_and_clear_port() {
    local port=$1
    # 检查端口占用
    port_in_use=$(lsof -i:$port -t || true)
    restart_services=()        # 记录需要重启的系统服务
    docker_containers=""       # 记录停止的Docker容器
    manual_killed=()           # 记录手动终止的进程信息

    if [ -n "$port_in_use" ]; then
        echo "检测到$port端口被以下进程占用："
        lsof -i:$port

        # 自动停止常见服务并记录
        if systemctl is-active --quiet nginx; then
            echo "检测到 Nginx，正在停止..."
            systemctl stop nginx
            restart_services+=("nginx")
        elif systemctl is-active --quiet apache2; then
            echo "检测到 Apache2，正在停止..."
            systemctl stop apache2
            restart_services+=("apache2")
        fi

        if command -v docker &>/dev/null; then
            docker_containers=$(docker ps -q --filter "publish=$port")
            if [ -n "$docker_containers" ]; then
                echo "检测到 Docker 容器，正在停止..."
                docker stop $docker_containers
                restart_services+=("docker")
            fi
        fi

        # 再次检查端口占用
        port_in_use=$(lsof -i:$port -t 2>/dev/null | xargs || true)
        if [ -n "$port_in_use" ]; then
            echo "$port端口仍被以下进程占用："
            lsof -i:$port

            read -p "是否终止这些进程以便申请证书? (回车默认停止): " ans
            ans="${ans:-y}"
            if [[ "$ans" =~ ^[Yy]$ ]]; then
                while IFS= read -r pid; do
                    if [ -z "$pid" ]; then continue; fi
                    proc_info=$(ps -p $pid -o comm=,args=)
                    if kill -9 "$pid" 2>/dev/null; then
                        echo "已终止进程PID: $pid (${proc_info})"
                        manual_killed+=("$proc_info")
                    fi
                done <<< "$port_in_use"
                sleep 2
            else
                echo "无法使用$port端口，申请证书可能失败。"
                return 1
            fi
        fi
    fi
    return 0
}

# 恢复自动停止的服务
restore_services() {
    if [[ "${restart_services[*]}" =~ "nginx" ]]; then
        echo "正在恢复 Nginx 服务..."
        systemctl start nginx
    elif [[ "${restart_services[*]}" =~ "apache2" ]]; then
        echo "正在恢复 Apache2 服务..."
        systemctl start apache2
    fi

    if [[ "${restart_services[*]}" =~ "docker" ]]; then
        echo "正在恢复 Docker 容器..."
        docker start $docker_containers
    fi

    # 提示手动终止的进程
    if [ ${#manual_killed[@]} -gt 0 ]; then
        echo -e "\n以下进程被手动终止，可能需要手动重启："
        printf "  %s\n" "${manual_killed[@]}"
    fi
}

# 设置软链接函数 (替换原来的硬链接函数)
create_cert_symlinks() {
    local source_path=$1
    local target_path=$2
    
    if [ ! -d "$target_path" ]; then
        mkdir -p "$target_path"
    fi
    
    # 移除目标文件夹中的现有文件
    rm -f "${target_path}/fullchain.pem" "${target_path}/privkey.pem"
    
    # 创建软链接
    ln -s "${source_path}/fullchain.pem" "${target_path}/fullchain.pem"
    ln -s "${source_path}/privkey.pem" "${target_path}/privkey.pem"
    
    echo "已创建证书软链接到: $target_path (与源文件同步更新)"
}

# 发送 JSON 请求到 DNS API
add_domain() {
    local domain=$1
    local ip=$2
    local json
    json=$(jq -n --arg action "add_domain" --arg d "$domain" --arg i "$ip" \
         '{action:$action, domain:$d, ip:$i}')
    echo "向DNS服务器($DNS_API_SERVER:$DNS_API_PORT)发送添加请求: $json"
    resp=$(echo "$json" | nc "$DNS_API_SERVER" "$DNS_API_PORT")
    echo "服务器响应: $resp"
    # 检查 status
    local st msg
    st=$(echo "$resp" | jq -r '.status' 2>/dev/null || true)
    msg=$(echo "$resp" | jq -r '.message' 2>/dev/null || true)
    if [ "$st" != "success" ]; then
        echo "添加失败: $msg"
        return 1
    fi
    echo "添加成功: $msg"
    return 0
}

# 申请测试证书 (Let's Encrypt 测试服务器)
issue_test_cert() {
    local domain=$1
    local is_test=$2
    local target_path="/root/cert/${domain}"
    
    echo "申请测试证书中..."
    
        # 首先添加域名记录(如果使用命令行参数)
    if [ "$USING_CLI_PARAMS" = true ]; then
        # 检测公网IP

        
        echo "检测到公网IP: $public_ip"
        if ! add_domain "$domain" "$public_ip"; then
            echo "无法添加域名记录，继续尝试申请证书..."
            # 这里可以选择继续或返回失败
        fi
    fi


    # 检查并清理80端口
    if ! check_and_clear_port 80; then
        return 1
    fi
    
    case "$cert_client" in
        "certbot")
            local test_arg=""
            if [ "$is_test" = true ]; then
                test_arg="--test-cert"
            fi
            
            certbot certonly $test_arg --standalone -d "$domain" --agree-tos --register-unsafely-without-email --no-eff-email --force-renewal
            
            if [ $? -eq 0 ]; then
                echo "测试证书申请成功。"
                local cert_path="/etc/letsencrypt/live/$domain"
                
                # 创建证书软链接
                create_cert_symlinks "$cert_path" "$target_path"
                
                echo "原始证书路径: $cert_path"
                
                if [ "$is_test" = true ]; then
                    echo "注意：这是一个测试证书，不被浏览器信任，仅用于测试！"
                fi
                
                echo "提示手动删除证书命令: certbot delete --cert-name $domain --force-delete-after-revoke --non-interactive && rm -rf ${target_path}"
            else
                echo "测试证书申请失败。请检查防火墙、DNS解析、80端口等。"
                restore_services
                return 1
            fi
            ;;
            
        "acme.sh")
            local test_arg=""
            if [ "$is_test" = true ]; then
                test_arg="--test"
            fi
            
            cd "$HOME" || exit
            
            "$HOME/.acme.sh/acme.sh" --issue $test_arg -d "$domain" --standalone
            
            if [ $? -eq 0 ]; then
                echo "测试证书申请成功。"



                mkdir -p "${target_path}"
                # 获取 acme.sh 证书目录
                acme_cert_dir="$HOME/.acme.sh/${domain}_ecc"

                # 创建软链接
                ln -sf "$acme_cert_dir/${domain}.key" "${target_path}/privkey.pem"
                ln -sf "$acme_cert_dir/fullchain.cer" "${target_path}/fullchain.pem"
                
                # # 设置证书权限
                # chmod 644 "$acme_cert_dir/${domain}.key"
                # chmod 644 "$acme_cert_dir/fullchain.cer"

                
                if [ "$is_test" = true ]; then
                    echo "注意：这是一个测试证书，不被浏览器信任，仅用于测试！"
                fi
                
                echo "提示手动删除证书命令: ~/.acme.sh/acme.sh --remove -d $domain && rm -rf ${target_path}"
            else
                echo "测试证书申请失败。请检查防火墙、DNS解析、80端口等。"
                restore_services
                return 1
            fi
            ;;
    esac
    
    # 恢复服务
    restore_services
    return 0
}

# 申请正式证书
issue_cert() {
    local domain=$1
    issue_test_cert "$domain" false
}

# 查找并列出可用的证书
list_available_certs() {
    local certs=()
    local idx=1
    
    echo "查找可用的证书..."
    
    case "$cert_client" in
        "certbot")
            # 获取certbot管理的证书列表
            if command -v certbot &>/dev/null; then
                mapfile -t cert_names < <(certbot certificates 2>/dev/null | grep "Domains:" | awk '{print $2}')
                if [ ${#cert_names[@]} -gt 0 ]; then
                    echo "Certbot证书:"
                    for name in "${cert_names[@]}"; do
                        echo "  $idx) $name"
                        certs+=("$name")
                        ((idx++))
                    done
                else
                    echo "  未找到Certbot证书"
                fi
            fi
            ;;
            
        "acme.sh")
            # 获取acme.sh管理的证书列表
            if [ -d "$HOME/.acme.sh" ]; then
                # mapfile -t cert_names < <(find "$HOME/.acme.sh" -maxdepth 1 -type d \( -name "*_ecc" -o -name "*.com" -o -name "*.org" -o -name "*.net" \) | xargs -n1 basename 2>/dev/null)

                mapfile -t cert_names < <(find "$HOME/.acme.sh" -type d -name "*_ecc" | xargs -n1 basename 2>/dev/null)
                if [ ${#cert_names[@]} -gt 0 ]; then
                    echo "acme.sh 证书:"
                    idx=1
                    for name in "${cert_names[@]}"; do
                        echo "  $idx) $name"
                        certs+=("$name")
                        ((idx++))
                    done
                else
                    echo "  未找到 acme.sh 证书"
                fi
            fi

            ;;
    esac
    
    # 检查/root/cert目录下的证书
    if [ -d "/root/cert" ]; then
        mapfile -t link_certs < <(find /root/cert -mindepth 1 -maxdepth 1 -type d | xargs -n1 basename 2>/dev/null)
        if [ ${#link_certs[@]} -gt 0 ]; then
            echo "本地链接证书:"
            for name in "${link_certs[@]}"; do
                if [[ ! " ${certs[@]} " =~ " ${name} " ]]; then
                    echo "  $idx) $name"
                    certs+=("$name")
                    ((idx++))
                fi
            done
        fi
    fi
    
    echo "  0) 手动输入域名"
    
    return $idx  # 返回下一个索引值作为证书数量+1
}

# 选择证书
select_certificate() {
    local action=$1
    local max_idx
    
    echo "================ 证书${action}操作 ================"
    list_available_certs
    max_idx=$?
    
    if [ $max_idx -eq 1 ]; then
        echo "未找到可用证书，请手动输入域名。"
        read -p "请输入域名: " domain
        return
    fi
    
    read -p "请选择证书 [0-$((max_idx-1))] (默认: 0): " cert_choice
    cert_choice="${cert_choice:-0}"
    
    if [ "$cert_choice" -eq 0 ]; then
        read -p "请输入域名: " domain
    elif [ "$cert_choice" -gt 0 ] && [ "$cert_choice" -lt "$max_idx" ]; then
        domain="${certs[$((cert_choice-1))]}"
    else
        echo "无效选择，请手动输入域名。"
        read -p "请输入域名: " domain
    fi
    
    echo "已选择域名: $domain"
}

# 手动吊销证书
revoke_cert() {
    local domain=$1
    
    echo "正在吊销证书: $domain"
    
    case "$cert_client" in
        "certbot")
            certbot revoke --cert-name "$domain" --delete-after-revoke
            if [ $? -eq 0 ]; then
                echo "证书已成功吊销并删除。"
                rm -rf "/root/cert/${domain}"
                echo "已清理软链接目录: /root/cert/${domain}"
            else
                echo "证书吊销失败，请检查域名是否正确。"
                return 1
            fi
            ;;
            
        "acme.sh")
            "$HOME/.acme.sh/acme.sh" --revoke -d "$domain" --remove
            if [ $? -eq 0 ]; then
                echo "证书已成功吊销并删除。"
                rm -rf "/root/cert/${domain}"
                echo "已清理软链接目录: /root/cert/${domain}"
            else
                echo "证书吊销失败，请检查域名是否正确。"
                return 1
            fi
            ;;
    esac
    
    return 0
}

# 手动吊销证书 - 交互式
revoke_cert_interactive() {
    select_certificate "吊销"
    if [ -n "$domain" ]; then
        revoke_cert "$domain"
    else
        echo "未指定域名，操作取消。"
    fi
}

# 手动续期证书
renew_cert() {
    local domain=$1
    
    echo "正在续期证书: $domain"
    
    # 检查并清理80端口
    if ! check_and_clear_port 80; then
        return 1
    fi
    
    case "$cert_client" in
        "certbot")
            certbot renew --cert-name "$domain" --force-renewal
            if [ $? -eq 0 ]; then
                echo "证书已成功续期。"
                local cert_path="/etc/letsencrypt/live/$domain"
                local target_path="/root/cert/${domain}"
                
                # 更新软链接
                create_cert_symlinks "$cert_path" "$target_path"
            else
                echo "证书续期失败，请检查域名是否正确。"
                restore_services
                return 1
            fi
            ;;
            
        "acme.sh")
            "$HOME/.acme.sh/acme.sh" --renew -d "$domain" --force
            if [ $? -eq 0 ]; then
                echo "证书已成功续期。"
                local target_path="/root/cert/${domain}"
                
                # 更新证书
                mkdir -p "${target_path}"
                # 获取 acme.sh 证书目录
                acme_cert_dir="$HOME/.acme.sh/${domain}_ecc"

                # 创建软链接
                ln -sf "$acme_cert_dir/${domain}.key" "${target_path}/privkey.pem"
                ln -sf "$acme_cert_dir/fullchain.cer" "${target_path}/fullchain.pem"
                
                # 设置证书权限
                # chmod 644 "$acme_cert_dir/${domain}.key"
                # chmod 644 "$acme_cert_dir/fullchain.cer"
            else
                echo "证书续期失败，请检查域名是否正确。"
                restore_services
                return 1
            fi
            ;;
    esac
    
    # 恢复服务
    restore_services
    return 0
}

# 手动续期证书 - 交互式
renew_cert_interactive() {
    select_certificate "续期"
    if [ -n "$domain" ]; then
        renew_cert "$domain"
    else
        echo "未指定域名，操作取消。"
    fi
}



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

    echo "正在检测公网IPv4..."
    for service in "ifconfig.me" "ip.sb" "ipinfo.io/ip" "api.ipify.org"; do
        ip=$(curl -4 -s -m 5 "$service" 2>/dev/null || echo "")
        if [[ -n "$ip" && -z "${seen_public_ipv4[$ip]}" ]] && is_ipv4 "$ip"; then
            public_ipv4+=("$ip")
            seen_public_ipv4["$ip"]=1
        fi
    done

    echo "正在检测公网IPv6..."
    for service in "ifconfig.co" "ipv6.icanhazip.com"; do
        ip=$(curl -6 -s -m 5 "$service" 2>/dev/null || echo "")
        if [[ -n "$ip" && -z "${seen_public_ipv6[$ip]}" ]]; then
            public_ipv6+=("$ip")
            seen_public_ipv6["$ip"]=1
        fi
    done

    echo "正在检测内网IPv4..."
    while IFS= read -r line; do
        [[ "$line" != "127.0.0.1" ]] && private_ipv4+=("$line")
    done < <(ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1)

    echo "正在检测内网IPv6..."
    while IFS= read -r line; do
        [[ "$line" != "::1" ]] && private_ipv6+=("$line")
    done < <(ip -o -6 addr show | awk '{print $4}' | cut -d/ -f1)
}




# 显示帮助菜单
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help                显示此帮助信息"
    echo "  -t, --test <域名>         申请测试证书"
    echo "  -i, --issue <域名>        申请正式证书"
    echo "  -r, --revoke [域名]       吊销并删除证书 (无参数则交互式选择)"
    echo "  -n, --renew [域名]        手动续期证书 (无参数则交互式选择)"
    echo "  无参数                    运行交互式向导"
    echo
    echo "示例:"
    echo "  $0                        运行交互式证书管理向导"
    echo "  $0 -t example.com         为 example.com 申请测试证书"
    echo "  $0 -r                     交互式选择并吊销证书"
    echo "  $0 -r example.com         吊销 example.com 的证书"
}




# 主函数
main() {
    # 安装基本依赖
    install_dep

    # 如果没有参数，运行交互式向导
    if [ $# -eq 0 ]; then
        echo "========== Let's Encrypt 证书管理工具 =========="
        echo "1) 申请新证书"
        echo "2) 吊销证书"
        echo "3) 手动续期证书"
        read -p "请选择操作 [1-3] (默认: 1): " main_choice
        main_choice="${main_choice:-1}"
        
        # 选择证书客户端
        select_client
        
        case "$main_choice" in
            1)
                interactive_wizard
                ;;
            2)
                revoke_cert_interactive
                ;;
            3)
                renew_cert_interactive
                ;;
            *)
                echo "无效选择，默认使用申请新证书。"
                interactive_wizard
                ;;
        esac
        return
    fi

    USING_CLI_PARAMS=false
    # 解析命令行参数
    case "$1" in
        -h|--help)
            show_help
            ;;
        -t|--test)
            USING_CLI_PARAMS=true
            if [ -z "$2" ]; then
                echo "错误: 缺少域名参数"
                show_help
                exit 1
            fi
            
            # 选择证书客户端
            select_client
            
            issue_test_cert "$2" true
            ;;
        -i|--issue)
            USING_CLI_PARAMS=true
            if [ -z "$2" ]; then
                echo "错误: 缺少域名参数"
                show_help
                exit 1
            fi
            
            # 选择证书客户端
            select_client
            
            issue_cert "$2"
            ;;
        -r|--revoke)
            if [ -z "$2" ]; then
                # 选择证书客户端
                select_client
                revoke_cert_interactive
            else
                # 选择证书客户端
                select_client
                revoke_cert "$2"
            fi
            ;;
        -n|--renew)
            if [ -z "$2" ]; then
                # 选择证书客户端
                select_client
                renew_cert_interactive
            else
                # 选择证书客户端
                select_client
                renew_cert "$2"
            fi
            ;;
        *)
            echo "错误: 未知选项 $1"
            show_help
            exit 1
            ;;
    esac
}




# 选择证书客户端
select_client() {
    echo "请选择证书申请客户端："
    echo "1) certbot (默认)"
    echo "2) acme.sh"
    read -p "请输入选择 [1-2] (默认: 1): " cert_client_choice
    cert_client_choice="${cert_client_choice:-1}"

    # 根据选择安装相应的客户端
    case "$cert_client_choice" in
        1)
            cert_client="certbot"
            install_certbot
            ;;
        2)
            cert_client="acme.sh"
            install_acme
            ;;
        *)
            echo "无效选择，默认使用 certbot。"
            cert_client="certbot"
            install_certbot
            ;;
    esac

    echo "已选择 $cert_client 作为证书申请客户端"
}

# 交互式向导
interactive_wizard() {
    # 选择证书客户端
    select_client

    ######################################################## 获取所有公网IP
    get_ips


    # 显示IP列表
    echo "检测到的IP列表："
    idx=1
    ip_list=()

    if [ ${#public_ipv4[@]} -gt 0 ]; then
        echo "公网IPv4:"
        for ip in "${public_ipv4[@]}"; do
            echo "  $idx) $ip"
            ip_list+=("$ip")
            ((idx++))
        done
    fi

    if [ ${#public_ipv6[@]} -gt 0 ]; then
        echo "公网IPv6:"
        for ip in "${public_ipv6[@]}"; do
            echo "  $idx) $ip"
            ip_list+=("$ip")
            ((idx++))
        done
    fi

    if [ ${#private_ipv4[@]} -gt 0 ]; then
        echo "内网IPv4:"
        for ip in "${private_ipv4[@]}"; do
            echo "  $idx) $ip"
            ip_list+=("$ip")
            ((idx++))
        done
    fi

    if [ ${#private_ipv6[@]} -gt 0 ]; then
        echo "内网IPv6:"
        for ip in "${private_ipv6[@]}"; do
            echo "  $idx) $ip"
            ip_list+=("$ip")
            ((idx++))
        done
    fi

    echo "  0)  使用以上列表外的自定义IP"
    read -p "请选择IP序号（默认选择第一个公网IPv4）: " choice
    choice="${choice:-1}"

    # 处理用户选择
    if [[ "$choice" == "0" ]]; then
        read -p "请输入自定义IP: " custom_ip
        public_ip="$custom_ip"
    else
        # 如果用户输入超范围或者不是数字，则使用默认值 1
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#ip_list[@]}" ]; then
            choice=1
        fi
        public_ip="${ip_list[$((choice-1))]}"
    fi

    echo "使用 IP: $public_ip"

    ######################################################## 获取域名

    # 生成随机前缀函数
    generate_prefix() {
        tr -dc 'a-z0-9' </dev/urandom | head -c6
    }

    # 提示用户输入子域名前缀（回车则自动生成）
    read -p "请输入子域名前缀（回车自动生成）: " prefix
    if [ -z "$prefix" ]; then
        prefix=$(generate_prefix)
    fi

    full_domain="${prefix}.${DOMAIN_SUFFIX}"
    echo "完整域名: $full_domain"

    # 询问是否申请测试证书
    read -p "是否申请测试证书 (y/N)? " test_cert
    is_test_cert=false
    if [[ "$test_cert" =~ ^[Yy]$ ]]; then
        is_test_cert=true
        echo "将申请测试证书（不被浏览器信任，仅用于测试）"
    fi

    # 尝试添加域名记录
    if ! add_domain "$full_domain" "$public_ip"; then
        echo "请更换前缀或修改IP后再试。"
        exit 1
    fi

    ######################################################## 申请证书

    if [ "$is_test_cert" = true ]; then
        issue_test_cert "$full_domain" true
    else
        issue_cert "$full_domain"
    fi
}

# 执行主函数
main "$@"