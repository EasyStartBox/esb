#!/bin/bash


cd

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
rm -rf "$DOWNLOAD_DIR"
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
    "patch_kejilion_update.sh|https://raw.githubusercontent.com/EasyStartBox/esb/main/scripts/linux/patch_sh/patch_kejilion_update.sh"
    "patch_kejilion_sh.sh|https://raw.githubusercontent.com/EasyStartBox/esb/main/scripts/linux/patch_sh/patch_kejilion_sh.sh"
    "sh_main.sh|https://raw.githubusercontent.com/EasyStartBox/esb/main/scripts/linux/patch_sh/sh_main.sh"
    "kejilion.sh|https://raw.githubusercontent.com/EasyStartBox/esb/main/kejilion/sh/kejilion.sh"
    
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
        log "检查脚本文件不存在退出"
        exit 1
    fi
    log "脚本文件存在：$SCRIPT_PATH"

    # 目标目录
    TARGET_DIR="/usr/local/bin"
    COMMAND_NAME="kk" # 最终的命令名称

    # 检查是否有同名文件或符号链接
    if [ -f "$TARGET_DIR/$COMMAND_NAME" ] || [ -L "$TARGET_DIR/$COMMAND_NAME" ]; then
        echo "目标目录已有同名文件或符号链接，正在删除..."
        log "目标目录已有同名文件或符号链接，正在删除：$TARGET_DIR/$COMMAND_NAME"
        rm -f "$TARGET_DIR/$COMMAND_NAME"
    fi

    # 创建符号链接
    log "创建符号链接 $TARGET_DIR/$COMMAND_NAME -> $SCRIPT_PATH"
    ln -s "$SCRIPT_PATH" "$TARGET_DIR/$COMMAND_NAME"
    if [ $? -eq 0 ]; then
        log "符号链接创建成功：$TARGET_DIR/$COMMAND_NAME"
        echo "符号链接已创建：$TARGET_DIR/$COMMAND_NAME"
    else
        log "符号链接创建失败：$TARGET_DIR/$COMMAND_NAME"
        echo "符号链接创建失败，请检查权限或路径问题。"
        exit 1
    fi

    # 确保脚本具有可执行权限
    log "确保脚本具有可执行权限：$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    if [ $? -eq 0 ]; then
        log "已确保脚本具有可执行权限：$SCRIPT_PATH"
        echo "脚本已具有可执行权限：$SCRIPT_PATH"
    else
        log "无法确保脚本具有可执行权限：$SCRIPT_PATH"
        echo "设置脚本可执行权限失败，请检查权限。"
        exit 1
    fi

    # 提示用户
    echo "符号链接已成功创建，现在可以通过 'kk' 命令直接运行该脚本。"
    log "符号链接创建完成，可以通过 'kk' 命令运行该脚本。"
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
