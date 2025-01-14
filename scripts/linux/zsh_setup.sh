#!/bin/bash

# 脚本名称：zsh_setup.sh
# 功能：安装和卸载 Zsh、Oh My Zsh 及相关主题和插件
# 系统要求：基于 Debian 的 Linux 系统，支持 apt 包管理器
# 使用方法：以 root 或 sudo 权限运行脚本，根据提示选择安装或卸载。

# 检查权限
if [ "$(id -u)" -ne 0 ]; then
  echo "请以 root 或使用 sudo 运行此脚本。"
  exit 1
fi

# 输出格式化函数
info() {
  echo -e "\033[32m[INFO]\033[0m $1"
}
warn() {
  echo -e "\033[33m[WARN]\033[0m $1"
}
error() {
  echo -e "\033[31m[ERROR]\033[0m $1"
}

# 路径管理
OH_MY_ZSH_DIR="$HOME/.oh-my-zsh"
ZSH_CUSTOM="${OH_MY_ZSH_DIR}/custom"

# 备份文件
# backup_file() {
#   local file="$1"
#   if [ -f "$file" ]; then
#     mv "$file" "${file}.bak_$(date +%s)"
#     info "$file 已备份为 ${file}.bak_$(date +%s)"
#   fi
# }

# 安装插件或主题函数
install_plugin_or_theme() {
  local name="$1"
  local repo="$2"
  local dest="$3"

  if [ ! -d "$dest" ]; then
    info "正在安装 $name..."
    git clone --depth=1 "$repo" "$dest" || error "$name 安装失败！"
  else
    warn "$name 已存在，跳过安装..."
  fi
}

# 功能选择
echo "请选择操作："
echo "1. 安装 Zsh 及相关配置"
echo "2. 卸载 Zsh 及相关配置"
read -p "请输入选项 (1 或 2): " choice

if [[ "$choice" == "1" ]]; then
  info "正在安装 Zsh 及相关配置..."

  # 更新系统并安装必要工具
  info "正在安装必要软件..."
  apt update && apt install -y wget git curl vim zsh || {
    error "软件安装失败，请检查网络连接或依赖问题。"
    exit 1
  }

  # 安装 Oh My Zsh（非交互）
  if [ ! -d "$OH_MY_ZSH_DIR" ]; then
    info "正在安装 Oh My Zsh (非交互模式)..."
    env RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || {
      error "Oh My Zsh 安装失败！"
      exit 1
    }
  else
    warn "Oh My Zsh 已存在，跳过安装..."
  fi

  # 安装主题和插件
  install_plugin_or_theme "Powerlevel10k 主题" "https://github.com/romkatv/powerlevel10k.git" "${ZSH_CUSTOM}/themes/powerlevel10k"
  install_plugin_or_theme "zsh-autosuggestions 插件" "https://github.com/zsh-users/zsh-autosuggestions.git" "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
  install_plugin_or_theme "zsh-syntax-highlighting 插件" "https://github.com/zsh-users/zsh-syntax-highlighting.git" "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"

  # 配置 Zsh (.zshrc)
  info "配置 Zsh..."
  backup_file "$HOME/.zshrc"
  cat << 'EOF' > "$HOME/.zshrc"
# 设置 Oh My Zsh 路径
export ZSH="$HOME/.oh-my-zsh"

# 使用 powerlevel10k 作为主题
ZSH_THEME="powerlevel10k/powerlevel10k"

# 插件
plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
)

# 加载 Oh My Zsh
if [ -f "$ZSH/oh-my-zsh.sh" ]; then
  source "$ZSH/oh-my-zsh.sh"
else
  echo "Error: Oh My Zsh 文件未找到，请检查安装是否成功。"
fi

# 如果存在 p10k 配置文件则加载
if [ -f "$HOME/.p10k.zsh" ]; then
  source "$HOME/.p10k.zsh"
fi
EOF

  # 配置 Powerlevel10k (.p10k.zsh)
  info "配置 Powerlevel10k..."
  backup_file "$HOME/.p10k.zsh"
  cat << 'EOF' > "$HOME/.p10k.zsh"
# Powerlevel10k config
POWERLEVEL9K_MODE='nerdfont-complete'

# 左侧提示符元素
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(os_icon user dir vcs)

# 右侧提示符元素
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status background_jobs battery time)
EOF

  info "请确保安装支持 Nerd Fonts 的字体（如 MesloLGS NF）以获得最佳效果！"

  # 切换默认 Shell 为 Zsh
  info "切换默认 Shell 为 Zsh..."
  chsh -s "$(which zsh)" || error "切换 Shell 为 Zsh 失败！"

  # 执行 exec zsh，让当前 Bash 进程变为 Zsh
  info "安装完成，正在进入 Zsh..."
  info "p10k configure 命令可以自定义zsh样式的主题"
  exec zsh

elif [[ "$choice" == "2" ]]; then
  info "开始卸载 Zsh 和相关配置..."

  info "切换默认 Shell 回 Bash..."
  chsh -s "$(which bash)" || error "切换默认 Shell 失败！"

  info "删除 Oh My Zsh 和相关文件..."
  rm -rf "$OH_MY_ZSH_DIR"

  info "删除 Powerlevel10k 主题..."
  rm -rf "${ZSH_CUSTOM}/themes/powerlevel10k"

  info "删除 Zsh 插件..."
  rm -rf "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
  rm -rf "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"

  info "删除 Zsh 配置文件..."
  rm -f "$HOME/.zshrc" "$HOME/.p10k.zsh"

  info "卸载 Zsh..."
  apt remove --purge -y zsh || error "卸载 Zsh 失败！"

  info "清理无用的软件包..."
  apt autoremove -y && apt autoclean

  info "卸载完成！当前 Shell 已切换为 Bash。"
  bash
else
  error "无效的选项！退出。"
  exit 1
fi