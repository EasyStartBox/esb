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
# Configuration
# DNS_API_SERVER="${DNS_API_SERVER:-localhost}"
# DNS_API_PORT="${DNS_API_PORT:-5050}"

DNS_API_SERVER="178.157.56.29"
DNS_API_PORT=5050

CONFIG_FILE=".dns_api_config"


# Load configuration if exists
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi


# 你在 Bind 配置中管理的子域后缀
DOMAIN_SUFFIX="ns.washvoid.com"

source ./install_depend.sh
source ./port_manager.sh
source ./dns_operations.sh
source ./local_list_select_certificate.sh
source ./renew_cert_interactive.sh
source ./revoke_cert_interactive.sh
source ./interactive_wizard.sh


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


# 申请测试证书 (Let's Encrypt 测试服务器)
issue_test_cert() {
    local domain=$1
    local is_test=$2 # 是否为测试证书 通过true或false来判断
    local target_path="/root/cert/${domain}"
    
    echo "申请测试证书中..."
    
        # 首先添加域名记录(如果使用命令行参数) "$USING_CLI_PARAMS" = true是使用命令行参数然后自动解析ip
    if [ "$USING_CLI_PARAMS" = true ]; then
        # 检测公网IP
        get_ips


        
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



# 执行主函数
main "$@"