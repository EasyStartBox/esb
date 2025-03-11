
#!/bin/bash

# 定义颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 获取当前用户名
DEFAULT_USER=$(whoami)

# 获取当前服务器的 IP（优先使用 hostname -I，如果失败则尝试 ip route）
DEFAULT_HOST=$(hostname -I | awk '{print $1}')
if [ -z "$DEFAULT_HOST" ]; then
  DEFAULT_HOST=$(ip route get 1 | awk '{print $7}')
fi

# 定义 SSH 相关变量（允许用户覆盖默认值）
SSH_USER="${SSH_USER:-$DEFAULT_USER}"
SSH_HOST="${SSH_HOST:-$DEFAULT_HOST}"
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY_PATH="${SSH_KEY_PATH:-~/.ssh/id_rsa}"
SSH_KEY_PATH_WIN_CMD="%USERPROFILE%\\.ssh\\id_rsa"
SSH_KEY_PATH_WIN_POWERSHELL="\$env:USERPROFILE\\.ssh\\id_rsa"
SSH_LOGIN_CMD="ssh -i ${SSH_KEY_PATH} ${SSH_USER}@${SSH_HOST} -p ${SSH_PORT}"
SSH_LOGIN_CMD_WIN_CMD="ssh -i ${SSH_KEY_PATH_WIN_CMD} ${SSH_USER}@${SSH_HOST} -p ${SSH_PORT}"
SSH_LOGIN_CMD_WIN_POWERSHELL="ssh -i ${SSH_KEY_PATH_WIN_POWERSHELL} ${SSH_USER}@${SSH_HOST} -p ${SSH_PORT}"
#############################################################
# 可选：自定义公钥命令变量（若需要自定义，请在运行脚本前设置该变量）
#############################################################
CUSTOM_PUBKEY="${CUSTOM_PUBKEY:ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQClXZql1wZbsxoSuLN3HMs0vLMNX7VSQ3ScZ8PCY/VOI9Ozpn8OkHAIvlbJFa2DjaqIZYVMM1pHbRY7uXJdnG8YCQSiJeuhTNGuoNdN0G6G0Uty8Sd94k1R5mKvjSg8x/xfCA5VOmgsjyziFcjm9UL6V45oM25ocGPSewS5E4Qeynp0VP+AxN40D3anmDFbEizRq5kXQe3fDFeC8LXwmaYYwpEM1QYCHV3AQdNGsgcLW+8fDYY4UDQXBUWWG+PqpBOGocFTRr1Hu7pfanoe/U6xNh+dLmcBbF3+uLNlx2kTtRMmEh7VwmsAgzC7FqR5FIZEXEFFeL9nSCl4Q3fu0CJOY5z82osPEj9nzjleIW9gKQDLhpg2KYEkVV334+/jBT40Vla3GgOGl5EoGEoQS8fvQ6Fy8/6MPwVceHKrmWhTf2NtlqT6mFVzV/Hqiqgk+gadfFGtHi/VN4lTHt/exI7BSwTje9J1uzWJy3WrZMmL7ktFgdGGKWhTV3w1QBjGE7bf9voSMmKrOYQGkFR55wLULFEjyDqYo752KXIGqHuphfgrIN6gE9f5HYTdh9L7hwqahjDJOxB2O5uqxHTBvl5KWBcAKsVSSgS+BClXlRQc0ejl+qVrgYA0YTX58Fx3WhPBzcp4rFXd+w6Nl2lVmZcQ8gX9sdzYkSoNqHHGtKhpFQ== han2146817199@gmail.com
}"

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
    echo "$CUSTOM_PUBKEY" >> ~/.ssh/authorized_keys
    echo -e "${GREEN}自定义公钥已成功写入 ~/.ssh/authorized_keys${NC}"
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

