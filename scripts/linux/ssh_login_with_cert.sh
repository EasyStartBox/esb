
#!/bin/bash

# 定义颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 获取当前用户名
DEFAULT_USER=$(whoami)


########################################################################################开始获取所有本机ip

# 准备记录IP的关联数组（去重用）
declare -A seen_public_ipv4 seen_public_ipv6

# 用数组分别保存不同类型的IP
public_ipv4=()
public_ipv6=()
private_ipv4=()
private_ipv6=()

# 获取公网IPv4，使用curl超时参数避免卡住
echo "正在检测公网IPv4..."
for service in "ifconfig.me" "ip.sb" "ipinfo.io/ip" "api.ipify.org"; do
    ip=$(curl -s -m 5 "$service" 2>/dev/null || echo "")
    if [[ -n "$ip" && -z "${seen_public_ipv4[$ip]}" ]]; then
        public_ipv4+=("$ip")
        seen_public_ipv4["$ip"]=1
    fi
done
sleep 1
# 获取公网IPv6（需服务支持IPv6）
echo "正在检测公网IPv6..."
for service in "ifconfig.co" "ipv6.icanhazip.com"; do
    ip=$(curl -6 -s -m 5 "$service" 2>/dev/null || echo "")
    if [[ -n "$ip" && -z "${seen_public_ipv6[$ip]}" ]]; then
        public_ipv6+=("$ip")
        seen_public_ipv6["$ip"]=1
    fi
done

# 获取内网IPv4地址
echo "正在检测内网IPv4..."
while IFS= read -r line; do
    if [[ "$line" != "127.0.0.1" ]]; then
        private_ipv4+=("$line")
    fi
done < <(ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1)

# 获取内网IPv6地址
echo "正在检测内网IPv6..."
while IFS= read -r line; do
    # 排除回环地址（例如::1）
    if [[ "$line" != "::1" ]]; then
        private_ipv6+=("$line")
    fi
done < <(ip -o -6 addr show | awk '{print $4}' | cut -d/ -f1)

# 显示IP列表
echo "检测到的IP列表："
idx=1
ip_list=()

if [ ${#public_ipv4[@]} -gt 0 ]; then
    echo "公网IPv4:"
    for ip in "${public_ipv4[@]}"; do
        echo "  $idx) $ip"
        ip_list+=("$ip")
        ((idx++))
    done
fi

if [ ${#public_ipv6[@]} -gt 0 ]; then
    echo "公网IPv6:"
    for ip in "${public_ipv6[@]}"; do
        echo "  $idx) $ip"
        ip_list+=("$ip")
        ((idx++))
    done
fi

if [ ${#private_ipv4[@]} -gt 0 ]; then
    echo "内网IPv4:"
    for ip in "${private_ipv4[@]}"; do
        echo "  $idx) $ip"
        ip_list+=("$ip")
        ((idx++))
    done
fi

if [ ${#private_ipv6[@]} -gt 0 ]; then
    echo "内网IPv6:"
    for ip in "${private_ipv6[@]}"; do
        echo "  $idx) $ip"
        ip_list+=("$ip")
        ((idx++))
    done
fi





########################################################################################结束获取所有本机ip




# 设置默认IP为第一个公网IPv4
if [ ${#public_ipv4[@]} -gt 0 ]; then
    DEFAULT_HOST="${public_ipv4[0]}"
else
    DEFAULT_HOST=""
fi


# 定义 SSH 相关变量（允许用户覆盖默认值）
SSH_USER="${SSH_USER:-$DEFAULT_USER}"
SSH_HOST="${SSH_HOST:-$DEFAULT_HOST}"
# 获取当前 SSH 端口号（优先从 sshd_config 获取，若失败则默认为 22）
SSH_PORT=$(grep '^Port ' /etc/ssh/sshd_config | awk '{print $2}')
SSH_PORT="${SSH_PORT:-22}"

SSH_KEY_PATH="${SSH_KEY_PATH:-~/.ssh/id_rsa}"
SSH_KEY_PATH_WIN_CMD="%USERPROFILE%\\.ssh\\id_rsa"
SSH_KEY_PATH_WIN_POWERSHELL="\$env:USERPROFILE\\.ssh\\id_rsa"
SSH_LOGIN_CMD="ssh -i ${SSH_KEY_PATH} ${SSH_USER}@${SSH_HOST} -p ${SSH_PORT}"
SSH_LOGIN_CMD_WIN_CMD="ssh -i ${SSH_KEY_PATH_WIN_CMD} ${SSH_USER}@${SSH_HOST} -p ${SSH_PORT}"
SSH_LOGIN_CMD_WIN_POWERSHELL="ssh -i ${SSH_KEY_PATH_WIN_POWERSHELL} ${SSH_USER}@${SSH_HOST} -p ${SSH_PORT}"
#############################################################
# 必选：自定义公钥命令变量（若需要自定义，请在运行脚本前设置该变量）
#############################################################

CUSTOM_PUBKEY="${CUSTOM_PUBKEY:-ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQClXZql1wZbsxoSuLN3HMs0vLMNX7VSQ3ScZ8PCY/VOI9Ozpn8OkHAIvlbJFa2DjaqIZYVMM1pHbRY7uXJdnG8YCQSiJeuhTNGuoNdN0G6G0Uty8Sd94k1R5mKvjSg8x/xfCA5VOmgsjyziFcjm9UL6V45oM25ocGPSewS5E4Qeynp0VP+AxN40D3anmDFbEizRq5kXQe3fDFeC8LXwmaYYwpEM1QYCHV3AQdNGsgcLW+8fDYY4UDQXBUWWG+PqpBOGocFTRr1Hu7pfanoe/U6xNh+dLmcBbF3+uLNlx2kTtRMmEh7VwmsAgzC7FqR5FIZEXEFFeL9nSCl4Q3fu0CJOY5z82osPEj9nzjleIW9gKQDLhpg2KYEkVV334+/jBT40Vla3GgOGl5EoGEoQS8fvQ6Fy8/6MPwVceHKrmWhTf2NtlqT6mFVzV/Hqiqgk+gadfFGtHi/VN4lTHt/exI7BSwTje9J1uzWJy3WrZMmL7ktFgdGGKWhTV3w1QBjGE7bf9voSMmKrOYQGkFR55wLULFEjyDqYo752KXIGqHuphfgrIN6gE9f5HYTdh9L7hwqahjDJOxB2O5uqxHTBvl5KWBcAKsVSSgS+BClXlRQc0ejl+qVrgYA0YTX58Fx3WhPBzcp4rFXd+w6Nl2lVmZcQ8gX9sdzYkSoNqHHGtKhpFQ== han2146817199@gmail.com
}"
# 注意格式:CUSTOM_PUBKEY="${CUSTOM_PUBKEY:-ssh-rsa ...}"
# 检查是否以 root 用户运行
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请以 root 权限运行此脚本。${NC}"
  exit 1
fi

# 定义 SSH 配置文件路径
SSHD_CONFIG="/etc/ssh/sshd_config"

# 备份原 SSH 配置文件
if [ ! -f "${SSHD_CONFIG}.bak" ]; then
  cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"
  echo -e "${GREEN}已备份原 SSH 配置文件到 ${SSHD_CONFIG}.bak${NC}"
else
  echo -e "${YELLOW}备份已存在，跳过备份步骤。${NC}"
fi

# 启用密码登录和密钥登录
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' "$SSHD_CONFIG"
sed -i 's/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
sed -i 's/^#\?ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' "$SSHD_CONFIG"

# 限制登录失败尝试次数
if ! grep -q '^MaxAuthTries' "$SSHD_CONFIG"; then
  echo "MaxAuthTries 3" >> "$SSHD_CONFIG"
else
  sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 3/' "$SSHD_CONFIG"
fi

# 重启 SSH 服务
if systemctl restart sshd; then
  echo -e "${GREEN}SSH 服务已成功重启。${NC}"
  echo -e "${GREEN}配置已完成，服务器现在支持密码登录和密钥登录。${NC}"
  
  # 提示如何生成密钥
  echo -e "${BLUE}本地机输入以下命令生成密钥：${NC}"
  echo -e "${BLUE}ssh-keygen -t rsa -b 4096 -C \"your_email@example.com\"${NC}"
  echo -e "${BLUE}默认情况下，私钥保存为：~/.ssh/id_rsa，公钥为：~/.ssh/id_rsa.pub${NC}"



  # 若有自定义公钥命令，则自动写入 ~/.ssh/authorized_keys
  if [ -n "$CUSTOM_PUBKEY" ]; then
    mkdir -p ~/.ssh
    # 检查公钥是否已存在
    if ! grep -q "$CUSTOM_PUBKEY" ~/.ssh/authorized_keys; then
      echo "$CUSTOM_PUBKEY" >> ~/.ssh/authorized_keys
      echo -e "${GREEN}自定义公钥已成功写入 ~/.ssh/authorized_keys${NC}"
    else
      echo -e "${YELLOW}公钥已存在于 ~/.ssh/authorized_keys 中，跳过写入。${NC}"
    fi
  else
    # 提示如何将公钥写入服务器
    echo -e "${BLUE}将公钥 (~/.ssh/id_rsa.pub) 写入远程服务器的文件：${NC}"
    echo -e "${BLUE}~/.ssh/authorized_keys${NC}"
  fi


  # 提示如何使用密钥登录（自动填充当前用户和 IP）
  echo -e "${BLUE}本地使用以下命令通过密钥登录：${NC}"
  echo -e "${GREEN}${SSH_LOGIN_CMD}${NC}"
  echo -e "${BLUE}Windows本地使用以下命令通过密钥登录(CMD)：${NC}"
  echo -e "${GREEN}${SSH_LOGIN_CMD_WIN_CMD}${NC}"
  echo -e "${BLUE}Windows本地使用以下命令通过密钥登录(Powershell)：${NC}"
  echo -e "${GREEN}${SSH_LOGIN_CMD_WIN_POWERSHELL}${NC}"
  # 如果 Windows 客户端连接时出现警告，提示用户删除旧的主机密钥条目
  echo -e "${RED}注意: 如果在 Windows 上连接时出现如下警告：${NC}"
  echo -e "${RED}@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@${NC}"
  echo -e "${RED}@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @${NC}"
  echo -e "${RED}@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@${NC}"
  echo -e "${RED}IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!${NC}"
  echo -e "${RED}请使用命令 'ssh-keygen -R ${SSH_HOST}' 删除旧的主机密钥，然后再尝试连接。${NC}"

else
  echo -e "${RED}SSH 服务重启失败，请检查配置文件是否正确。${NC}"
  exit 1
fi

