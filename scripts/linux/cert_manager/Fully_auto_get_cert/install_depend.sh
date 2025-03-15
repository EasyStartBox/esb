#!/bin/bash


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