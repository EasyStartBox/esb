#!/bin/bash

# 定义颜色变量
gl_orange="\033[1;33m"  # 橙色（通常用黄色近似表示）
gl_reset="\033[0m"      # 重置颜色
gl_kjlan="\033[1;36m"  # 青色（自定义）
gl_huang="\033[1;33m"  # 黄色
gl_bai="\033[1;37m"    # 白色

# 临时文件存储动态信息
SHARED_FILE="/tmp/system_info.txt"

# 初始化共享文件
> "$SHARED_FILE"

# 定义清理函数
cleanup() {
    # 清理临时文件和子进程...
    rm -f "$SHARED_FILE"
    kill "$DYNAMIC_PID" 2>/dev/null
    kill "$DISPLAY_PID" 2>/dev/null
    tput cnorm  # 恢复光标
    if [ "$end_line" -gt 0 ]; then
        tput cup $((end_line + 1)) 0  # 移动光标到菜单下方
        echo  # 输出换行符
    else
        tput cup 0 0  # 默认移动到第一行
        echo
    fi
    exit
}

trap cleanup EXIT

# 定义菜单项
left_menu=(
    "1. 系统信息查询"
    "2. 系统更新"
    "3. 系统清理"
    "4. Docker管理"
    "5. 脚本更新"
)

right_menu=(
    "a. 网络设置"
    "b. 资源监控"
    "c. 安全检查"
    "d. 服务管理"
    "e. 数据备份"
)

# 对应的操作函数
actions_left=(
    "linux_ps"
    "linux_update"
    "linux_clean"
    "linux_docker"
    "linux_update"
)

actions_right=(
    "network_config"
    "resource_monitor"
    "security_check"
    "service_management"
    "data_backup"
)

# 测试函数
linux_ps() {
    echo "系统信息展示"
}

linux_update() {
    echo "系统更新中..."
}

linux_clean() {
    echo "系统清理中..."
}

linux_docker() {
    echo "Docker 管理中..."
}

network_config() {
    echo "网络设置..."
}

resource_monitor() {
    echo "资源监控中..."
}

security_check() {
    echo "安全检查中..."
}

service_management() {
    echo "服务管理中..."
}

data_backup() {
    echo "数据备份中..."
}

current_row=0  # 当前选中的行
current_col=0  # 当前选中的列

# 动态获取系统信息并写入文件（子进程）
update_dynamic_info() {
    while true; do
        local cpu_usage=$(top -bn1 | grep 'Cpu(s)' | awk '{print $2 + $4}')
        local memory_info=$(free -m | awk 'NR==2{printf "%s/%s MB", $3, $2}')
        local net_info=$(ifstat -q 1 1 | awk 'NR==3{printf "入站: %s KB/s 出站: %s KB/s", $1, $2}')
        
        # 将动态信息写入共享文件
        {
            echo "CPU占用: $cpu_usage%            "
            echo "内存占用: $memory_info    "
            echo "网络流量: $net_info               "
        } > "$SHARED_FILE"
        
        sleep 1
    done
}

# 动态显示信息（后台子进程）
display_dynamic_info() {
    while true; do
        if [[ -f "$SHARED_FILE" ]]; then
            local cpu=$(sed -n '1p' "$SHARED_FILE")
            local memory=$(sed -n '2p' "$SHARED_FILE")
            local net=$(sed -n '3p' "$SHARED_FILE")
        else
            local cpu="CPU占用: 加载中..."
            local memory="内存占用: 加载中..."
            local net="网络流量: 加载中..."
        fi

        # 使用 tput 定位并更新动态信息
        tput cup 1 0
        echo -e "${gl_orange}$cpu${gl_reset}"
        tput cup 2 0
        echo -e "${gl_orange}$memory${gl_reset}"
        tput cup 3 0
        echo -e "${gl_orange}$net${gl_reset}"

        sleep 1
    done
}

# 启动子进程：更新动态信息
update_dynamic_info &
DYNAMIC_PID=$!

# 启动子进程：显示动态信息
display_dynamic_info &
DISPLAY_PID=$!

# 绘制菜单
draw_menu() {
    tput clear

    # 绘制左侧菜单
    for i in "${!left_menu[@]}"; do
        tput cup $((5 + $i)) 0  # 从第5行开始绘制左侧菜单
        if [ "$i" -eq "$current_row" ] && [ "$current_col" -eq 0 ]; then
            echo -e "\033[1;32m> ${left_menu[$i]} \033[0m"  # 高亮显示左列
        else
            echo -e "  ${left_menu[$i]}"
        fi
    done

    # 绘制右侧菜单
    for i in "${!right_menu[@]}"; do
        tput cup $((5 + $i)) 20  # 从第5行开始绘制右侧菜单
        if [ "$i" -eq "$current_row" ] && [ "$current_col" -eq 1 ]; then
            echo -e "\033[1;32m> ${right_menu[$i]} \033[0m"  # 高亮显示右列
        else
            echo -e "  ${right_menu[$i]}"
        fi
    done

    # 底部提示
    tput cup $((5 + ${#left_menu[@]})) 0
    echo -e "${gl_kjlan}------------------------${gl_bai}"
    tput cup $((6 + ${#left_menu[@]})) 0
    echo -e "${gl_kjlan}使用上下方向键选择菜单项${gl_bai}"
    tput cup $((7 + ${#left_menu[@]})) 0
    echo -e "${gl_kjlan}左右方向键切换列${gl_bai}"
    tput cup $((8 + ${#left_menu[@]})) 0
    echo -e "${gl_kjlan}按 Enter 回车确认选择${gl_bai}"
}

# 更新选项显示
update_option() {
    tput cup $((5 + $1)) $(( $2 * 20 ))  # 根据列更新显示位置
    if [ "$1" -eq "$current_row" ] && [ "$2" -eq "$current_col" ]; then
        if [ "$2" -eq 0 ]; then
            echo -e "\033[1;32m> ${left_menu[$1]} \033[0m"  # 高亮显示左列
        else
            echo -e "\033[1;32m> ${right_menu[$1]} \033[0m"  # 高亮显示右列
        fi
    else
        if [ "$2" -eq 0 ]; then
            echo -e "  ${left_menu[$1]}"  # 显示左列
        else
            echo -e "  ${right_menu[$1]}"  # 显示右列
        fi
    fi
}

# 主逻辑
tput civis  # 隐藏光标
draw_menu
while true; do
    read -rsn1 input  # 读取用户输入

    case "$input" in
        $'\x1b')  # 方向键输入
            read -rsn2 -t 0.1 input
            case "$input" in
                "[A")  # 上方向键
                    old_row=$current_row
                    ((current_row--))
                    if [ "$current_row" -lt 0 ]; then
                        current_row=$(( ${#left_menu[@]} - 1 ))
                    fi
                    update_option "$old_row" "$current_col"
                    update_option "$current_row" "$current_col"
                    ;;
                "[B")  # 下方向键
                    old_row=$current_row
                    ((current_row++))
                    if [ "$current_row" -ge "${#left_menu[@]}" ]; then
                        current_row=0
                    fi
                    update_option "$old_row" "$current_col"
                    update_option "$current_row" "$current_col"
                    ;;
                "[C")  # 右方向键
                    current_col=1
                    update_option "$current_row" 0
                    update_option "$current_row" "$current_col"
                    ;;
                "[D")  # 左方向键
                    current_col=0
                    update_option "$current_row" 1
                    update_option "$current_row" "$current_col"
                    ;;
            esac
            ;;
        "")  # Enter 键
            if [ "$current_col" -eq 0 ]; then
                eval "${actions_left[$current_row]}"  # 执行左侧菜单对应的操作
            else
                eval "${actions_right[$current_row]}"  # 执行右侧菜单对应的操作
            fi
            echo -e "\n\033[1;32m操作完成，请按任意键返回菜单...\033[0m"
            read -rsn1  # 等待按任意键

            # 重新启动动态信息子进程
            update_dynamic_info &
            DYNAMIC_PID=$!
            display_dynamic_info &
            DISPLAY_PID=$!

            draw_menu
            ;;
        [0-9a-z])  # 数字或字母选择
            old_row=$current_row
            if [[ "$input" =~ [a-z] ]]; then
                # 字母选择右侧菜单
                if [ "$current_col" -ne 1 ]; then
                    current_col=1
                    update_option "$old_row" 0
                    update_option "$current_row" "$current_col"
                fi
                for i in "${!right_menu[@]}"; do
                    if [[ "${right_menu[$i]}" == "$input"* ]]; then
                        current_row=$i
                        break
                    fi
                done
            else
                # 数字选择左侧菜单
                if [ "$current_col" -ne 0 ]; then
                    current_col=0
                    update_option "$old_row" 1
                    update_option "$current_row" "$current_col"
                fi
                for i in "${!left_menu[@]}"; do
                    if [[ "${left_menu[$i]}" == "$input"* ]]; then
                        current_row=$i
                        break
                    fi
                done
            fi
            update_option "$old_row" "$current_col"
            update_option "$current_row" "$current_col"
            ;;
        *)
            echo -e "\n\033[1;31m无效的输入！\033[0m"
            sleep 1
            draw_menu
            ;;
    esac
done
