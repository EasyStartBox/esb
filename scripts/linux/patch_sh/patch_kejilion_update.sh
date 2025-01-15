#!/bin/bash

# === 定义更新函数 ===
# === 定义更新函数 ===
kejilion_update() {
    # 解析传递的参数
    local FORCE_UPDATE=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            force)
                FORCE_UPDATE=true
                shift
                ;;
            *)
                echo "未知参数: $1"
                log "未知参数: $1"
                exit 1
                ;;
        esac
    done

    # 确保全局变量已定义
    if [ -z "$DOWNLOAD_DIR" ] || [ -z "$DEPENDENCIES" ]; then
        echo "必要的全局变量未定义。"
        log "必要的全局变量未定义。"
        exit 1
    fi

    send_stats "脚本更新"

    cd ~ || { echo "无法切换到主目录。"; log "无法切换到主目录。"; exit 1; }

    clear

    echo "更新日志"
    echo "------------------------"

    echo "全部日志: ${gh_proxy}https://raw.githubusercontent.com/kejilion/sh/main/kejilion_sh_log.txt"
    echo "------------------------"

    # 下载并显示最新的35条日志
    curl -s "${gh_proxy}https://raw.githubusercontent.com/kejilion/sh/main/kejilion_sh_log.txt" | tail -n 35

    # 定义远程 config.yml 的 URL
    local remote_config_url="https://raw.githubusercontent.com/EasyStartBox/esb/main/config/patch_sh/config.yml"
    local local_config_file="$DOWNLOAD_DIR/config.yml"
    local temp_config_file=$(mktemp /tmp/config.yml.XXXXXX) || { echo "无法创建临时配置文件。"; log "无法创建临时配置文件。"; exit 1; }

    # 下载远程的 config.yml 到临时文件
    if ! curl -s -o "$temp_config_file" "$remote_config_url"; then
        echo "下载远程配置文件失败，请检查网络连接。"
        log "下载远程配置文件失败。"
        exit 1
    fi

    # 提取远程版本信息
    remote_major=$(grep '^major:' "$temp_config_file" | awk '{print $2}')
    remote_minor=$(grep '^minor:' "$temp_config_file" | awk '{print $2}')
    remote_patch=$(grep '^patch:' "$temp_config_file" | awk '{print $2}')
    remote_version_format=$(grep '^version_format:' "$temp_config_file" | cut -d'"' -f2)

    # 检查远程版本信息是否提取成功
    if [ -z "$remote_major" ] || [ -z "$remote_minor" ] || [ -z "$remote_patch" ] || [ -z "$remote_version_format" ]; then
        echo "远程配置文件中的版本信息不完整。"
        log "远程配置文件中的版本信息不完整。"
        rm -f "$temp_config_file"
        exit 1
    fi

    # 构造远程完整版本号（不包含 'v' 前缀）
    remote_sh_v=$(echo "$remote_version_format" | sed "s/{major}/$remote_major/" | sed "s/{minor}/$remote_minor/" | sed "s/{patch}/$remote_patch/")
    log "远程版本 $remote_sh_v"

    # 提取本地版本信息
    if [ -f "$local_config_file" ]; then
        local_major=$(grep '^major:' "$local_config_file" | awk '{print $2}')
        local_minor=$(grep '^minor:' "$local_config_file" | awk '{print $2}')
        local_patch=$(grep '^patch:' "$local_config_file" | awk '{print $2}')
        local_version_format=$(grep '^version_format:' "$local_config_file" | cut -d'"' -f2)

        # 检查本地版本信息是否提取成功
        if [ -z "$local_major" ] || [ -z "$local_minor" ] || [ -z "$local_patch" ] || [ -z "$local_version_format" ]; then
            echo "本地配置文件中的版本信息不完整。"
            log "本地配置文件中的版本信息不完整。"
            local_sh_v="0.0.0"  # 假设初始版本为 0.0.0
        else
            # 构造本地完整版本号（不包含 'v' 前缀）
            local_sh_v=$(echo "$local_version_format" | sed "s/{major}/$local_major/" | sed "s/{minor}/$local_minor/" | sed "s/{patch}/$local_patch/")
            log "本地版本 $local_sh_v"
        fi
    else
        echo "本地配置文件不存在：$local_config_file"
        log "本地配置文件不存在：$local_config_file"
        local_sh_v="0.0.0"  # 假设初始版本为 0.0.0
    fi

    echo "当前版本 $local_sh_v    最新版本 $remote_sh_v"
    echo "------------------------"

    # 版本比较函数
    version_compare() {
        # 去除可能的 'v' 前缀
        local ver1="${1#v}"
        local ver2="${2#v}"

        if [[ "$ver1" == "$ver2" ]]; then
            return 0
        fi

        local IFS=.
        local i
        local ver1_array=($ver1)
        local ver2_array=($ver2)

        # 填充较短的版本号数组
        for ((i=${#ver1_array[@]}; i<${#ver2_array[@]}; i++)); do
            ver1_array[i]=0
        done
        for ((i=${#ver2_array[@]}; i<${#ver1_array[@]}; i++)); do
            ver2_array[i]=0
        done

        for ((i=0; i<${#ver1_array[@]}; i++)); do
            if ((10#${ver1_array[i]} > 10#${ver2_array[i]})); then
                return 1
            fi
            if ((10#${ver1_array[i]} < 10#${ver2_array[i]})); then
                return 2
            fi
        done

        return 0
    }

    version_compare "$remote_sh_v" "$local_sh_v"
    compare_result=$?

    if [ "$compare_result" -eq 0 ]; then
        if [ "$FORCE_UPDATE" = true ]; then
            echo -e "${gl_lv}强制更新脚本。${gl_bai}"
            log "强制更新脚本。"
        else
            echo -e "${gl_lv}你已经是最新版本！${gl_huang}$remote_sh_v${gl_bai}"
            log "脚本已经是最新版本 $remote_sh_v，无需更新。"

            # 提示用户是否要强制更新
            read -e -p "是否要强制更新脚本？(Y/N): " user_choice
            case "$user_choice" in
                [Yy]* )
                    FORCE_UPDATE=true
                    log "用户选择强制更新脚本。"
                    ;;
                [Nn]* )
                    echo "已取消更新。"
                    log "用户取消了更新。"
                    # 清理临时配置文件
                    rm -f "$temp_config_file"
                    log "清理临时配置文件 $temp_config_file."
                    return
                    ;;
                * )
                    echo "无效的选择，已取消更新。"
                    log "用户输入无效，更新已取消。"
                    # 清理临时配置文件
                    rm -f "$temp_config_file"
                    log "清理临时配置文件 $temp_config_file."
                    return
                    ;;
            esac
        fi
    elif [ "$compare_result" -eq 2 ]; then
        if [ "$FORCE_UPDATE" = false ]; then
            echo -e "${gl_lv}本地版本高于远程版本，可能存在问题。${gl_bai}"
            log "本地版本高于远程版本，建议检查。"
            # 清理临时配置文件
            rm -f "$temp_config_file"
            log "清理临时配置文件 $temp_config_file."
            return
        fi
    fi

    # 如果是强制更新或发现新版本，则执行更新逻辑
    if [ "$FORCE_UPDATE" = true ] || [ "$compare_result" -eq 1 ]; then
        echo "准备更新脚本..."
        if [ "$FORCE_UPDATE" = true ]; then
            echo -e "当前版本 $local_sh_v        最新版本 ${gl_huang}$remote_sh_v${gl_bai} (强制更新)"
        else
            echo -e "当前版本 $local_sh_v        最新版本 ${gl_huang}$remote_sh_v${gl_bai}"
        fi
        echo "------------------------"
        read -e -p "确定更新脚本吗？(Y/N): " choice
        case "$choice" in
            [Yy]* )
                clear

                # 获取用户所在国家
                local country=$(curl -s ipinfo.io/country)
                local download_url

                # 根据用户所在国家选择下载路径（防止访问 GitHub 问题）
                if [ "$country" = "CN" ]; then
                    # 如果在中国，从中国区镜像下载所有依赖
                    echo "检测到您位于中国，使用代理下载依赖文件..."
                    # 这里可以设置代理或更改下载源，例如：
                    # gh_proxy="https://ghproxy.com/"
                fi

                # 使用唯一的临时目录
                local temp_dir=$(mktemp -d /tmp/patch_sh_update.XXXXXX) || { echo "无法创建临时目录。"; log "无法创建临时目录。"; exit 1; }

                # 下载所有依赖文件到临时目录
                echo "开始下载所有依赖文件到临时目录 $temp_dir..."
                log "开始下载所有依赖文件到临时目录 $temp_dir."

                download_dependencies "$temp_dir"

                # 确保 temp_dir 中的文件已经下载完毕
                for dep in "${DEPENDENCIES[@]}"; do
                    local FILENAME="${dep%%|*}"
                    if [ ! -f "$temp_dir/$FILENAME" ]; then
                        echo "下载失败，文件不存在：$temp_dir/$FILENAME"
                        log "下载失败，文件不存在：$temp_dir/$FILENAME"
                        rm -rf "$temp_dir"
                        exit 1
                    fi
                done

                echo "所有依赖文件下载完成。"
                log "所有依赖文件下载完成。"

                # 备份当前下载目录
                if [ -d "$DOWNLOAD_DIR" ]; then
                    echo "备份当前下载目录到 ${DOWNLOAD_DIR}.bak..."
                    cp -r "$DOWNLOAD_DIR" "${DOWNLOAD_DIR}.bak" || { echo "备份下载目录失败。"; log "备份下载目录失败。"; rm -rf "$temp_dir"; exit 1; }
                    log "备份下载目录到 ${DOWNLOAD_DIR}.bak."
                fi

                # 覆盖下载目录
                echo "覆盖下载目录 $DOWNLOAD_DIR..."
                rm -rf "$DOWNLOAD_DIR"
                mkdir -p "$DOWNLOAD_DIR"
                cp -rf "$temp_dir"/* "$DOWNLOAD_DIR" || { echo "覆盖下载目录失败。"; log "覆盖下载目录失败。"; rm -rf "$temp_dir"; exit 1; }
                log "覆盖下载目录完成。"

                # 赋予执行权限
                chmod +x "$DOWNLOAD_DIR/sh_main.sh" || { echo "无法设置 sh_main.sh 为可执行。"; log "无法设置 sh_main.sh 为可执行。"; rm -rf "$temp_dir"; exit 1; }
                log "已设置 sh_main.sh 为可执行。"

                # 备份并重新创建符号链接 /usr/local/bin/kk
                if [ -L "/usr/local/bin/kk" ]; then
                    echo "备份当前符号链接 /usr/local/bin/kk 到 /usr/local/bin/kk.bak..."
                    cp -r "/usr/local/bin/kk" "/usr/local/bin/kk.bak" || { echo "备份符号链接失败。"; log "备份符号链接失败。"; rm -rf "$temp_dir"; exit 1; }
                    log "备份符号链接 /usr/local/bin/kk 到 /usr/local/bin/kk.bak."
                elif [ -f "/usr/local/bin/kk" ]; then
                    echo "备份当前脚本 /usr/local/bin/kk 到 /usr/local/bin/kk.bak..."
                    cp "/usr/local/bin/kk" "/usr/local/bin/kk.bak" || { echo "备份当前脚本失败。"; log "备份当前脚本失败。"; rm -rf "$temp_dir"; exit 1; }
                    log "备份当前脚本 /usr/local/bin/kk 到 /usr/local/bin/kk.bak."
                fi

                # 确保 /usr/local/bin/kk 是指向最新 sh_main.sh 的符号链接
                echo "更新符号链接 /usr/local/bin/kk -> $DOWNLOAD_DIR/sh_main.sh"
                ln -sf "$DOWNLOAD_DIR/sh_main.sh" /usr/local/bin/kk || { echo "更新符号链接失败。"; log "更新符号链接失败。"; rm -rf "$temp_dir"; exit 1; }
                log "更新符号链接 /usr/local/bin/kk -> $DOWNLOAD_DIR/sh_main.sh 完成。"

                # 更新本地的 config.yml
                cp "$temp_config_file" "$local_config_file" || { echo "更新本地配置文件失败。"; log "更新本地配置文件失败。"; rm -rf "$temp_dir"; exit 1; }
                log "更新本地配置文件 $local_config_file."

                # 清理临时目录
                rm -rf "$temp_dir"
                log "清理临时目录 $temp_dir."

                # 使用 exec 重新执行脚本，替代当前进程
                echo "更新完成，重新启动脚本..."
                exec /usr/local/bin/kk
                ;;
            [Nn]* )
                echo "已取消更新。"
                log "用户取消了更新。"
                ;;
            * )
                echo "无效的选择，已取消更新。"
                log "用户输入无效，更新已取消。"
                ;;
        esac
    fi

    # 清理临时配置文件
    rm -f "$temp_config_file"
    log "清理临时配置文件 $temp_config_file."
}

# ====
