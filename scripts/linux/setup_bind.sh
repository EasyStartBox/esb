#!/bin/bash
# ============================================================
# BIND 子域委派配置脚本
# 目标：将 Cloudflare 作为主域（例如 example.com）的权威 DNS，
#      同时将子域（例如 son.example.com 或 *.son.example.com）
#      委派给本机 BIND 服务器进行解析。
#
# 脚本会：
#   1. 提醒用户脚本用途和注意事项
#   2. 交互式提示用户输入委派子域
#   3. 自动获取本机公网 IP（或让用户手动输入）
#   4. 生成 BIND 区域文件和添加区域配置
#   5. 检查配置并重启 BIND 服务
#   6. 给出 Cloudflare 配置及测试提示
#   7. 演示如何添加新的 A 记录及后续操作提示
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

# 欢迎和说明
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}欢迎使用 BIND 子域委派自动配置脚本${NC}"
echo -e "${GREEN}本脚本用于将 Cloudflare 上主域的某个子域委派到本机 BIND服务器${NC}"
echo -e "${GREEN}你可以使用此脚本配置例如：*.son.example.com${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""

##############################################
# 1. 提示输入委派的子域
##############################################
read -rp "$(echo -e ${YELLOW}"请输入你想委派的子域（例如：son.example.com，不含前缀*号）：${NC}")" DELEGATED_SUBDOMAIN

if [ -z "$DELEGATED_SUBDOMAIN" ]; then
  echo -e "${RED}输入为空，退出！${NC}"
  exit 1
fi

echo -e "${GREEN}你将委派的子域为：${DELEGATED_SUBDOMAIN}${NC}"
echo ""

##############################################
# 2. 获取本机公网 IP（默认用当前 IP）
##############################################
# 检查 curl 命令是否存在
if ! command -v curl >/dev/null 2>&1; then
  echo -e "${RED}未安装 curl，请先安装 curl，再运行脚本！${NC}"
  exit 1
fi

# 自动获取公网 IP（例如：ifconfig.me 或 ipinfo.io）
AUTO_IP=$(curl -s ifconfig.me)
echo -e "${YELLOW}检测到的本机公网 IP 为：${AUTO_IP}${NC}"
read -rp "$(echo -e ${YELLOW}"是否使用该 IP？(Y/n): ${NC}")" USE_AUTO

if [[ "$USE_AUTO" =~ ^[Nn] ]]; then
  read -rp "$(echo -e ${YELLOW}"请输入你希望使用的 IP 地址: ${NC}")" MANUAL_IP
  if [ -z "$MANUAL_IP" ]; then
    echo -e "${RED}未输入 IP 地址，退出！${NC}"
    exit 1
  fi
  SERVER_IP="$MANUAL_IP"
else
  SERVER_IP="$AUTO_IP"
fi

echo -e "${GREEN}将使用 IP: ${SERVER_IP}${NC}"
echo ""

##############################################
# 3. 配置 BIND 区域
##############################################
# 定义相关变量
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

; 定义 NS 服务器的 A 记录
ns1.${ZONE_NAME}.   IN  A   ${SERVER_IP}

; 定义 *.${ZONE_NAME} 通配符解析
*.${ZONE_NAME}.   IN  A   ${SERVER_IP}

; 直接添加 test.${ZONE_NAME} 记录
test.${ZONE_NAME}.  IN  A   ${SERVER_IP}
EOF
echo -e "${GREEN}区域文件 ${ZONE_FILE} 创建完成！${NC}"
echo ""

##############################################
# 4. 检查 BIND 配置并重启服务
##############################################
echo -e "${YELLOW}[步骤 4] 正在检查 BIND 配置...${NC}"
named-checkconf
named-checkzone "$ZONE_NAME" "$ZONE_FILE"

echo -e "${YELLOW}[步骤 4] 正在重启 BIND 服务...${NC}"
systemctl restart bind9
echo -e "${GREEN}BIND 服务重启成功！${NC}"
echo ""

##############################################
# 5. 提示 Cloudflare 配置操作
##############################################
echo -e "${BLUE}[提示] 请登录 Cloudflare 控制面板，对你的主域（例如 example.com）进行如下操作：${NC}"
echo -e "${BLUE}1) 添加 NS 记录，将子域 ${ZONE_NAME} 委派到你的 BIND 服务器：${NC}"
echo -e "${BLUE}      名称/主机：${ZONE_NAME}  (或 _${ZONE_NAME}，视你的注册商而定)${NC}"
echo -e "${BLUE}      类型：NS${NC}"
echo -e "${BLUE}      值：ns1.${ZONE_NAME}.${NC}"
echo -e "${BLUE}2) 添加 A 记录，确保 ns1.${ZONE_NAME} 指向 ${SERVER_IP}${NC}"
echo ""
read -rp "$(echo -e ${YELLOW}"完成 Cloudflare 设置后，按回车继续测试解析...${NC}")" dummy

##############################################
# 6. 测试 DNS 解析
##############################################
# 检查是否安装 dig
if ! command -v dig >/dev/null 2>&1; then
  echo -e "${RED}未检测到 dig 命令，请在 Linux 上使用 'apt install dnsutils' 安装，或在 Windows 上使用相应工具。${NC}"
else
  echo -e "${YELLOW}[步骤 6] 测试本机解析 (使用本机 BIND 服务 IP ${SERVER_IP})...${NC}"
  echo -e "${BLUE}测试 test.${ZONE_NAME}:${NC}"
  dig test.${ZONE_NAME} @"${SERVER_IP}" +short
  echo -e "${BLUE}测试 随机子域 random.${ZONE_NAME}:${NC}"
  dig random.${ZONE_NAME} @"${SERVER_IP}" +short
fi
echo ""

##############################################
# 7. 后续操作提示
##############################################
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}BIND 子域委派配置已完成！${NC}"
echo -e "${GREEN}注意：${NC}"
echo -e "${GREEN}1. 你可以通过编辑 ${ZONE_FILE} 文件来添加更多 A 记录，例如：${NC}"
echo -e "${GREEN}   new.${ZONE_NAME}.   IN  A   <目标IP地址>${NC}"
echo -e "${GREEN}2. 配置修改后，记得递增 Serial 号，然后使用 'rndc reload' 或 'systemctl restart bind9' 使配置生效。${NC}"
echo -e "${GREEN}3. 常用的 BIND 管理命令：${NC}"
echo -e "${GREEN}   - 检查配置：named-checkconf${NC}"
echo -e "${GREEN}   - 检查区域：named-checkzone ${ZONE_NAME} ${ZONE_FILE}${NC}"
echo -e "${GREEN}   - 重启服务：systemctl restart bind9${NC}"
echo -e "${GREEN}============================================================${NC}"
