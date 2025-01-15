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

# 定义配置目录和文件（独立于 DOWNLOAD_DIR）
CONFIG_DIR="$HOME/.patch_sh_config"
CONFIG_FILE="$CONFIG_DIR/commands.conf"

# 创建配置目录
mkdir -p "$CONFIG_DIR" || { echo "无法创建配置目录。"; log "无法创建配置目录。"; exit 1; }

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
    "create_custom_command.sh|https://raw.githubusercontent.com/EasyStartBox/esb/main/scripts/linux/patch_sh/create_custom_command.sh"
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

log "当前版本 $sh_v"


# 加载自定义命令  ==== 自定义命令实现 ====
source "$DOWNLOAD_DIR/create_custom_command.sh"

# 创建所有自定义命令
create_all_custom_commands

# === 其他脚本逻辑 ===

# 在这里添加其他需要在安装/更新时执行的逻辑

log "脚本执行完毕"
echo "安装/更新完成。请使用 'add-command' 来添加新的自定义命令。"

chmod +x "$DOWNLOAD_DIR/sh_main.sh"

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

send_stats() {
  # 这里可以什么都不做，避免函数不存在的错误
  return 0
}

CheckFirstRun_false(){
    return 0
}

# 按顺序加载模块
# echo "加载依赖模块..."
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
# ==