#!/usr/bin/env bash
# auto_cert.sh - 极简版全自动申请 Let's Encrypt 证书
# 1. 列出本机检测到的公网IP让用户选择（可包含IPv6）
# 2. 用户输入/自动生成子域名前缀 -> 组成完整域名
# 3. 调用远程 DNS API 添加域名记录
# 4. 检查80端口占用，必要时终止进程
# 5. 调用 acme.sh --standalone 验证并签发证书

set -e

# 服务器上跑 dns_api_server.py 的地址（可能是你的DNS服务器的公网IP）
DNS_API_SERVER="178.157.56.29"
DNS_API_PORT=5050

# 你在 Bind 配置中管理的子域后缀
DOMAIN_SUFFIX="ns.washvoid.com"

# 检查并安装缺少的依赖
for cmd in jq lsof curl wget socat; do
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

# 安装 netcat-openbsd
if ! command -v nc &>/dev/null; then
    echo "缺少依赖: nc，正在尝试安装..."
    if command -v apt-get &>/dev/null; then
        echo "检测到 apt-get，使用 apt-get 安装 netcat-openbsd"
        apt-get update && apt-get install -y netcat-openbsd
    else
        echo "无法自动安装 netcat-openbsd，请手动安装该依赖。"
        exit 1
    fi
fi



# 如果 acme.sh 未安装，自动安装（需要网络）
if ! command -v acme.sh &>/dev/null; then
    echo "acme.sh 未找到，正在自动安装..."
    curl https://get.acme.sh | sh
    # 加载 acme.sh 环境（若安装在 /root/.acme.sh 则可能需要 source 其配置）
    export PATH="$HOME/.acme.sh":$PATH
fi

# 安装 socat（若系统无此包，建议安装，否则standalone模式可能失败）
if ! command -v socat &>/dev/null; then
    echo "socat 不存在，正在尝试安装（若是Debian/Ubuntu: apt-get install socat）"
    if command -v apt-get &>/dev/null; then
        apt-get update && apt-get install -y socat || true
    elif command -v yum &>/dev/null; then
        yum install -y socat || true
    elif command -v dnf &>/dev/null; then
        dnf install -y socat || true
    else
        echo "无法安装 socat，请手动安装该依赖。"
        exit 1
    fi
fi


# === 准备列出本机可用公网IP ===
# 方法1: 用 ip 命令列举全局地址，然后过滤掉本地/链路地址
#        只做一个简单的 grep "global" 示例，如果想更准确，可做更多正则判断
ip_list=()
while IFS= read -r line; do
    ip_list+=("$line")
done < <(ip -o addr show scope global | awk '{print $4}' | cut -d/ -f1)

# 如果没检测到，就尝试 curl ifconfig.me 作为默认
if [ ${#ip_list[@]} -eq 0 ]; then
    fallback_ip=$(curl -s ifconfig.me || true)
    if [ -n "$fallback_ip" ]; then
        ip_list+=("$fallback_ip")
    fi
fi

echo "检测到的公网IP列表："
idx=1
for ip in "${ip_list[@]}"; do
    echo "  $idx) $ip"
    ((idx++))
done
echo "  0)  使用以上列表外的自定义IP"

read -p "请选择IP序号（默认1）:" choice
choice="${choice:-1}"

if [ "$choice" == "0" ]; then
    read -p "请输入自定义IP: " custom_ip
    public_ip="$custom_ip"
else
    # 如果用户输入超范围，则用默认1
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#ip_list[@]}" ] 2>/dev/null; then
        choice=1
    fi
    public_ip="${ip_list[$((choice-1))]}"
fi

echo "使用 IP: $public_ip"

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

# 检查 80 端口占用
port_in_use=$(lsof -i:80 -t || true)
if [ -n "$port_in_use" ]; then
    echo "检测到80端口被以下进程占用："
    lsof -i:80
    read -p "是否终止这些进程以便申请证书? (y/n): " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        for pid in $port_in_use; do
            kill -9 "$pid" && echo "已终止进程PID: $pid"
        done
        sleep 2
    else
        echo "无法使用80端口，申请证书可能失败。"
        exit 1
    fi
fi

# 调用 acme.sh --standalone 申请
# 注意要确保此时外网 dig $full_domain 能解析到 $public_ip 且80端口可访问到此机
echo "开始申请证书..."

# 尝试使用 Let's Encrypt 申请证书
acme.sh --issue -d "$full_domain" --standalone --force --server "https://acme-v02.api.letsencrypt.org/directory"


if [ $? -eq 0 ]; then
    echo "证书申请成功。acme.sh 默认会自动续期。"
else
    # 如果 Let's Encrypt 失败，切换到 默认
    echo "Let's Encrypt 证书申请失败，正在尝试使用 ZeroSSL ..."
    acme.sh --issue -d "$full_domain" --standalone --force --server "https://acme.zerossl.com/v2/DV90"

    if [ $? -eq 0 ]; then
        echo "使用 ZeroSSL 成功申请证书。"
    else
        echo "证书申请失败。请检查防火墙、DNS解析、80端口等。"
        exit 1
    fi
fi

# 获取证书列表
acme.sh --list | grep "$full_domain"

# 若需安装证书到系统路径，可手动执行：
# acme.sh --install-cert -d "$full_domain" \
#   --key-file /etc/ssl/${full_domain}.key \
#   --fullchain-file /etc/ssl/${full_domain}.crt

# 在证书申请成功后，添加以下代码将证书安装到指定目录
INSTALL_CERT_PATH="/root/cert/${full_domain}"
mkdir -p "$INSTALL_CERT_PATH"

# 确定证书存放的目录
CERT_DIR="/root/.acme.sh/${full_domain}_ecc"

# 将证书复制到目标目录
cp "${CERT_DIR}/fullchain.cer" "${INSTALL_CERT_PATH}/fullchain.pem"
cp "${CERT_DIR}/${full_domain}.key" "${INSTALL_CERT_PATH}/privkey.pem"

echo "证书已安装到: $INSTALL_CERT_PATH"
echo "证书文件: ${INSTALL_CERT_PATH}/fullchain.pem"
echo "私钥文件: ${INSTALL_CERT_PATH}/privkey.pem"

# 设置证书权限
chmod 644 "${INSTALL_CERT_PATH}/fullchain.pem"
chmod 644 "${INSTALL_CERT_PATH}/privkey.pem"

echo "证书安装完成。"
echo "手动删除证书: rm -rf ${INSTALL_CERT_PATH}"
echo "手动删除证书: rm -rf ${CERT_DIR}"
