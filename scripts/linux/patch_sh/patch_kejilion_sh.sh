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
    # echo "清理临时文件和子进程..."
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

kejilion_sh() { 
    # 最小高度要求
    local min_height=33  # 最小高度需求，包含菜单和底部提示区域

    # 初始化 end_line
    local end_line=0

    # 检查终端高度
    check_terminal_height() {
        local current_height=$(tput lines)
        if [ "$current_height" -lt "$min_height" ]; then
            tput clear
            echo -e "\033[1;31m当前终端高度不足！\033[0m"
            echo -e "请调整终端窗口高度至少为 \033[1;32m$min_height\033[0m 行。"
            echo -e "当前终端高度：\033[1;33m$current_height\033[0m 行。"
            echo -e "请调整后重新运行脚本。"
            exit 1
        fi
    }

    # 检查终端高度
    check_terminal_height

    # 初始化选项
    options=(
        "1. 系统信息查询"
        "2. 系统更新"
        "3. 系统清理"
        "4. 基础工具 ▶"
        "5. BBR管理 ▶"
        "6. Docker管理 ▶"
        "7. WARP管理 ▶"
        "8. 测试脚本合集 ▶"
        "9. 甲骨文云脚本合集 ▶"
        "a. LDNMP建站 ▶"
        "y. 应用市场 ▶"
        "w. 我的工作区 ▶"
        "x. 系统工具 ▶"
        "f. 服务器集群控制 ▶"
        "g. 广告专栏"
        "p. 幻兽帕鲁开服脚本 ▶"
        "u. 脚本更新"
        "0. 退出脚本"
    )
    actions=(
        "linux_ps"
        "clear ; send_stats '系统更新' ; linux_update"
        "clear ; send_stats '系统清理' ; linux_clean"
        "linux_tools"
        "linux_bbr"
        "linux_docker"
        "clear ; send_stats 'warp管理' ; install wget; wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh ; bash menu.sh [option] [lisence/url/token]"
        "linux_test"
        "linux_Oracle"
        "linux_ldnmp"
        "linux_panel"
        "linux_work"
        "linux_Settings"
        "linux_cluster"
        "kejilion_Affiliates"
        "send_stats '幻兽帕鲁开服脚本' ; cd ~; curl -sS -O ${gh_proxy}https://raw.githubusercontent.com/kejilion/sh/main/palworld.sh ; chmod +x palworld.sh ; ./palworld.sh"
        "kejilion_update"
        "exit"  # 修改这里，从 "clear ; exit" 到 "exit"
    )

    current_selection=0  # 当前选中的选项索引

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

    # 绘制标题部分（固定不动）
    draw_title() {
        tput clear

        # 固定不变的信息
        local disk_info=$(df -h / | awk 'NR==2{printf "%s/%s", $3, $2}')
        local ipv4=$(curl -s ipv4.ip.sb)
        local ipv6=$(curl -s --max-time 1 ipv6.ip.sb)

        # 主显示界面，从第0行开始绘制标题
        tput cup 5 0
        echo -e "硬盘占用: ${gl_orange}$disk_info${gl_reset}"

        # 合并 IPv4 和 IPv6 行，减少行数
        tput cup 6 0
        echo -e "网络: IPv4: ${gl_orange}$ipv4${gl_reset} | IPv6: ${gl_orange}$ipv6${gl_reset}"

        # 分隔线，保持菜单与标题之间的间距
        tput cup 7 0



        echo -e "${gl_kjlan}输入${gl_huang}kk${gl_kjlan}可快启动${gl_bai}   v$sh_v"
        
        

        # 额外间距留给菜单（3 行以上可调整）
        tput cup 8 0
        echo -e "${gl_kjlan}------------------------${gl_bai}"




    }

    # 绘制底部虚线和提示文本
    draw_footer() {
        local footer_text="${gl_kjlan}------------------------${gl_bai}"
        local hint_color="${gl_kjlan}"  # 与虚线颜色一致

        # 将底部提示绘制在菜单选项之后
        local footer_start_line=$((11 + ${#options[@]}))  # 菜单从第11行开始
        tput cup "$footer_start_line" 0  # 定位到菜单最后一个选项的下一行
        echo -e "$footer_text"

        # 提示文本分为三行，使用与虚线相同的颜色
        tput cup $((footer_start_line + 1)) 0  # 定位到虚线下一行
        echo -e "${hint_color}使用上下方向键选择${gl_bai}"
        tput cup $((footer_start_line + 2)) 0  # 定位到下一行
        echo -e "${hint_color}或输入数字和字母选择${gl_bai}"
        tput cup $((footer_start_line + 3)) 0  # 定位到再下一行
        echo -e "${hint_color}按 Enter 回车确认选择${gl_bai}"

        # 设置 end_line
        end_line=$((footer_start_line + 3))
    }

    # 绘制选项部分
    draw_menu() {
        for i in "${!options[@]}"; do
            tput cup $((11 + $i)) 0  # 从第11行开始绘制菜单
            if [ "$i" -eq "$current_selection" ]; then
                echo -e "\033[1;32m> ${options[$i]} \033[0m"  # 高亮显示
            else
                option="${options[$i]}"
                # 仅检查 "a. LDNMP建站 ▶"
                if [[ "$option" == "a."* ]]; then
                    # 将 "a" 部分显示为橙色
                    echo -e "  ${gl_orange}a${gl_reset}.${option#a.}"
                else
                    echo -e "  ${options[$i]}"
                fi
            fi
        done
        draw_footer  # 绘制底部虚线和提示文本
    }

    # 更新选项显示
    update_option() {
        tput cup $((11 + $1)) 0  # 从第11行开始绘制菜单
        if [ "$1" -eq "$current_selection" ]; then
            echo -e "\033[1;32m> ${options[$1]} \033[0m"  # 高亮显示
        else
            option="${options[$1]}"
            # 仅检查 "a. LDNMP建站 ▶"
            if [[ "$option" == "a."* ]]; then
                # 将 "a" 部分显示为橙色
                echo -e "  ${gl_orange}a${gl_reset}.${option#a.}"
            else
                echo -e "  ${options[$1]}"
            fi
        fi
    }

    # 主菜单绘制函数
    draw_main_menu() {
        draw_title
        draw_menu
    }

    # 确保在退出时恢复光标并移动到菜单下方（已在 cleanup 中定义）

    # 主逻辑
    tput civis  # 隐藏光标
    draw_main_menu
    while true; do
        read -rsn1 input  # 读取用户输入

        case "$input" in
            $'\x1b')  # 方向键输入
                read -rsn2 -t 0.1 input
                case "$input" in
                    "[A")  # 上方向键
                        old_selection=$current_selection
                        ((current_selection--))
                        if [ "$current_selection" -lt 0 ]; then
                            current_selection=$((${#options[@]} - 1))
                        fi
                        update_option "$old_selection"
                        update_option "$current_selection"
                        ;;
                    "[B")  # 下方向键
                        old_selection=$current_selection
                        ((current_selection++))
                        if [ "$current_selection" -ge "${#options[@]}" ]; then
                            current_selection=0
                        fi
                        update_option "$old_selection"
                        update_option "$current_selection"
                        ;;
                esac
                ;;
            "")  # Enter 键
                # 终止动态信息子进程
                kill "$DYNAMIC_PID" 2>/dev/null
                kill "$DISPLAY_PID" 2>/dev/null

                # 执行对应功能
                eval "${actions[$current_selection]}"

                # 等待用户按任意键继续
                echo -e "\n\033[1;32m操作完成，请按任意键返回菜单...\033[0m"
                read -rsn1  # 等待按任意键

                # 重新启动动态信息子进程
                update_dynamic_info &
                DYNAMIC_PID=$!

                display_dynamic_info &
                DISPLAY_PID=$!

                # 重新绘制菜单
                draw_title
                draw_menu
                ;;
            [0-9a-z])  # 数字或字母选择
                for i in "${!options[@]}"; do
                    if [[ "${options[$i]}" == "$input"* ]]; then
                        old_selection=$current_selection
                        current_selection=$i
                        update_option "$old_selection"
                        update_option "$current_selection"
                        break
                    fi
                done
                ;;
            *)
                echo -e "\n\033[1;31m无效的输入！\033[0m"
                sleep 1
                draw_title
                draw_menu
                ;;
        esac
    done
}
