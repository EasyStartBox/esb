#!/bin/bash


# 定义"a"颜色变量
gl_orange="\033[1;33m"  # 橙色（通常用黄色近似表示）
gl_reset="\033[0m"      # 重置颜色




kejilion_sh() { 
    # 最小高度要求
    local min_height=30  # 最小高度需求，包含菜单和底部提示区域

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

    # 绘制标题部分（固定不动）
    draw_title() {
        tput clear
        echo -e "${gl_kjlan}"
        echo "╦╔═╔═╗ ╦╦╦  ╦╔═╗╔╗╔ ╔═╗╦ ╦"
        echo "╠╩╗║╣  ║║║  ║║ ║║║║ ╚═╗╠═╣"
        echo "╩ ╩╚═╝╚╝╩╩═╝╩╚═╝╝╚╝o╚═╝╩ ╩"
        echo -e "科技lion脚本工具箱 v$sh_v"
        echo -e "命令行输入${gl_huang}k${gl_kjlan}可快速启动脚本${gl_bai}"
        echo -e "${gl_kjlan}------------------------${gl_bai}"
    }

    # 绘制底部虚线和提示文本
    draw_footer() {
        local footer_text="${gl_kjlan}------------------------${gl_bai}"
        local hint_color="${gl_kjlan}"  # 与虚线颜色一致
        tput cup $((7 + ${#options[@]})) 0  # 定位到菜单最后一个选项的下一行
        echo -e "$footer_text"

        # 提示文本分为三行，使用与虚线相同的颜色
        tput cup $((8 + ${#options[@]})) 0  # 定位到虚线下一行
        echo -e "${hint_color}使用上下方向键选择${gl_bai}"
        tput cup $((9 + ${#options[@]})) 0  # 定位到下一行
        echo -e "${hint_color}或输入数字和字母选择${gl_bai}"
        tput cup $((10 + ${#options[@]})) 0  # 定位到再下一行
        echo -e "${hint_color}按 Enter 回车确认选择${gl_bai}"

        # 设置 end_line
        end_line=$((10 + ${#options[@]}))
    }

    # 修改后的绘制选项部分
    draw_menu() {
        for i in "${!options[@]}"; do
            tput cup $((7 + $i)) 0  # 从第7行开始绘制菜单
            if [ "$i" -eq "$current_selection" ]; then
                echo -e "\033[1;32m> ${options[$i]} \033[0m"  # 高亮显示
            else
                option="${options[$i]}"
                # 仅检查 "a. LDNMP建站 ▶"
                if [[ "$option" == "a."* ]]; then
                    # 将 "a" 部分显示为橙色
                    echo -e "  ${gl_orange}a${gl_reset}.${option#a.}"
                else
                    echo "  ${options[$i]}"
                fi
            fi
        done
        draw_footer  # 绘制底部虚线和提示文本
    }

    # 修改后的更新选项部分
    update_option() {
        tput cup $((7 + $1)) 0
        if [ "$1" -eq "$current_selection" ]; then
            echo -e "\033[1;32m> ${options[$1]} \033[0m"  # 高亮显示
        else
            option="${options[$1]}"
            # 仅检查 "a. LDNMP建站 ▶"
            if [[ "$option" == "a."* ]]; then
                # 将 "a" 部分显示为橙色
                echo -e "  ${gl_orange}a${gl_reset}.${option#a.}"
            else
                echo "  ${options[$1]}"
            fi
        fi
    }

    # 确保在退出时恢复光标并移动到菜单下方
    cleanup() {
        tput cnorm  # 恢复光标
        if [ "$end_line" -gt 0 ]; then
            tput cup $((end_line + 1)) 0  # 移动光标到菜单下方
            echo  # 输出换行符
        else
            tput cup 0 0  # 默认移动到第一行
            echo
        fi
    }

    trap cleanup EXIT

    # 主逻辑
    tput civis  # 隐藏光标
    draw_title
    draw_menu
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
                # 执行对应功能
                eval "${actions[$current_selection]}"

                # 等待用户按任意键继续
                echo -e "\n\033[1;32m操作完成，请按任意键返回菜单...\033[0m"
                read -rsn1  # 等待按任意键

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
                echo "无效的输入！"
                sleep 1
                ;;
        esac
    done
}