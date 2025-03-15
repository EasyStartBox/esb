#!/bin/bash

# 检查端口占用并清理
check_and_clear_port() {
    local port=$1
    # 检查端口占用
    port_in_use=$(lsof -i:$port -t || true)
    restart_services=()        # 记录需要重启的系统服务
    docker_containers=""       # 记录停止的Docker容器
    manual_killed=()           # 记录手动终止的进程信息

    if [ -n "$port_in_use" ]; then
        echo "检测到$port端口被以下进程占用："
        lsof -i:$port

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
            docker_containers=$(docker ps -q --filter "publish=$port")
            if [ -n "$docker_containers" ]; then
                echo "检测到 Docker 容器，正在停止..."
                docker stop $docker_containers
                restart_services+=("docker")
            fi
        fi

        # 再次检查端口占用
        port_in_use=$(lsof -i:$port -t 2>/dev/null | xargs || true)
        if [ -n "$port_in_use" ]; then
            echo "$port端口仍被以下进程占用："
            lsof -i:$port

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
                echo "无法使用$port端口，申请证书可能失败。"
                return 1
            fi
        fi
    fi
    return 0
}

# 恢复自动停止的服务
restore_services() {
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
}
