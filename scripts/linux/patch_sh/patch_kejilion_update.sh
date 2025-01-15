#!/bin/bash

# === 定义更新函数 ===
kejilion_update() {
    # 检查是否传递了 "force" 参数
    local FORCE_UPDATE=false
    if [ "$1" == "force" ]; then
        FORCE_UPDATE=true
    fi

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

    # 构造远程完整版本号
    remote_sh_v=$(echo "$remote_version_format" | sed "s/{major}/$remote_major/" | sed "s/{minor}/$remote_minor/" | sed "s/{patch}/$remote_patch/")
    log "远程版本 v$remote_sh_v"

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
            # 构造本地完整版本号
            local_sh_v=$(echo "$local_version_format" | sed "s/{major}/$local_major/" | sed "s/{minor}/$local_minor/" | sed "s/{patch}/$local_patch/")
            log "本地版本 v$local_sh_v"
        fi
    else
        echo "本地配置文件不存在：$local_config_file"
        log "本地配置文件不存在：$local_config_file"
        local_sh_v="0.0.0"  # 假设初始版本为 0.0.0
    fi

    echo "当前版本 v$local_sh_v    最新版本 v$remote_sh_v"
    echo "------------------------"

    # 版本比较函数
    version_compare() {
        if [[ "$1" == "$2" ]]; then
            return 0
        fi

        local IFS=.
        local i
        local ver1=($1)
        local ver2=($2)

        # Fill empty fields in ver1 with zeros
        for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
            ver1[i]=0
        done
        # Fill empty fields in ver2 with zeros
        for ((i=0; i<${#ver1[@]}; i++)); do
            if [[ -z ${ver2[i]} ]]; then
                ver2[i]=0
            fi
            if ((10#${ver1[i]} > 10#${ver2[i]})); then
                return 1
            fi
            if ((10#${ver1[i]} < 10#${ver2[i]})); then
                return 2
            fi
        done
        return 0
    }

    version_compare "$remote_sh_v" "$local_sh_v"
    compare_result=$?

    if [ "$FORCE_UPDATE" = true ]; then
        echo -e "${gl_lv}强制更新脚本。${gl_bai}"
        log "强制更新脚本。"
    elif [ $compare_result -eq 0 ]; then
        echo -e "${gl_lv}你已经是最新版本！${gl_huang}v$remote_sh_v${gl_bai}"
        log "脚本已经是最新版本 v$remote_sh_v，无需更新。"
        # 清理临时配置文件
        rm -f "$temp_config_file"
        log "清理临时配置文件 $temp_config_file."
        return
    fi

    # 如果是强制更新或发现新版本，则执行更新逻辑
    if [ "$FORCE_UPDATE" = true ] || [ $compare_result -ne 0 ]; then
        echo "发现新版本！"
        if [ "$FORCE_UPDATE" = true ]; then
            echo -e "当前版本 v$local_sh_v        最新版本 ${gl_huang}v$remote_sh_v${gl_bai} (强制更新)"
        else
            echo -e "当前版本 v$local_sh_v        最新版本 ${gl_huang}v$remote_sh_v${gl_bai}"
        fi
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
                cp -rf "$temp_dir"/* "$DOWNLOAD_DIR/" || { echo "覆盖下载目录失败。"; log "覆盖下载目录失败。"; rm -rf "$temp_dir"; exit 1; }
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
            [Nn])
                echo "已取消更新"
                log "用户取消了更新。"
                ;;
            *)
                echo "无效的选择，已取消更新。"
                log "用户输入无效，更新已取消。"
                ;;
        esac
    fi

    # 清理临时配置文件
    rm -f "$temp_config_file"
    log "清理临时配置文件 $temp_config_file."
}








# # === 定义更新函数 ===
# kejilion_update() {
#     send_stats "脚本更新"
#     cd ~
#     clear

#     echo "更新日志"
#     echo "------------------------"

# 	echo "全部日志: ${gh_proxy}https://raw.githubusercontent.com/kejilion/sh/main/kejilion_sh_log.txt"
# 	echo "------------------------"

# 	curl -s ${gh_proxy}https://raw.githubusercontent.com/kejilion/sh/main/kejilion_sh_log.txt | tail -n 35

#     # 定义远程 config.yml 的 URL
#     local remote_config_url="https://raw.githubusercontent.com/EasyStartBox/esb/main/config/patch_sh/config.yml"
#     local local_config_file="$DOWNLOAD_DIR/config.yml"
#     local temp_config_file="/tmp/config.yml"

#     # 下载远程的 tag-config.yml 到临时文件
#     if ! curl -s -o "$temp_config_file" "$remote_config_url"; then
#         echo "下载远程配置文件失败，请检查网络连接。"
#         exit 1
#     fi

#     # 提取远程版本信息
#     remote_major=$(grep '^major:' "$temp_config_file" | awk '{print $2}')
#     remote_minor=$(grep '^minor:' "$temp_config_file" | awk '{print $2}')
#     remote_patch=$(grep '^patch:' "$temp_config_file" | awk '{print $2}')
#     remote_version_format=$(grep '^version_format:' "$temp_config_file" | cut -d'"' -f2)

#     # 构造远程完整版本号
#     remote_sh_v=$(echo "$remote_version_format" | sed "s/{major}/$remote_major/" | sed "s/{minor}/$remote_minor/" | sed "s/{patch}/$remote_patch/")

#     # 提取本地版本信息
#     if [ -f "$local_config_file" ]; then
#         local_major=$(grep '^major:' "$local_config_file" | awk '{print $2}')
#         local_minor=$(grep '^minor:' "$local_config_file" | awk '{print $2}')
#         local_patch=$(grep '^patch:' "$local_config_file" | awk '{print $2}')
#         local_version_format=$(grep '^version_format:' "$local_config_file" | cut -d'"' -f2)

#         # 构造本地完整版本号
#         local_sh_v=$(echo "$local_version_format" | sed "s/{major}/$local_major/" | sed "s/{minor}/$local_minor/" | sed "s/{patch}/$local_patch/")
#     else
#         echo "本地配置文件不存在：$local_config_file"
#         local_sh_v="0.0.0"  # 假设初始版本为 0.0.0
#     fi

#     echo "当前版本 v$local_sh_v    最新版本 v$remote_sh_v"
#     echo "------------------------"

#     # 比较版本号
#     if [ "$remote_sh_v" = "$local_sh_v" ]; then
#         echo -e "${gl_lv}你已经是最新版本！${gl_huang}v$remote_sh_v${gl_bai}"
#         send_stats "脚本已经最新了，无需更新"
#     else
#         echo "发现新版本！"
#         echo -e "当前版本 v$local_sh_v        最新版本 ${gl_huang}v$remote_sh_v${gl_bai}"
#         echo "------------------------"
#         read -e -p "确定更新脚本吗？(Y/N): " choice
#         case "$choice" in
#             [Yy])
#                 clear

#                 # 获取用户所在国家
#                 local country=$(curl -s ipinfo.io/country)
#                 local download_url

#                 # 根据用户所在国家选择下载路径（防止访问 GitHub 问题）
#                 if [ "$country" = "CN" ]; then
#                     # 如果在中国，从中国区镜像下载所有依赖
#                     echo "检测到您位于中国，使用代理下载依赖文件..."
#                 fi


#                 # 如果临时目录已经存在文件，先清空它
#                 local temp_dir="/tmp/patch_sh_update"

#                 # 测试rm -rf "$temp_dir" 无效,把它加入顶部使每次运行都删除它
#                 if [ -d "$temp_dir" ]; then
#                     echo "临时目录 $temp_dir 存在，正在清空..."
#                     rm -rf "$temp_dir"  # 删除目录及其内容
#                 fi

#                 # 重新创建临时目录
#                 mkdir -p "$temp_dir"


#                 # 下载所有依赖文件到临时目录
#                 echo "开始下载所有依赖文件到临时目录 $temp_dir..."
#                 download_dependencies "$temp_dir"

#                 # 确保 temp_dir 中的文件已经下载完毕
#                 for dep in "${DEPENDENCIES[@]}"; do
#                     local FILENAME=$(echo "$dep" | cut -d'|' -f1)
#                     if [ ! -f "$temp_dir/$FILENAME" ]; then
#                         echo "下载失败，文件不存在：$temp_dir/$FILENAME"
#                         exit 1
#                     fi
#                 done

#                 # 更新所有依赖文件到目标目录
#                 echo "开始将更新文件从临时目录复制到 $DOWNLOAD_DIR ..."
#                 cp -rf "$temp_dir"/* "$DOWNLOAD_DIR"

#                 # 赋予执行权限
#                 chmod +x "$DOWNLOAD_DIR/sh_main.sh"

#                 # 备份当前脚本
#                 if [ -f "/usr/local/bin/kk" ]; then
#                     cp /usr/local/bin/kk /usr/local/bin/kk.bak
#                 fi

#                 # 更新目标脚本
#                 echo "更新脚本 sh_main.sh 到 /usr/local/bin/kk ..."
#                 cp -f "$DOWNLOAD_DIR/sh_main.sh" /usr/local/bin/kk

#                 # 更新本地的 tag-config.yml
#                 cp "$temp_config_file" "$local_config_file"

#                 # 使用 exec 重新执行脚本，替代当前进程
#                 exec /usr/local/bin/kk
#                 ;;
#             [Nn])
#                 echo "已取消更新"
#                 ;;
#             *)
#                 echo "无效的选择，已取消更新。"
#                 ;;
#         esac
#     fi

#     # 清理临时配置文件
#     rm -f "$temp_config_file"
#     rm -rf "$temp_dir"  # 清理临时下载目录
# }