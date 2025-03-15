#! /bin/bash



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