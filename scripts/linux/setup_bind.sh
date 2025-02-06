#!/bin/bash
# ============================================================
# BIND 子域委派配置脚本
# 目标：将 Cloudflare 作为主域（例如 example.com）的权威 DNS，
#      同时将子域（例如 son.example.com 或 *.son.example.com）
#      委派给本机 BIND 服务器进行解析。
#
# 脚本功能：
#   1. 提醒用户脚本用途和注意事项
#   2. 检测所需命令（curl、dig、BIND 工具），若已安装询问是否重新安装，
#      否则询问是否自动安装
#   3. 交互式提示用户输入委派子域
#   4. 自动获取公网 IPv4/IPv6，并列出本机所有 IP 供用户选择
#   5. 根据选择生成 BIND 区域文件和添加区域配置（生成 A 或 AAAA 记录）
#   6. 检查配置并重启 BIND 服务
#   7. 给出 Cloudflare 配置及客户端测试提示，以及后续操作说明
#
# ============================================================

# ANSI 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查是否以 root 用户运行
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请以 root 用户运行此脚本！${NC}"
  exit 1
fi

# 选择操作：安装 BIND 或卸载 BIND
echo -e "${YELLOW}请选择操作：${NC}"
echo -e "${BLUE}1) 安装 BIND9 和相关工具${NC}"
echo -e "${BLUE}2) 卸载 BIND9 和相关工具${NC}"
read -rp "$(echo -e ${YELLOW}"请输入 1 或 2: ${NC}")" action

if [ "$action" == "1" ]; then
  # 安装 BIND9 和相关工具
  if [ ! -d "/etc/bind" ]; then
    echo -e "${RED}/etc/bind 目录不存在，BIND 似乎未正确安装！${NC}"
    read -rp "$(echo -e ${YELLOW}"是否自动安装 bind9 (及相关工具) ? (Y/n): ${NC}")" ans
    if [[ "$ans" =~ ^[Yy] ]]; then
      apt-get update
      apt-get install -y bind9 bind9utils bind9-doc dnsutils
    else
      echo -e "${RED}BIND 是必须的，退出脚本。${NC}"
      exit 1
    fi
  fi
  echo -e "${GREEN}BIND9 安装完成！${NC}"

elif [ "$action" == "2" ]; then
  # 卸载 BIND9 和相关工具
  read -rp "$(echo -e ${YELLOW}"你确定要卸载 BIND9 和相关工具吗？此操作不可逆！（Y/n）: ${NC}")" ans
  if [[ "$ans" =~ ^[Yy] ]]; then
    apt-get remove --purge -y bind9 bind9utils bind9-doc dnsutils
    apt-get autoremove -y
    apt-get clean
    echo -e "${GREEN}BIND9 和相关工具已成功卸载！${NC}"
  else
    echo -e "${RED}卸载操作已取消。${NC}"
  fi

else
  echo -e "${RED}无效选择，退出脚本。${NC}"
  exit 1
fi


# -------------------------------------------
# 函数：检查命令是否存在，若存在询问是否重新安装
# 参数1：命令名
# 参数2：对应的软件包名称（用于 apt 安装）
# -------------------------------------------
# check_command() {
#   local cmd=$1
#   local pkg=$2
#   if command -v "$cmd" >/dev/null 2>&1; then
#     echo -e "${GREEN}检测到命令 '$cmd' 已安装.${NC}"
#     read -rp "$(echo -e ${YELLOW}"是否重新安装 $pkg? (Y/n): ${NC}")" ans
#     if [[ "$ans" =~ ^[Yy] ]]; then
#       echo -e "${BLUE}正在重新安装 $pkg ...${NC}"
#       apt-get install --reinstall -y "$pkg"
#     fi
#   else
#     read -rp "$(echo -e ${YELLOW}"命令 '$cmd' 未安装，是否自动安装 $pkg? (Y/n): ${NC}")" ans
#     if [[ "$ans" =~ ^[Yy] ]]; then
#       echo -e "${BLUE}正在安装 $pkg ...${NC}"
#       apt-get install -y "$pkg"
#     else
#       echo -e "${RED}$cmd 是必须的，退出脚本。${NC}"
#       exit 1
#     fi
#   fi
# }

# -------------------------------------------
# 检查必需的命令
# -------------------------------------------
# echo -e "${GREEN}检测所需命令...${NC}"
# # check_command curl curl
# check_command dig dnsutils
# # 修正 named-checkconf 的检测路径和包名
# check_command /usr/sbin/named-checkconf bind9  # bind9 包含 named-checkconf
# check_command /usr/sbin/named-checkzone bind9  # 同样修正 named-checkzone

# # 检查 /etc/bind 目录是否存在，否则提示安装 bind9
# if [ ! -d "/etc/bind" ]; then
#   echo -e "${RED}/etc/bind 目录不存在，BIND 似乎未正确安装！${NC}"
#   read -rp "$(echo -e ${YELLOW}"是否自动安装 bind9 (及相关工具) ? (Y/n): ${NC}")" ans
#   if [[ "$ans" =~ ^[Yy] ]]; then
#     # 安装完整的 BIND 工具链
#     apt-get install -y bind9 bind9utils bind9-doc dnsutils
#   else
#     echo -e "${RED}BIND 是必须的，退出脚本。${NC}"
#     exit 1
#   fi
# fi

# -------------------------------------------
# 欢迎信息和用途说明
# -------------------------------------------
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}欢迎使用 BIND 子域委派自动配置脚本${NC}"
echo -e "${GREEN}本脚本用于将 Cloudflare 上主域的某个子域委派到本机 BIND 服务器${NC}"
echo -e "${GREEN}你可以使用此脚本配置例如：*.son.example.com${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""

# -------------------------------------------
# 1. 提示输入委派的子域
# -------------------------------------------
read -rp "$(echo -e ${YELLOW}"请输入你想委派的子域（例如：son.example.com，不含前缀*号）：${NC}")" DELEGATED_SUBDOMAIN

if [ -z "$DELEGATED_SUBDOMAIN" ]; then
  echo -e "${RED}输入为空，退出！${NC}"
  exit 1
fi

echo -e "${GREEN}你将委派的子域为：${DELEGATED_SUBDOMAIN}${NC}"
echo ""

# -------------------------------------------
# 2. 获取本机公网 IP 并列出本机所有 IP（IPv4 和 IPv6）
# -------------------------------------------
# 获取公网 IP，并加入错误处理
echo -e "${YELLOW}正在获取公网 IP...${NC}"
AUTO_IPV4=$(curl -s ipv4.ip.sb || echo "无法获取公网IPv4")
AUTO_IPV6=$(curl -s ipv6.ip.sb || echo "无法获取公网IPv6")

echo -e "${YELLOW}自动检测到的公网 IPv4：${AUTO_IPV4}${NC}"
echo -e "${YELLOW}自动检测到的公网 IPv6：${AUTO_IPV6}${NC}"
echo ""

# 选择 IP 类型时加入默认选项
echo -e "${YELLOW}请选择使用的 IP 类型：${NC}"
echo -e "${BLUE}1) IPv4${NC}"
echo -e "${BLUE}2) IPv6${NC}"
echo -e "${BLUE}3) 默认使用自动检测的 IP${NC}"
read -rp "$(echo -e ${YELLOW}"请输入 1 或 2 或 3: ${NC}")" ip_type

if [ "$ip_type" == "1" ]; then
  RECORD_TYPE="A"
  # 列出本机所有 IPv4 地址（非回环）
  echo -e "${YELLOW}本机 IPv4 地址列表：${NC}"
  ALL_IPV4=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  select chosen in $ALL_IPV4 "使用自动检测的公网 IPv4 ($AUTO_IPV4)"; do
    if [ -n "$chosen" ]; then
      if [[ "$chosen" == *"$AUTO_IPV4"* ]]; then
        SELECTED_IP="$AUTO_IPV4"
      else
        SELECTED_IP="$chosen"
      fi
      break
    else
      echo -e "${RED}无效选择，请重新选择！${NC}"
    fi
  done
elif [ "$ip_type" == "2" ]; then
  RECORD_TYPE="AAAA"
  # 列出本机所有 IPv6 地址（过滤回环和 link-local）
  echo -e "${YELLOW}本机 IPv6 地址列表：${NC}"
  ALL_IPV6=$(ip -6 addr show scope global | grep -oP '(?<=inet6\s)[0-9a-f:]+')
  select chosen in $ALL_IPV6 "使用自动检测的公网 IPv6 ($AUTO_IPV6)"; do
    if [ -n "$chosen" ]; then
      if [[ "$chosen" == *"$AUTO_IPV6"* ]]; then
        SELECTED_IP="$AUTO_IPV6"
      else
        SELECTED_IP="$chosen"
      fi
      break
    else
      echo -e "${RED}无效选择，请重新选择！${NC}"
    fi
  done
elif [ "$ip_type" == "3" ]; then
  # 使用自动检测的公网 IP 作为默认
  if [ -n "$AUTO_IPV4" ]; then
    SELECTED_IP="$AUTO_IPV4"
    RECORD_TYPE="A"
  elif [ -n "$AUTO_IPV6" ]; then
    SELECTED_IP="$AUTO_IPV6"
    RECORD_TYPE="AAAA"
  else
    echo -e "${RED}无法自动获取公网 IP，请手动选择 IP 类型。${NC}"
    exit 1
  fi
else
  echo -e "${RED}无效选择，退出脚本。${NC}"
  exit 1
fi

echo -e "${GREEN}将使用 IP: ${SELECTED_IP} (${RECORD_TYPE} 记录)${NC}"
echo ""

# -------------------------------------------
# 3. 配置 BIND 区域
# -------------------------------------------
ZONE_NAME="${DELEGATED_SUBDOMAIN}"   # 例如：son.example.com
ZONE_CONF="/etc/bind/named.conf.local"
ZONE_FILE="/etc/bind/db.${ZONE_NAME}"

echo -e "${YELLOW}[步骤 3] 正在添加委派子域 ${ZONE_NAME} 的 BIND 配置...${NC}"

# 添加区域配置到 named.conf.local（如果不存在则追加）
if ! grep -q "zone \"$ZONE_NAME\"" "$ZONE_CONF"; then
  cat << EOF >> "$ZONE_CONF"

zone "$ZONE_NAME" {
    type master;
    file "$ZONE_FILE";
};
EOF
  echo -e "${GREEN}已将区域配置添加到 ${ZONE_CONF}${NC}"
else
  echo -e "${BLUE}区域配置 ${ZONE_NAME} 已存在于 ${ZONE_CONF}${NC}"
fi

# 生成区域文件
echo -e "${YELLOW}[步骤 3] 正在生成区域文件 ${ZONE_FILE} ...${NC}"
cat > "$ZONE_FILE" << EOF
\$TTL 86400
@   IN  SOA   ns1.${ZONE_NAME}. admin.${ZONE_NAME}. (
            $(date +"%Y%m%d01") ; Serial（当前日期+序号，可自行递增）
            3600       ; Refresh
            1800       ; Retry
            604800     ; Expire
            86400      ; Minimum TTL
)
    IN  NS    ns1.${ZONE_NAME}.

; 定义 NS 服务器的 ${RECORD_TYPE} 记录
ns1.${ZONE_NAME}.   IN  ${RECORD_TYPE}   ${SELECTED_IP}

; 定义 *.${ZONE_NAME} 通配符解析
*.${ZONE_NAME}.   IN  ${RECORD_TYPE}   ${SELECTED_IP}

; 直接添加 test.${ZONE_NAME} 记录
test.${ZONE_NAME}.  IN  ${RECORD_TYPE}   ${SELECTED_IP}
EOF
echo -e "${GREEN}区域文件 ${ZONE_FILE} 创建完成！${NC}"
echo ""

# -------------------------------------------
# 4. 检查 BIND 配置并重启服务
# -------------------------------------------

echo -e "${YELLOW}[步骤 4] 正在检查 BIND 配置...${NC}"
if ! named-checkconf; then
  echo -e "${RED}BIND 配置文件有错误，请检查。${NC}"
  exit 1
fi

if ! named-checkzone "$ZONE_NAME" "$ZONE_FILE"; then
  echo -e "${RED}区域文件检查失败，请修正问题。${NC}"
  exit 1
fi

# 重启 BIND 服务
echo -e "${YELLOW}[步骤 4] 正在重启 BIND 服务...${NC}"
systemctl restart bind9
if systemctl status bind9 | grep -q "active (running)"; then
  echo -e "${GREEN}BIND 服务重启成功！${NC}"
else
  echo -e "${RED}BIND 服务重启失败，请检查 bind9 安装状态。${NC}"
  exit 1
fi

echo ""

# -------------------------------------------
# 5. 提示 Cloudflare 配置操作
# -------------------------------------------
echo -e "${BLUE}[提示] 请登录 Cloudflare 控制面板，对你的主域（例如 example.com）进行如下操作：${NC}"
echo -e "${BLUE}1) 添加 NS 记录，将子域 ${ZONE_NAME} 委派到你的 BIND 服务器：${NC}"
echo -e "${BLUE}      名称/主机：${ZONE_NAME} (或 _${ZONE_NAME}，视你的注册商而定)${NC}"
echo -e "${BLUE}      类型：NS${NC}"
echo -e "${BLUE}      值：ns1.${ZONE_NAME}.${NC}"
echo -e "${BLUE}2) 添加 ${RECORD_TYPE} 记录，确保 ns1.${ZONE_NAME} 指向 ${SELECTED_IP}${NC}"
echo ""
read -rp "$(echo -e ${YELLOW}"完成 Cloudflare 设置后，按回车继续测试解析...${NC}")" dummy

# -------------------------------------------
# 6. 提示客户端测试 DNS 解析
# -------------------------------------------
echo -e "${YELLOW}[步骤 6] 请在其他客户端（例如 Linux 或 Windows）使用 dig、nslookup 等工具测试解析${NC}"
echo -e "${YELLOW}建议测试命令示例：${NC}"
echo -e "${BLUE}  dig test.${ZONE_NAME} @8.8.8.8${NC}"
echo -e "${BLUE}  nslookup test.${ZONE_NAME} 8.8.8.8${NC}"
echo ""
echo -e "${YELLOW}本机 BIND 服务器上的测试（仅供参考）：${NC}"
echo -e "${BLUE}测试 test.${ZONE_NAME}:${NC}"
dig test.${ZONE_NAME} @"${SELECTED_IP}" +short
echo -e "${BLUE}测试 随机子域 random.${ZONE_NAME}:${NC}"
dig random.${ZONE_NAME} @"${SELECTED_IP}" +short
echo ""

# -------------------------------------------
# 7. 后续操作提示
# -------------------------------------------
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}BIND 子域委派配置已完成！${NC}"
echo -e "${GREEN}注意：${NC}"
echo -e "${GREEN}1. 你可以通过编辑 ${ZONE_FILE} 文件来添加更多记录，例如：${NC}"
echo -e "${GREEN}   new.${ZONE_NAME}.   IN  ${RECORD_TYPE}   <目标IP地址>${NC}"
echo -e "${GREEN}2. 修改配置后，记得递增 Serial 号，然后使用 'rndc reload' 或 'systemctl restart bind9' 使配置生效。${NC}"
echo -e "${GREEN}3. 常用的 BIND 管理命令：${NC}"
echo -e "${GREEN}   - 检查配置：named-checkconf${NC}"
echo -e "${GREEN}   - 检查区域：named-checkzone ${ZONE_NAME} ${ZONE_FILE}${NC}"
echo -e "${GREEN}   - 重启服务：systemctl restart bind9${NC}"
echo -e "${GREEN}============================================================${NC}"
