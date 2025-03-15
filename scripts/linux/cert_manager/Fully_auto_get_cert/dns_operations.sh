#!/bin/bash
# 发送 JSON 请求到 DNS API
# add_domain() {
#     local domain=$1
#     local ip=$2
#     local json
#     json=$(jq -n --arg action "add_domain" --arg d "$domain" --arg i "$ip" \
#          '{action:$action, domain:$d, ip:$i}')
#     echo "向DNS服务器($DNS_API_SERVER:$DNS_API_PORT)发送添加请求: $json"
#     resp=$(echo "$json" | nc "$DNS_API_SERVER" "$DNS_API_PORT")
#     echo "服务器响应: $resp"
#     # 检查 status
#     local st msg
#     st=$(echo "$resp" | jq -r '.status' 2>/dev/null || true)
#     msg=$(echo "$resp" | jq -r '.message' 2>/dev/null || true)
#     if [ "$st" != "success" ]; then
#         echo "添加失败: $msg"
#         return 1
#     fi
#     echo "添加成功: $msg"
#     return 0
# }






# dns_client.sh - Enhanced DNS API Client


# CONFIG_FILE="${HOME}/.dns_api_config"


# Helper functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

send_request() {
    local json="$1"
    local timeout="${2:-5}"
    
    log "向DNS服务器($DNS_API_SERVER:$DNS_API_PORT)发送请求:"
    log "$json"
    
    # Use timeout for connection issues
    resp=$(echo "$json" | timeout "$timeout" nc "$DNS_API_SERVER" "$DNS_API_PORT")
    
    if [[ $? -ne 0 ]]; then
        log "错误: 连接服务器失败或超时"
        return 1
    fi
    
    echo "$resp"
}

# Add domain function (original)
add_domain() {
    local domain="$1"
    local ip="$2"
    
    # Validate inputs
    if [[ -z "$domain" || -z "$ip" ]]; then
        log "错误: 域名和IP都必须提供"
        return 1
    fi
    
    # Validate domain format
    if ! echo "$domain" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$'; then
        log "错误: 无效的域名格式"
        return 1
    fi
    
    # Validate IP format
    if [[ "$ip" == *":"* ]]; then
        # IPv6 validation (basic)
        if ! echo "$ip" | grep -qE '^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|^::$|^::1$|^::ffff:[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
            log "错误: 无效的IPv6格式"
            return 1
        fi
    else
        # IPv4 validation
        if ! echo "$ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
            log "错误: 无效的IPv4格式"
            return 1
        fi
    fi
    
    local json
    json=$(jq -n --arg action "add_domain" --arg d "$domain" --arg i "$ip" \
        '{action:$action, domain:$d, ip:$i}')
    
    resp=$(send_request "$json")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    log "服务器响应: $resp"
    
    # 检查 status
    local st msg
    st=$(echo "$resp" | jq -r '.status' 2>/dev/null || echo "error")
    msg=$(echo "$resp" | jq -r '.message' 2>/dev/null || echo "无法解析响应")
    
    if [[ "$st" != "success" ]]; then
        log "添加失败: $msg"
        return 1
    fi
    
    log "添加成功: $msg"
    return 0
}

# New function: delete domain
delete_domain() {
    local domain="$1"
    
    # Validate inputs
    if [[ -z "$domain" ]]; then
        log "错误: 必须提供域名"
        return 1
    fi
    
    local json
    json=$(jq -n --arg action "delete_domain" --arg d "$domain" \
        '{action:$action, domain:$d}')
    
    resp=$(send_request "$json")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    log "服务器响应: $resp"
    
    # 检查 status
    local st msg
    st=$(echo "$resp" | jq -r '.status' 2>/dev/null || echo "error")
    msg=$(echo "$resp" | jq -r '.message' 2>/dev/null || echo "无法解析响应")
    
    if [[ "$st" != "success" ]]; then
        log "删除失败: $msg"
        return 1
    fi
    
    log "删除成功: $msg"
    return 0
}

# New function: update domain
update_domain() {
    local domain="$1"
    local ip="$2"
    
    # Validate inputs
    if [[ -z "$domain" || -z "$ip" ]]; then
        log "错误: 域名和IP都必须提供"
        return 1
    fi
    
    local json
    json=$(jq -n --arg action "update_domain" --arg d "$domain" --arg i "$ip" \
        '{action:$action, domain:$d, ip:$i}')
    
    resp=$(send_request "$json")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    log "服务器响应: $resp"
    
    # 检查 status
    local st msg
    st=$(echo "$resp" | jq -r '.status' 2>/dev/null || echo "error")
    msg=$(echo "$resp" | jq -r '.message' 2>/dev/null || echo "无法解析响应")
    
    if [[ "$st" != "success" ]]; then
        log "更新失败: $msg"
        return 1
    fi
    
    log "更新成功: $msg"
    return 0
}

# New function: list domains
list_domains() {
    local json
    json=$(jq -n --arg action "list_domains" '{action:$action}')
    
    resp=$(send_request "$json")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    log "服务器响应: $resp"
    
    # 检查 status
    local st
    st=$(echo "$resp" | jq -r '.status' 2>/dev/null || echo "error")
    
    if [[ "$st" != "success" ]]; then
        local msg
        msg=$(echo "$resp" | jq -r '.message' 2>/dev/null || echo "无法解析响应")
        log "获取域名列表失败: $msg"
        return 1
    fi
    
    # 显示域名列表
    echo "域名列表:"
    echo "$resp" | jq -r '.domains[] | "\(.domain) [\(.type)] -> \(.ip)"' 2>/dev/null
    return 0
}

# Config management
set_server() {
    local server="$1"
    local port="$2"
    
    if [[ -z "$server" ]]; then
        log "错误: 请提供服务器地址"
        return 1
    fi
    
    if [[ -z "$port" ]]; then
        port="5050"
    fi
    
    # Update vars
    DNS_API_SERVER="$server"
    DNS_API_PORT="$port"
    
    # Save to config
    echo "DNS_API_SERVER=\"$server\"" > "$CONFIG_FILE"
    echo "DNS_API_PORT=\"$port\"" >> "$CONFIG_FILE"
    
    log "已设置服务器为 $server:$port"
    return 0
}

# Main command handler
main() {
    case "$1" in
        add)
            if [[ $# -lt 3 ]]; then
                echo "用法: $0 add <域名> <IP地址>"
                return 1
            fi
            add_domain "$2" "$3"
            ;;
        delete|del|remove|rm)
            if [[ $# -lt 2 ]]; then
                echo "用法: $0 delete <域名>"
                return 1
            fi
            delete_domain "$2"
            ;;
        update|up)
            if [[ $# -lt 3 ]]; then
                echo "用法: $0 update <域名> <新IP地址>"
                return 1
            fi
            update_domain "$2" "$3"
            ;;
        list|ls)
            list_domains
            ;;
        server)
            if [[ $# -lt 2 ]]; then
                echo "用法: $0 server <服务器地址> [端口]"
                return 1
            fi
            set_server "$2" "$3"
            ;;
        help|-h|--help)
            echo "DNS API 客户端用法:"
            echo "  $0 add <域名> <IP地址>     - 添加新域名记录"
            echo "  $0 delete <域名>           - 删除域名记录"
            echo "  $0 update <域名> <IP地址>  - 更新域名记录"
            echo "  $0 list                   - 列出所有域名记录"
            echo "  $0 server <地址> [端口]    - 设置服务器地址和端口"
            echo "  $0 help                   - 显示帮助信息"
            ;;
        *)
            echo "未知命令: $1"
            echo "运行 '$0 help' 获取命令列表"
            return 1
            ;;
    esac
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 1 ]]; then
        echo "错误: 请提供命令"
        echo "运行 '$(basename "$0") help' 获取帮助"
        exit 1
    fi
    
    main "$@"
fi

