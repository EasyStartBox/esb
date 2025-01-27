#!/usr/bin/env bash

########################################
# 1. 颜色与变量初始化
########################################

# 定义颜色变量
gl_orange="\033[1;33m"  # 橙色（通常用黄色近似表示）
gl_reset="\033[0m"      # 重置颜色
gl_kjlan="\033[1;36m"   # 青色（自定义）
gl_huang="\033[1;33m"   # 黄色
gl_bai="\033[1;37m"     # 白色

# 临时文件存储动态信息
SHARED_FILE="/tmp/system_info.txt"
> "$SHARED_FILE"

########################################
# 2. 菜单数据
########################################

left_menu=(
    "a3. 系统信息查询"
    "2. 系统更新"
    "333. 系统清理"
    "e. Docker管理"
    "5. 脚本更新"
)

right_menu=(
    "1. 网络设置"
    "b. 资源监控"
    "c. 安全检查"
    "d. 服务管理"
    "93. 数据备份"
)

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

# 默认焦点
current_row=0
current_col=0

# **重要：鼠标行偏移**  
#  你可以把它理解为“脚本中第1个菜单行”在终端坐标中的位置。  
#  如果你发现实际点击行和选中菜单不一致，就改这个值：  
#  往往你在 draw_menu 里用 tput cup 5 0 来绘制菜单的第一行，就尝试 OFFSET=5。  
#  若结果还是偏移，你可改为4或6等，直到对齐。
MOUSE_MENU_OFFSET=6

########################################
# 3. 功能函数
########################################

linux_ps() {
    clear
    echo "系统信息展示"
}

linux_update() {
    clear
    echo "系统更新中..."
}

linux_clean() {
    clear
    echo "系统清理中..."
}

linux_docker() {
    clear
    echo "Docker 管理中..."
}

network_config() {
    clear
    echo "网络设置..."
}

resource_monitor() {
    clear
    echo "资源监控中..."
}

security_check() {
    clear
    echo "安全检查中..."
}

service_management() {
    clear
    echo "服务管理中..."
}

data_backup() {
    clear
    echo "数据备份中..."
}

########################################
# 4. 鼠标支持等
########################################

enable_mouse() {
    # 1000h: 在xterm等终端中启用基本的鼠标点击追踪(按钮按下释放)
    printf '\e[?1000h'
}

disable_mouse() {
    printf '\e[?1000l'
}

# 修正：根据 MOUSE_MENU_OFFSET 调整鼠标点击行  
#  如果点击时对应的 menu_row 比预期少1或多1，改 MOUSE_MENU_OFFSET 即可
# parse_mouse_event() {
#     local data="$1"
#     local -i button=$(( $(printf '%d' "'${data:0:1}") - 32 ))
#     local -i mouse_col=$(( $(printf '%d' "'${data:1:1}") - 32 ))
#     local -i mouse_row=$(( $(printf '%d' "'${data:2:1}") - 32 ))

#     # 仅处理左键按下 button=0 (有的终端下 button=32 表示释放, 需测试)
#     if (( button == 0 )); then
#         # 判断鼠标是否落在菜单行范围
#         # left_menu: 行 [MOUSE_MENU_OFFSET .. MOUSE_MENU_OFFSET + len(left_menu)-1]
#         # right_menu: 行同样范围，但 col >= 20
#         if (( mouse_row >= MOUSE_MENU_OFFSET && mouse_row < MOUSE_MENU_OFFSET + ${#left_menu[@]} )); then
#             local new_row=$((mouse_row - MOUSE_MENU_OFFSET))
#             local new_col
#             if (( mouse_col < 20 )); then
#                 new_col=0  # 左栏
#             elif (( mouse_col < 40 )); then
#                 new_col=1  # 右栏
#             else
#                 return  # 超出右栏可点击区域
#             fi
#             # 更新焦点
#             local old_row=$current_row
#             local old_col=$current_col
#             current_row=$new_row
#             current_col=$new_col
#             update_option "$old_row" "$old_col"
#             update_option "$current_row" "$current_col"
#         fi
#     fi
# }

parse_mouse_event() {
    local data="$1"
    local -i button=$(( $(printf '%d' "'${data:0:1}") - 32 ))
    local -i mouse_col=$(( $(printf '%d' "'${data:1:1}") - 32 ))
    local -i mouse_row=$(( $(printf '%d' "'${data:2:1}") - 32 ))

    # 仅处理左键按下 button=0
    if (( button == 0 )); then
        # 判断鼠标是否落在菜单行范围
        if (( mouse_row >= MOUSE_MENU_OFFSET && mouse_row < MOUSE_MENU_OFFSET + ${#left_menu[@]} )); then
            local new_row=$((mouse_row - MOUSE_MENU_OFFSET))
            local new_col
            if (( mouse_col < 20 )); then
                new_col=0  # 左栏
            elif (( mouse_col < 40 )); then
                new_col=1  # 右栏
            else
                return  # 超出右栏可点击区域
            fi
            # 更新焦点
            local old_row=$current_row
            local old_col=$current_col
            current_row=$new_row
            current_col=$new_col
            update_option "$old_row" "$old_col"
            update_option "$current_row" "$current_col"
        fi
    fi
}



########################################
# 5. 绘制与更新
########################################

draw_menu() {
    tput clear
    tput cup 1 0
    echo -e "=======超级菜单======="

    # 动态信息区域（2~4行）
    tput cup 2 0; echo -e "${gl_orange}CPU占用: 加载中...${gl_reset}"
    tput cup 3 0; echo -e "${gl_orange}内存占用: 加载中...${gl_reset}"
    tput cup 4 0; echo -e "${gl_orange}网络流量: 加载中...${gl_reset}"

    # 绘制左侧菜单(从第5行开始)
    for i in "${!left_menu[@]}"; do
        tput cup $((5 + i)) 0
        if [ "$i" -eq "$current_row" ] && [ "$current_col" -eq 0 ]; then
            echo -e "\033[1;32m> ${left_menu[$i]} \033[0m"
        else
            echo -e "  ${left_menu[$i]}"
        fi
    done

    # 绘制右侧菜单(同样从第5行开始, 列=20)
    for i in "${!right_menu[@]}"; do
        tput cup $((5 + i)) 20
        if [ "$i" -eq "$current_row" ] && [ "$current_col" -eq 1 ]; then
            echo -e "\033[1;32m> ${right_menu[$i]} \033[0m"
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

update_option() {
    local row_idx="$1"
    local col_idx="$2"
    local screen_row=$((5 + row_idx))
    local screen_col=$((col_idx * 20))

    tput cup "$screen_row" "$screen_col"
    if [ "$row_idx" -eq "$current_row" ] && [ "$col_idx" -eq "$current_col" ]; then
        if [ "$col_idx" -eq 0 ]; then
            echo -e "\033[1;32m> ${left_menu[$row_idx]} \033[0m"
        else
            echo -e "\033[1;32m> ${right_menu[$row_idx]} \033[0m"
        fi
    else
        if [ "$col_idx" -eq 0 ]; then
            echo -e "  ${left_menu[$row_idx]}"
        else
            echo -e "  ${right_menu[$row_idx]}"
        fi
    fi
}

########################################
# 6. 动态信息刷新子进程
########################################

update_dynamic_info() {
    while true; do
        local cpu_usage=$(top -bn1 | grep 'Cpu(s)' | awk '{print $2 + $4}')
        local memory_info=$(free -m | awk 'NR==2{printf "%s/%s MB", $3, $2}')
        # 如果系统没有ifstat，可以改成其他命令
        local net_info=$(ifstat -q 1 1 2>/dev/null | awk 'NR==3{printf "入站: %s KB/s 出站: %s KB/s", $1, $2}')

        {
            echo "CPU占用: $cpu_usage%"
            echo "内存占用: $memory_info"
            if [[ -z "$net_info" ]]; then
                echo "网络流量: --"
            else
                echo "网络流量: $net_info"
            fi
        } > "$SHARED_FILE"
        sleep 1
    done
}

display_dynamic_info() {
    while true; do
        if [[ -f "$SHARED_FILE" ]]; then
            cpu=$(sed -n '1p' "$SHARED_FILE")
            memory=$(sed -n '2p' "$SHARED_FILE")
            net=$(sed -n '3p' "$SHARED_FILE")
        else
            cpu="CPU占用: 加载中..."
            memory="内存占用: 加载中..."
            net="网络流量: 加载中..."
        fi

        tput cup 2 0; echo -e "${gl_orange}${cpu}            ${gl_reset}"
        tput cup 3 0; echo -e "${gl_orange}${memory}               ${gl_reset}"
        tput cup 4 0; echo -e "${gl_orange}${net}               ${gl_reset}"
        sleep 1
    done
}

########################################
# 7. 主循环 + 解决你提到的问题
########################################

# 清理函数
cleanup() {
    rm -f "$SHARED_FILE"
    kill "$DYNAMIC_PID" 2>/dev/null
    kill "$DISPLAY_PID" 2>/dev/null
    disable_mouse
    tput cnorm
    stty sane
    clear
    exit
}
trap cleanup EXIT

# 启动子进程
update_dynamic_info &
DYNAMIC_PID=$!
display_dynamic_info &
DISPLAY_PID=$!

# 绘制菜单并隐藏光标
tput civis
draw_menu

# 启用鼠标捕获
enable_mouse

# 设置终端为原始模式
stty raw -echo

# 用于字母/数字多字符输入的缓冲
input_buffer=""
last_input_time=0

while true; do
    # 读取1字节
    if ! IFS= read -rsn1 -t 0.1 input; then
        # 如果缓冲区里有内容并且超时 0.5秒，就解析
        if [ -n "$input_buffer" ]; then
            now=$(date +%s.%N)
            delta=$(awk -v now="$now" -v last="$last_input_time" 'BEGIN{print now - last}')
            if (( $(awk 'BEGIN{print('"$delta"' > 0.5)}') )); then
                # 超过0.5秒没有新输入 -> 解析缓冲
                parse_buffer="$input_buffer"
                input_buffer=""

                old_row=$current_row
                found=false

                # 检查左菜单
                for i in "${!left_menu[@]}"; do
                    if [[ "${left_menu[$i]}" == "$parse_buffer"* ]]; then
                        if [ "$current_col" -ne 0 ]; then
                            current_col=0
                            update_option "$old_row" 1
                        fi
                        current_row=$i
                        found=true
                        break
                    fi
                done
                # 如果未找到，再查右菜单
                if [ "$found" = false ]; then
                    for i in "${!right_menu[@]}"; do
                        if [[ "${right_menu[$i]}" == "$parse_buffer"* ]]; then
                            if [ "$current_col" -ne 1 ]; then
                                current_col=1
                                update_option "$old_row" 0
                            fi
                            current_row=$i
                            found=true
                            break
                        fi
                    done
                fi

                if [ "$found" = true ]; then
                    update_option "$old_row" "$current_col"
                    update_option "$current_row" "$current_col"
                else
                    # 未找到匹配项
                    tput cup $((10 + ${#left_menu[@]})) 0
                    echo -e "\n\033[1;31m未找到匹配项 [${parse_buffer}]！\033[0m"
                    sleep 1
                    draw_menu
                fi
            fi
        fi
        continue
    fi

    case "$input" in
        $'\x1b')  # 方向键或鼠标
            if IFS= read -rsn1 -t 0.01 nextchar; then
                if [[ "$nextchar" == "[" ]]; then
                    if IFS= read -rsn1 -t 0.01 thirdchar; then
                        case "$thirdchar" in
                            "A")  # 上
                                old_row=$current_row
                                ((current_row--))
                                if [ "$current_row" -lt 0 ]; then
                                    current_row=$(( ${#left_menu[@]} - 1 ))
                                fi
                                update_option "$old_row" "$current_col"
                                update_option "$current_row" "$current_col"
                                ;;
                            "B")  # 下
                                old_row=$current_row
                                ((current_row++))
                                if [ "$current_row" -ge "${#left_menu[@]}" ]; then
                                    current_row=0
                                fi
                                update_option "$old_row" "$current_col"
                                update_option "$current_row" "$current_col"
                                ;;
                            "C")  # 右
                                current_col=1
                                update_option "$current_row" 0
                                update_option "$current_row" "$current_col"
                                ;;
                            "D")  # 左
                                current_col=0
                                update_option "$current_row" 1
                                update_option "$current_row" "$current_col"
                                ;;
                            "M")  # 鼠标事件
                                if IFS= read -rsn3 -t 0.01 mouse_data; then
                                    parse_mouse_event "$mouse_data"
                                fi
                                ;;
                            *)  # 其他
                                :
                                ;;
                        esac
                    fi
                else
                    # 可能是单独按下ESC
                    # 此处不做特殊处理
                    :
                fi
            fi
            ;;
        # 将 \r 和 \n 都视为 Enter
        $'\r'|$'\n')
            # **合并处理**: 先尝试丢弃后续的 \n 或 \r，避免 “双击”问题
            if IFS= read -rsn1 -t 0.01 next_enter; then
                if [[ "$next_enter" != $'\r' && "$next_enter" != $'\n' ]]; then
                    # 若读到的并非换行符，则可能是其他按键，需要回退处理
                    # 但是纯 Bash 不容易“退还”这个字符，这里简单丢弃
                    # 或者可以放到缓冲 input_buffer 里，但场景复杂，这里就忽略
                    :
                fi
            fi

            # 解析尚未处理的缓冲
            if [ -n "$input_buffer" ]; then
                parse_buffer="$input_buffer"
                input_buffer=""
                old_row=$current_row
                found=false

                for i in "${!left_menu[@]}"; do
                    if [[ "${left_menu[$i]}" == "$parse_buffer"* ]]; then
                        if [ "$current_col" -ne 0 ]; then
                            current_col=0
                            update_option "$old_row" 1
                        fi
                        current_row=$i
                        found=true
                        break
                    fi
                done
                if [ "$found" = false ]; then
                    for i in "${!right_menu[@]}"; do
                        if [[ "${right_menu[$i]}" == "$parse_buffer"* ]]; then
                            if [ "$current_col" -ne 1 ]; then
                                current_col=1
                                update_option "$old_row" 0
                            fi
                            current_row=$i
                            found=true
                            break
                        fi
                    done
                fi
                if [ "$found" = true ]; then
                    update_option "$old_row" "$current_col"
                    update_option "$current_row" "$current_col"
                fi
            fi

            # 杀掉动态进程并执行对应操作
            kill "$DYNAMIC_PID" 2>/dev/null
            kill "$DISPLAY_PID" 2>/dev/null

            if [ "$current_col" -eq 0 ]; then
                eval "${actions_left[$current_row]}"
            else
                eval "${actions_right[$current_row]}"
            fi

            echo -e "\n\033[1;32m操作完成，请按任意键返回菜单...\033[0m"
            IFS= read -rsn1  # 等待任意键

            # 重新启动
            update_dynamic_info &
            DYNAMIC_PID=$!
            display_dynamic_info &
            DISPLAY_PID=$!

            draw_menu
            ;;
        *)
            # 如果是字母或数字 -> 加入缓冲
            # 否则提示无效输入
            if [[ "$input" =~ [0-9a-zA-Z] ]]; then
                now=$(date +%s.%N)
                delta=$(awk -v now="$now" -v last="$last_input_time" 'BEGIN{print now - last}')
                if (( $(awk 'BEGIN{print('"$delta"' < 0.5)}') )); then
                    # 0.5秒内再次输入 -> 拼接
                    input_buffer+="$input"
                else
                    # 超过 0.5秒 -> 先结束旧缓冲(这里直接丢弃旧的,或自行解析)
                    input_buffer="$input"
                fi
                last_input_time="$now"
            else
                echo -e "\n\033[1;31m无效的输入: [$input]\033[0m"
                sleep 1
                draw_menu
            fi
            ;;
    esac
done



