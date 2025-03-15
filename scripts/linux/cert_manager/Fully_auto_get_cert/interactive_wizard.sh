#! /bin/bash



# 交互式向导
interactive_wizard() {
    # 选择证书客户端
    #select_client

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