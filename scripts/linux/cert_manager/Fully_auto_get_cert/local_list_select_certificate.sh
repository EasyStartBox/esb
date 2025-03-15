#!/bin/bash
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
