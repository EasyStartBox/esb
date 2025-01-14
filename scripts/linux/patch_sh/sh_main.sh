#!/bin/bash

# 把它加入顶部使每次运行都删除它
rm -rf /tmp/patch_sh_update

log_file="/var/log/patch_sh_script.log"

log() {
    local message="$1"
    # 将信息写入日志文件，并且加上时间戳
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$log_file"
}

log "脚本开始执行"

# 假设执行某个命令
echo "Hello, World!"
log "Hello, World! 命令已执行"



# 默认存放目录（如果用户未指定目录）
DEFAULT_DIR="$HOME/.patch_sh"
DOWNLOAD_DIR="${1:-$DEFAULT_DIR}"  # 如果提供参数，则使用参数作为目录；否则使用默认目录。

# === 可选：设置 trap 清理临时文件或中断处理 ===
cleanup() {
    echo "清理临时资源..."
    # 如果有临时文件或目录需要清理，放在这里
}
trap cleanup EXIT

# 创建存放目录
mkdir -p "$DOWNLOAD_DIR"

# 定义 GitHub 代理（如果有）
#gh_proxy="https://ghproxy.com/"  # 根据需要修改


# 定义依赖脚本和配置文件的 URL 和文件名
DEPENDENCIES=(
    "sh_main.sh|https://raw.githubusercontent.com/EasyStartBox/esb/main/scripts/linux/patch_sh/sh_main.sh"
    "kejilion.sh|https://raw.githubusercontent.com/EasyStartBox/esb/main/kejilion/sh/kejilion.sh"
    "k_info.sh|https://raw.githubusercontent.com/washsky/sh-of-kjlion/washsky-develop/scripts/linux/k_info.sh"
    "config.yml|https://raw.githubusercontent.com/EasyStartBox/esb/main/config/patch_sh/config.yml"  # 配置文件
)

# 下载依赖脚本和配置文件的函数
download_dependencies() {
    local download_dir="$1"  # 下载目录

    for dep in "${DEPENDENCIES[@]}"; do
        local FILENAME=$(echo "$dep" | cut -d'|' -f1)
        local URL=$(echo "$dep" | cut -d'|' -f2)

        # 检查文件是否已存在
        if [ ! -f "$download_dir/$FILENAME" ]; then
            echo "正在下载 $FILENAME 到 $download_dir..."
            if ! curl -s -o "$download_dir/$FILENAME" "$URL"; then
                echo "下载失败：$FILENAME"
                exit 1
            fi
        else
            echo "文件已存在：$download_dir/$FILENAME"
        fi
    done
}

# 下载依赖脚本和配置文件到指定目录
download_dependencies "$DOWNLOAD_DIR"



# === 读取和处理配置文件 ===
CONFIG_FILE="$DOWNLOAD_DIR/config.yml"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "配置文件不存在：$CONFIG_FILE"
    exit 1
fi

# 提取版本信息
major=$(grep '^major:' "$CONFIG_FILE" | awk '{print $2}')
minor=$(grep '^minor:' "$CONFIG_FILE" | awk '{print $2}')
patch=$(grep '^patch:' "$CONFIG_FILE" | awk '{print $2}')
version_format=$(grep '^version_format:' "$CONFIG_FILE" | cut -d'"' -f2)

# 构造完整版本号
sh_v=$(echo "$version_format" | sed "s/{major}/$major/" | sed "s/{minor}/$minor/" | sed "s/{patch}/$patch/")

# 输出版本信息
#echo "当前版本号: $sh_v"




washsky_add_kk() {
    # 检查脚本文件是否存在
    log "检查脚本文件是否存在"
    SCRIPT_PATH="$DOWNLOAD_DIR/sh_main.sh"
    if [ ! -f "$SCRIPT_PATH" ]; then
        echo "脚本文件不存在: $SCRIPT_PATH"
        log "检查脚本文件存在退出"
        exit 1
    fi

    # 目标目录，通常是 /usr/local/bin
    TARGET_DIR="/usr/local/bin"
    COMMAND_NAME="kk" # 最终的命令名称

    # 如果目标目录已有同名文件或链接，先删除它
    if [ -f "$TARGET_DIR/$COMMAND_NAME" ] || [ -L "$TARGET_DIR/$COMMAND_NAME" ]; then
        echo "目标目录已有同名文件或符号链接，正在删除..."
        sudo rm -f "$TARGET_DIR/$COMMAND_NAME"  # 强制删除
    fi

    # 创建符号链接到目标目录，命名为 kk
    sudo ln -s "$SCRIPT_PATH" "$TARGET_DIR/$COMMAND_NAME"
    echo "已创建符号链接：$TARGET_DIR/$COMMAND_NAME"
    log "已创建符号链接：$TARGET_DIR/$COMMAND_NAME"

    # 确保脚本具有可执行权限
    sudo chmod +x "$SCRIPT_PATH"
    echo "已确保脚本具有可执行权限：$SCRIPT_PATH"
    log "已确保脚本具有可执行权限：$SCRIPT_PATH"

    # 提示用户执行
    echo "符号链接已成功创建，现在可以通过 'kk' 命令直接运行该脚本。"
}


washsky_add_kk

log "脚本执行完毕"


# === 模块函数 === #此函数暂时不使用,因为看着不错先放这
load_modules() {
    # 加载依赖脚本 #通过函数触发顺序
    for dep in "${DEPENDENCIES[@]}"; do
        FILENAME=$(echo "$dep" | cut -d'|' -f1)
        URL=$(echo "$dep" | cut -d'|' -f2)
        if [ ! -f "$DOWNLOAD_DIR/$FILENAME" ]; then
            echo "正在下载 $FILENAME 到 $DOWNLOAD_DIR..."
            curl -s -o "$DOWNLOAD_DIR/$FILENAME" "$URL"
        fi
        source "$DOWNLOAD_DIR/$FILENAME"
    done
}


# 按顺序加载模块
# echo "加载依赖模块..."
log "加载核心初始化模块"
# 1. 加载核心初始化模块
source "$DOWNLOAD_DIR/kejilion.sh"
log "加载核心初始化模块完毕"
# 测试里面是否有init_env函数
# if declare -f init_env > /dev/null; then
#     echo "运行初始化逻辑..."
#     init_env  # 调用初始化函数
# else
#     echo "初始化模块未正确加载，退出。"
#     exit 1
# fi








# === 定义更新函数 ===
kejilion_update() {
    send_stats "脚本更新"
    cd ~
    clear

    echo "更新日志"
    echo "------------------------"
    echo "全部日志: ${gh_proxy}https://raw.githubusercontent.com/kejilion/sh/main/sh_log.txt"
    echo "------------------------"

    # 显示最新的 35 行更新日志
    curl -s ${gh_proxy}https://raw.githubusercontent.com/kejilion/sh/main/sh_log.txt | tail -n 35

    # 定义远程 config.yml 的 URL
    local remote_config_url="https://raw.githubusercontent.com/EasyStartBox/esb/main/config/patch_sh/config.yml"
    local local_config_file="$DOWNLOAD_DIR/config.yml"
    local temp_config_file="/tmp/config.yml"

    # 下载远程的 tag-config.yml 到临时文件
    if ! curl -s -o "$temp_config_file" "$remote_config_url"; then
        echo "下载远程配置文件失败，请检查网络连接。"
        exit 1
    fi

    # 提取远程版本信息
    remote_major=$(grep '^major:' "$temp_config_file" | awk '{print $2}')
    remote_minor=$(grep '^minor:' "$temp_config_file" | awk '{print $2}')
    remote_patch=$(grep '^patch:' "$temp_config_file" | awk '{print $2}')
    remote_version_format=$(grep '^version_format:' "$temp_config_file" | cut -d'"' -f2)

    # 构造远程完整版本号
    remote_sh_v=$(echo "$remote_version_format" | sed "s/{major}/$remote_major/" | sed "s/{minor}/$remote_minor/" | sed "s/{patch}/$remote_patch/")

    # 提取本地版本信息
    if [ -f "$local_config_file" ]; then
        local_major=$(grep '^major:' "$local_config_file" | awk '{print $2}')
        local_minor=$(grep '^minor:' "$local_config_file" | awk '{print $2}')
        local_patch=$(grep '^patch:' "$local_config_file" | awk '{print $2}')
        local_version_format=$(grep '^version_format:' "$local_config_file" | cut -d'"' -f2)

        # 构造本地完整版本号
        local_sh_v=$(echo "$local_version_format" | sed "s/{major}/$local_major/" | sed "s/{minor}/$local_minor/" | sed "s/{patch}/$local_patch/")
    else
        echo "本地配置文件不存在：$local_config_file"
        local_sh_v="0.0.0"  # 假设初始版本为 0.0.0
    fi

    echo "当前版本 v$local_sh_v    最新版本 v$remote_sh_v"
    echo "------------------------"

    # 比较版本号
    if [ "$remote_sh_v" = "$local_sh_v" ]; then
        echo -e "${gl_lv}你已经是最新版本！${gl_huang}v$remote_sh_v${gl_bai}"
        send_stats "脚本已经最新了，无需更新"
    else
        echo "发现新版本！"
        echo -e "当前版本 v$local_sh_v        最新版本 ${gl_huang}v$remote_sh_v${gl_bai}"
        echo "------------------------"
        read -e -p "确定更新脚本吗？(Y/N): " choice
        case "$choice" in
            [Yy])
                clear

                # 获取用户所在国家
                local country=$(curl -s ipinfo.io/country)
                local download_url

                # 根据用户所在国家选择下载路径（防止访问 GitHub 问题）
                if [ "$country" = "CN" ]; then
                    # 如果在中国，从中国区镜像下载所有依赖
                    echo "检测到您位于中国，使用代理下载依赖文件..."
                fi


                # 如果临时目录已经存在文件，先清空它
                local temp_dir="/tmp/patch_sh_update"

                # 测试rm -rf "$temp_dir" 无效,把它加入顶部使每次运行都删除它
                if [ -d "$temp_dir" ]; then
                    echo "临时目录 $temp_dir 存在，正在清空..."
                    rm -rf "$temp_dir"  # 删除目录及其内容
                fi

                # 重新创建临时目录
                mkdir -p "$temp_dir"


                # 下载所有依赖文件到临时目录
                echo "开始下载所有依赖文件到临时目录 $temp_dir..."
                download_dependencies "$temp_dir"

                # 确保 temp_dir 中的文件已经下载完毕
                for dep in "${DEPENDENCIES[@]}"; do
                    local FILENAME=$(echo "$dep" | cut -d'|' -f1)
                    if [ ! -f "$temp_dir/$FILENAME" ]; then
                        echo "下载失败，文件不存在：$temp_dir/$FILENAME"
                        exit 1
                    fi
                done

                # 更新所有依赖文件到目标目录
                echo "开始将更新文件从临时目录复制到 $DOWNLOAD_DIR ..."
                cp -rf "$temp_dir"/* "$DOWNLOAD_DIR"

                # 赋予执行权限
                chmod +x "$DOWNLOAD_DIR/sh_main.sh"

                # 备份当前脚本
                if [ -f "/usr/local/bin/kk" ]; then
                    cp /usr/local/bin/kk /usr/local/bin/kk.bak
                fi

                # 更新目标脚本
                echo "更新脚本 sh_main.sh 到 /usr/local/bin/kk ..."
                cp -f "$DOWNLOAD_DIR/sh_main.sh" /usr/local/bin/kk

                # 更新本地的 tag-config.yml
                cp "$temp_config_file" "$local_config_file"

                # 使用 exec 重新执行脚本，替代当前进程
                exec /usr/local/bin/kk
                ;;
            [Nn])
                echo "已取消更新"
                ;;
            *)
                echo "无效的选择，已取消更新。"
                ;;
        esac
    fi

    # 清理临时配置文件
    rm -f "$temp_config_file"
    rm -rf "$temp_dir"  # 清理临时下载目录
}


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
        "patch_sh_update"
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

# 1. 加载kejilion_sh()函数后面的脚本
# source "$DOWNLOAD_DIR/k_info.sh"

log "脚本执行完毕"
