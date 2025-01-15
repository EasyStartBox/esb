#!/bin/bash

# === 权限检查 ===
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本，例如使用 sudo。"
    exit 1
fi

# === 配置部分 ===

# 设置基础目录
cd ~ || { echo "无法切换到主目录。"; exit 1; }

# 每次运行删除临时目录
rm -rf /tmp/patch_sh_update

# 日志文件
log_file="/var/log/patch_sh_script.log"

# 日志函数
log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$log_file"
}

log "脚本开始执行"

# 打印Hello, World!
echo "Hello, World!"
log "Hello, World! 命令已执行"

# 设置下载目录
DEFAULT_DIR="$HOME/.patch_sh"
DOWNLOAD_DIR="$DEFAULT_DIR"  # 固定为默认目录，不通过参数设置
#rm -rf "$DOWNLOAD_DIR"

# 定义配置目录和文件（独立于 DOWNLOAD_DIR）
CONFIG_DIR="$HOME/.patch_sh_config"
CONFIG_FILE="$CONFIG_DIR/commands.conf"

# 创建配置目录
mkdir -p "$CONFIG_DIR"

# 如果 commands.conf 不存在，初始化为包含默认命令 'kk'
if [ ! -f "$CONFIG_FILE" ]; then
    echo "kk" > "$CONFIG_FILE"
    log "初始化 commands.conf，添加默认命令 'kk'"
fi

# 清理函数
cleanup() {
    echo "清理临时资源..."
}
trap cleanup EXIT

# 创建下载目录
mkdir -p "$DOWNLOAD_DIR"

# 定义依赖项
DEPENDENCIES=(
    "patch_kejilion_update.sh|https://raw.githubusercontent.com/EasyStartBox/esb/main/scripts/linux/patch_sh/patch_kejilion_update.sh"
    "patch_kejilion_sh.sh|https://raw.githubusercontent.com/EasyStartBox/esb/main/scripts/linux/patch_sh/patch_kejilion_sh.sh"
    "sh_main.sh|https://raw.githubusercontent.com/EasyStartBox/esb/main/scripts/linux/patch_sh/sh_main.sh"
    "kejilion.sh|https://raw.githubusercontent.com/kejilion/sh/main/kejilion.sh"
    "config.yml|https://raw.githubusercontent.com/EasyStartBox/esb/main/config/patch_sh/config.yml"
)

# 下载依赖项函数
download_dependencies() {
    local download_dir="$1"
    for dep in "${DEPENDENCIES[@]}"; do
        local FILENAME=$(echo "$dep" | cut -d'|' -f1)
        local URL=$(echo "$dep" | cut -d'|' -f2)
        if [ ! -f "$download_dir/$FILENAME" ]; then
            echo "正在下载 $FILENAME 到 $download_dir..."
            if ! curl -s -o "$download_dir/$FILENAME" "$URL"; then
                echo "下载失败：$FILENAME"
                log "下载失败：$FILENAME"
                exit 1
            fi
            log "下载成功：$FILENAME"
        else
            echo "文件已存在：$download_dir/$FILENAME"
            log "文件已存在：$download_dir/$FILENAME"
        fi
    done
}

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

# === 主安装/更新逻辑 ===

echo "开始安装/更新脚本..."
log "开始安装/更新脚本..."

# 下载依赖项
download_dependencies "$DOWNLOAD_DIR"

# 读取并处理配置文件
CONFIG_YML="$DOWNLOAD_DIR/config.yml"
if [ ! -f "$CONFIG_YML" ]; then
    echo "配置文件不存在：$CONFIG_YML"
    log "配置文件不存在：$CONFIG_YML"
    exit 1
fi

# 提取版本信息
major=$(grep '^major:' "$CONFIG_YML" | awk '{print $2}')
minor=$(grep '^minor:' "$CONFIG_YML" | awk '{print $2}')
patch=$(grep '^patch:' "$CONFIG_YML" | awk '{print $2}')
version_format=$(grep '^version_format:' "$CONFIG_YML" | cut -d'"' -f2)
sh_v=$(echo "$version_format" | sed "s/{major}/$major/" | sed "s/{minor}/$minor/" | sed "s/{patch}/$patch/")

log "当前版本 v$sh_v"

# 创建所有自定义命令
create_all_custom_commands

# === 其他脚本逻辑 ===

# 在这里添加其他需要在安装/更新时执行的逻辑

log "脚本执行完毕"
echo "安装/更新完成。请使用 'add-command' 来添加新的自定义命令。"


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



# 测试里面是否有init_env函数
# if declare -f init_env > /dev/null; then
#     echo "运行初始化逻辑..."
#     init_env  # 调用初始化函数
# else
#     echo "初始化模块未正确加载，退出。"
#     exit 1
# fi





send_stats() {
  # 这里可以什么都不做，避免函数不存在的错误
  return 0
}

CheckFirstRun_false(){
    return 0
}





# 定义"a"颜色变量
gl_orange="\033[1;33m"  # 橙色（通常用黄色近似表示）
gl_reset="\033[0m"      # 重置颜色




# 按顺序加载模块
# echo "加载依赖模块..."
log "加载核心初始化模块"
# 1. 加载核心初始化模块
# load_modules_core(){
#     source "$DOWNLOAD_DIR/kejilion.sh"
#     log "加载核心初始化模块完毕"

#     unset -f kejilion_update
#     unset -f kejilion_sh
#     unset sh_v

# }
# load_modules_core

source "$DOWNLOAD_DIR/patch_kejilion_update.sh"
source "$DOWNLOAD_DIR/patch_kejilion_sh.sh"



# 定义子脚本路径
CHILD_SCRIPT="$DOWNLOAD_DIR/kejilion.sh"

# 删除函数 kejilion_update 的定义
sed -i '/^kejilion_update()/,/^}/d' "$CHILD_SCRIPT"
sed -i '/^kejilion_sh()/,/^}/d' "$CHILD_SCRIPT"
sed -i '/^send_stats()/,/^}/d' "$CHILD_SCRIPT"
sed -i '/^UserLicenseAgreement()/,/^}/d' "$CHILD_SCRIPT"
sed -i '/^CheckFirstRun_false()/,/^}/d' "$CHILD_SCRIPT"


# 删除变量 sh_v 的定义
sed -i '/^sh_v=/d' "$CHILD_SCRIPT"

# 加载修改后的子脚本
source "$CHILD_SCRIPT"




log "脚本执行完毕"
