#!/usr/bin/env bash
# auto_cert.sh - 极简版全自动申请 Let's Encrypt 证书（使用 certbot）
# 1. 列出本机检测到的公网IP让用户选择（可包含IPv6）
# 2. 用户输入/自动生成子域名前缀 -> 组成完整域名
# 3. 调用远程 DNS API 添加域名记录
# 4. 检查80端口占用，必要时终止进程
# 5. 使用 certbot --standalone 验证并签发证书

set -e

# 服务器上跑 bind_dns_api_server.py 的地址（可能是你的DNS服务器的公网IP）
DNS_API_SERVER="178.157.56.29"
DNS_API_PORT=5050

# 你在 Bind 配置中管理的子域后缀
DOMAIN_SUFFIX="ns.washvoid.com"

# 检查并安装缺少的依赖
for cmd in jq lsof curl wget socat certbot; do
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



######################################################## 获取所有公网IP


# 准备记录IP的关联数组（去重用）
declare -A seen_public_ipv4 seen_public_ipv6

# 用数组分别保存不同类型的IP
public_ipv4=()
public_ipv6=()
private_ipv4=()
private_ipv6=()

# 获取公网IPv4，使用curl超时参数避免卡住
echo "正在检测公网IPv4..."
for service in "ifconfig.me" "ip.sb" "ipinfo.io/ip" "api.ipify.org"; do
    ip=$(curl -s -m 5 "$service" 2>/dev/null || echo "")
    if [[ -n "$ip" && -z "${seen_public_ipv4[$ip]}" ]]; then
        public_ipv4+=("$ip")
        seen_public_ipv4["$ip"]=1
    fi
done
sleep 1
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




######################################################## 获取所有公网IP


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

发送 JSON 请求到 DNS API
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

# 调用 certbot --standalone 申请
# 注意要确保此时外网 dig $full_domain 能解析到 $public_ip 且80端口可访问到此机
echo "开始申请证书..."

# 尝试使用 Let's Encrypt 申请证书
certbot certonly --standalone -d "$full_domain" --agree-tos --no-eff-email --force-renewal --email "your-email@example.com"

if [ $? -eq 0 ]; then
    echo "证书申请成功。certbot 默认会自动续期。"
else
    echo "证书申请失败。请检查防火墙、DNS解析、80端口等。"
    exit 1
fi

# 获取证书路径
cert_path="/etc/letsencrypt/live/$full_domain"

echo "证书已安装到: $cert_path"
echo "证书文件: ${cert_path}/fullchain.pem"
echo "私钥文件: ${cert_path}/privkey.pem"

# 设置证书权限
chmod 644 "${cert_path}/fullchain.pem"
chmod 644 "${cert_path}/privkey.pem"



# 在证书申请成功后，添加以下代码将证书安装到指定目录
TMP_INSTALL_CERT_PATH="/root/cert/${full_domain}"
mkdir -p "$TMP_INSTALL_CERT_PATH"

# 将证书复制到目标目录
cp "${cert_path}/fullchain.pem" "${TMP_INSTALL_CERT_PATH}/fullchain.pem"
cp "${cert_path}/privkey.pem" "${TMP_INSTALL_CERT_PATH}/privkey.pem"

echo "证书已安装到: $TMP_INSTALL_CERT_PATH"

# 设置证书权限
chmod 644 "${TMP_INSTALL_CERT_PATH}/fullchain.pem"
chmod 644 "${TMP_INSTALL_CERT_PATH}/privkey.pem"

echo "证书安装完成。"
echo "提示手动删除证书命令1(推荐): certbot delete --cert-name $full_domain && rm -rf ${TMP_INSTALL_CERT_PATH}"
echo "提示手动删除证书命令2(不推荐): rm -rf /etc/letsencrypt/live/$full_domain && rm -rf /etc/letsencrypt/archive/$full_domain && rm -rf /etc/letsencrypt/renewal/$full_domain.conf && rm -rf ${TMP_INSTALL_CERT_PATH}"




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