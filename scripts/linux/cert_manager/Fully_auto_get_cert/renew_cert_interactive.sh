#! /bin/bash

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

