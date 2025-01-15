#!/bin/bash


# === 自定义命令管理部分 ===

# 创建自定义命令的函数，支持任意命令名称
create_custom_command() {
    local command_name="$1"

    # 检查命令名称是否提供
    if [ -z "$command_name" ]; then
        echo "未提供命令名称。使用方法: add-command"
        exit 1
    fi

    # 检查命令名称是否有效（仅允许字母、数字和下划线）
    if [[ ! "$command_name" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo "无效的命令名称。仅允许字母、数字和下划线。"
        exit 1
    fi

    log "开始创建自定义命令：$command_name"
    SCRIPT_PATH="$DOWNLOAD_DIR/sh_main.sh"

    if [ ! -f "$SCRIPT_PATH" ]; then
        echo "脚本文件不存在: $SCRIPT_PATH"
        log "检查脚本文件不存在，退出"
        exit 1
    fi
    log "脚本文件存在：$SCRIPT_PATH"

    TARGET_DIR="/usr/local/bin"

    # 检查并删除现有的同名文件或符号链接
    if [ -e "$TARGET_DIR/$command_name" ]; then
        echo "目标目录已有同名文件或符号链接 '$command_name'，正在删除..."
        log "删除现有的 $TARGET_DIR/$command_name"
        rm -f "$TARGET_DIR/$command_name" || { echo "无法删除现有文件"; exit 1; }
    fi

    # 创建符号链接
    ln -s "$SCRIPT_PATH" "$TARGET_DIR/$command_name" && \
    { 
        log "符号链接创建成功：$TARGET_DIR/$command_name"
        echo "符号链接已创建：$TARGET_DIR/$command_name"
    } || { 
        log "符号链接创建失败：$TARGET_DIR/$command_name"
        echo "符号链接创建失败，请检查权限或路径问题。"
        exit 1 
    }

    # 确保脚本具有可执行权限
    chmod +x "$SCRIPT_PATH" && \
    { 
        log "已确保脚本具有可执行权限：$SCRIPT_PATH"
        echo "脚本已具有可执行权限：$SCRIPT_PATH"
    } || { 
        log "无法确保脚本具有可执行权限：$SCRIPT_PATH"
        echo "设置脚本可执行权限失败，请检查权限。"
        exit 1 
    }

    # 将命令名称保存到自定义命令列表中（避免重复）
    if ! grep -Fxq "$command_name" "$CONFIG_FILE"; then
        echo "$command_name" >> "$CONFIG_FILE"
        log "自定义命令 '$command_name' 已添加到 $CONFIG_FILE"
        echo "自定义命令 '$command_name' 已添加。"
    else
        echo "命令 '$command_name' 已存在于 $CONFIG_FILE 中。"
    fi
}

# 读取 commands.conf 并创建所有自定义命令的符号链接
create_all_custom_commands() {
    local commands_file="$CONFIG_FILE"

    if [ ! -f "$commands_file" ]; then
        echo "自定义命令配置文件不存在，跳过创建自定义命令。"
        log "自定义命令配置文件不存在，跳过创建自定义命令。"
        return
    fi

    while IFS= read -r command_name; do
        # 跳过空行和注释
        [[ -z "$command_name" || "$command_name" =~ ^# ]] && continue

        log "正在创建自定义命令：$command_name"
        SCRIPT_PATH="$DOWNLOAD_DIR/sh_main.sh"
        TARGET_DIR="/usr/local/bin"
        link_path="$TARGET_DIR/$command_name"

        # 检查并删除现有的同名文件或符号链接
        if [ -e "$link_path" ]; then
            echo "目标目录已有同名文件或符号链接 '$command_name'，正在删除..."
            log "删除现有的 $link_path"
            rm -f "$link_path" || { echo "无法删除现有文件 $link_path"; exit 1; }
        fi

        # 创建符号链接
        ln -s "$SCRIPT_PATH" "$link_path" && \
        { 
            log "符号链接创建成功：$link_path"
            echo "符号链接已创建：$link_path"
        } || { 
            log "符号链接创建失败：$link_path"
            echo "符号链接创建失败，请检查权限或路径问题。"
            exit 1 
        }

        # 确保脚本具有可执行权限
        chmod +x "$SCRIPT_PATH" && \
        { 
            log "已确保脚本具有可执行权限：$SCRIPT_PATH"
            echo "脚本已具有可执行权限：$SCRIPT_PATH"
        } || { 
            log "无法确保脚本具有可执行权限：$SCRIPT_PATH"
            echo "设置脚本可执行权限失败，请检查权限。"
            exit 1 
        }

    done < "$commands_file"

    log "所有自定义命令已创建完成。"
}

# 移除自定义命令的函数
remove_custom_command() {
    local command_name="$1"
    local commands_file="$CONFIG_FILE"

    if [ -z "$command_name" ]; then
        echo "未提供命令名称。使用方法: remove-command <命令名称>"
        exit 1
    fi

    # 检查命令是否存在
    if ! grep -Fxq "$command_name" "$commands_file"; then
        echo "命令 '$command_name' 不存在。"
        exit 1
    fi

    # 删除符号链接
    local link_path="/usr/local/bin/$command_name"
    if [ -L "$link_path" ]; then
        rm -f "$link_path" && \
        { 
            log "符号链接已删除：$link_path"
            echo "符号链接已删除：$link_path"
        } || { 
            echo "无法删除符号链接：$link_path"
            exit 1 
        }
    else
        echo "符号链接不存在：$link_path"
    fi

    # 从 commands.conf 中移除命令
    grep -v "^$command_name$" "$commands_file" > "$commands_file.tmp" && mv "$commands_file.tmp" "$commands_file"
    log "命令 '$command_name' 已从 $commands_file 中移除"
    echo "命令 '$command_name' 已移除。"
}

# 列出所有自定义命令的函数
list_custom_commands() {
    local commands_file="$CONFIG_FILE"

    if [ ! -f "$commands_file" ]; then
        echo "没有自定义命令。"
        exit 0
    fi

    echo "当前自定义命令列表："
    grep -v "^#" "$commands_file" | while IFS= read -r cmd; do
        [ -z "$cmd" ] && continue
        echo "- $cmd"
    done
}

# === 脚本参数处理 ===

case "$1" in
    add-command)
        read -p "请输入自定义命令名称: " new_command
        create_custom_command "$new_command"
        exit 0
        ;;
    remove-command)
        read -p "请输入要移除的自定义命令名称: " del_command
        remove_custom_command "$del_command"
        exit 0
        ;;
    list-commands)
        list_custom_commands
        exit 0
        ;;
    uninstall)
        echo "卸载所有自定义命令..."
        while IFS= read -r command_name; do
            [[ -z "$command_name" || "$command_name" =~ ^# ]] && continue
            local link_path="/usr/local/bin/$command_name"
            if [ -L "$link_path" ]; then
                rm -f "$link_path" && \
                { 
                    log "符号链接已删除：$link_path"
                    echo "符号链接已删除：$link_path"
                } || { 
                    echo "无法删除符号链接：$link_path"
                }
            fi
        done < "$CONFIG_FILE"
        rm -f "$CONFIG_FILE"
        log "所有自定义命令已卸载，$CONFIG_FILE 已删除。"
        echo "所有自定义命令已卸载。"
        exit 0
        ;;
    *)
        ;;
esac
