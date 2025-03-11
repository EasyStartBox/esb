#!/usr/bin/env bash
# auto_cert.sh - 全自动申请 Let's Encrypt 证书（支持多种客户端）
# 1. 列出本机检测到的公网IP让用户选择（可包含IPv6）
# 2. 用户输入/自动生成子域名前缀 -> 组成完整域名
# 3. 调用远程 DNS API 添加域名记录
# 4. 检查80端口占用，必要时终止进程
# 5. 根据用户选择使用 certbot 或 acme.sh 验证并签发证书

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

# 安装基本依赖
install_dep

# 选择证书客户端
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

######################################################## 获取所有公网IP

# 准备记录IP的关联数组（去重用）
declare -A seen_public_ipv4 seen_public_ipv6

# 用数组分别保存不同类型的IP
public_ipv4=()
public_ipv6=()
private_ipv4=()
private_ipv6=()

# 添加一个IPv4格式验证函数
is_ipv4() {
    local ip=$1
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# 修改获取公网IPv4的代码
echo "正在检测公网IPv4..."
for service in "ifconfig.me" "ip.sb" "ipinfo.io/ip" "api.ipify.org"; do
    ip=$(curl -4 -s -m 5 "$service" 2>/dev/null || echo "")
    if [[ -n "$ip" && -z "${seen_public_ipv4[$ip]}" ]] && is_ipv4 "$ip"; then
        public_ipv4+=("$ip")
        seen_public_ipv4["$ip"]=1
    fi
done

# 获取公网IPv6（需服务支持IPv6）
echo "正在检测公网IPv6..."
for service in "ifconfig.co" "ipv6.icanhazip.com"; do
    ip=$(curl -6 -s -m 5 "$service" 2>/dev/null || echo "")
    if [[ -n "$ip" && -z "${seen_public_ipv6[$ip]}" ]]; then
        public_ipv6+=("$ip")
        seen_public_ipv6["$ip"]=1
    fi
done

# 获取内网IPv4地址
echo "正在检测内网IPv4..."
while IFS= read -r line; do
    if [[ "$line" != "127.0.0.1" ]]; then
        private_ipv4+=("$line")
    fi
done < <(ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1)

# 获取内网IPv6地址
echo "正在检测内网IPv6..."
while IFS= read -r line; do
    # 排除回环地址（例如::1）
    if [[ "$line" != "::1" ]]; then
        private_ipv6+=("$line")
    fi
done < <(ip -o -6 addr show | awk '{print $4}' | cut -d/ -f1)

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

# 尝试添加域名记录
if ! add_domain "$full_domain" "$public_ip"; then
    echo "请更换前缀或修改IP后再试。"
    exit 1
fi

######################################################## 处理端口占用

# 检查 80 端口占用
port_in_use=$(lsof -i:80 -t || true)
restart_services=()        # 记录需要重启的系统服务
docker_containers=""       # 记录停止的Docker容器
manual_killed=()           # 记录手动终止的进程信息

if [ -n "$port_in_use" ]; then
    echo "检测到80端口被以下进程占用："
    lsof -i:80

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
        docker_containers=$(docker ps -q --filter "publish=80")
        if [ -n "$docker_containers" ]; then
            echo "检测到 Docker 容器，正在停止..."
            docker stop $docker_containers
            restart_services+=("docker")
        fi
    fi

    # 再次检查端口占用
    port_in_use=$(lsof -i:80 -t 2>/dev/null | xargs || true)
    if [ -n "$port_in_use" ]; then
        echo "80端口仍被以下进程占用："
        lsof -i:80

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
            echo "无法使用80端口，申请证书可能失败。"
            exit 1
        fi
    fi
fi

######################################################## 申请证书

# 设置证书安装路径
TMP_INSTALL_CERT_PATH="/root/cert/${full_domain}"
mkdir -p "$TMP_INSTALL_CERT_PATH"

# 申请证书，根据选择的客户端执行不同的命令
case "$cert_client" in
    "certbot")
        echo "使用 certbot 申请证书..."
        certbot certonly --standalone -d "$full_domain" --agree-tos --register-unsafely-without-email --no-eff-email --force-renewal
        
        if [ $? -eq 0 ]; then
            echo "证书申请成功。"
            cert_path="/etc/letsencrypt/live/$full_domain"
            
            # 将证书复制到目标目录
            cp "${cert_path}/fullchain.pem" "${TMP_INSTALL_CERT_PATH}/fullchain.pem"
            cp "${cert_path}/privkey.pem" "${TMP_INSTALL_CERT_PATH}/privkey.pem"
            
            # 设置证书权限
            chmod 644 "${TMP_INSTALL_CERT_PATH}/fullchain.pem"
            chmod 644 "${TMP_INSTALL_CERT_PATH}/privkey.pem"
            
            echo "证书已安装到: $TMP_INSTALL_CERT_PATH"
            echo "原始证书路径: $cert_path"
            echo "提示手动删除证书命令1(推荐): certbot delete --cert-name $full_domain && rm -rf ${TMP_INSTALL_CERT_PATH}"
            echo "提示手动删除证书命令2(不推荐): rm -rf /etc/letsencrypt/live/$full_domain && rm -rf /etc/letsencrypt/archive/$full_domain && rm -rf /etc/letsencrypt/renewal/$full_domain.conf && rm -rf ${TMP_INSTALL_CERT_PATH}"
        else
            echo "证书申请失败。请检查防火墙、DNS解析、80端口等。"
            exit 1
        fi
        ;;
        
    "acme.sh")
        echo "使用 acme.sh 申请证书..."
        # 确保 acme.sh 命令可用
        if [ -f "$HOME/.acme.sh/acme.sh" ]; then
            cd "$HOME" || exit
            
            # 使用 acme.sh 申请证书 (HTTP 验证)
            "$HOME/.acme.sh/acme.sh" --issue -d "$full_domain" --standalone
            
            if [ $? -eq 0 ]; then
                echo "证书申请成功。"
                
                # 将证书安装到指定目录
                "$HOME/.acme.sh/acme.sh" --install-cert -d "$full_domain" \
                    --key-file "${TMP_INSTALL_CERT_PATH}/privkey.pem" \
                    --fullchain-file "${TMP_INSTALL_CERT_PATH}/fullchain.pem"
                
                # 设置证书权限
                chmod 644 "${TMP_INSTALL_CERT_PATH}/fullchain.pem"
                chmod 644 "${TMP_INSTALL_CERT_PATH}/privkey.pem"
                
                echo "证书已安装到: $TMP_INSTALL_CERT_PATH"
                echo "提示手动删除证书命令: ~/.acme.sh/acme.sh --remove -d $full_domain && rm -rf ${TMP_INSTALL_CERT_PATH}"
            else
                echo "证书申请失败。请检查防火墙、DNS解析、80端口等。"
                exit 1
            fi
        else
            echo "acme.sh 安装出错，无法找到可执行文件。"
            exit 1
        fi
        ;;
esac

######################################################## 恢复服务

# 恢复自动停止的服务
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

echo "全部完成！"