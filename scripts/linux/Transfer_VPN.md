# **🚀 公网服务器中转内网 VPN（WireGuard）完整教程**  
## **📌 目标**  
1. **公网服务器**（Linux, Docker）仅作为 VPN **中转节点**，不影响自身网络。  
2. **内网服务器**（Windows）通过 VPN 连接公网服务器，**对外提供访问**。  
3. **外部客户端**（Windows/手机）连接 VPN 后，可访问**内网服务器**资源。  

---

## **🛠️ 1. 公网服务器（Docker 部署 WireGuard）**
### **✅ 1.1 安装 Docker 和 Docker Compose**
```bash
# 安装 Docker
curl -fsSL https://get.docker.com | bash

# 安装 Docker Compose
apt install docker-compose -y
```

### **✅ 1.2 创建 WireGuard 配置**
```bash
mkdir -p /opt/wireguard && cd /opt/wireguard
nano docker-compose.yml
```
#### **🔹 配置 `docker-compose.yml`（使用 `host` 模式）**
```yaml
version: '3'
services:
  wireguard:
    image: lscr.io/linuxserver/wireguard
    container_name: wireguard-server
    network_mode: "host"  # ✅ 直接使用宿主机网络
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
      - SERVERPORT=51820
      - PEERS=2  # 1个内网服务器（Windows）+ 1个外部客户端
      - ALLOWEDIPS=0.0.0.0/0
    volumes:
      - ./config:/config
      - /lib/modules:/lib/modules
    sysctls:
      - net.ipv4.ip_forward=1
    restart: unless-stopped
```

### **✅ 1.3 启动 WireGuard**
```bash
docker-compose up -d
```

### **✅ 1.4 开启 IP 转发**
```bash
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -w net.ipv4.ip_forward=1
```
持久生效：
```bash
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p
```

### **✅ 1.5 防火墙放行 VPN 端口**
```bash
sudo iptables -I INPUT -p udp --dport 51820 -j ACCEPT
sudo iptables-save > /etc/iptables/rules.v4
```
如果使用 `firewalld`：
```bash
sudo firewall-cmd --add-port=51820/udp --permanent
sudo firewall-cmd --reload
```

### **✅ 1.6 获取客户端配置**
```bash
ls config/peer*
cat config/peer1/peer1.conf
```
**示例 `peer1.conf`（给内网 Windows 服务器）**：
```ini
[Interface]
Address = 10.0.0.2/24
PrivateKey = xxxxxxxxxxxxxxxxxxxxxxxxxxxxx
DNS = 8.8.8.8

[Peer]
PublicKey = xxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Endpoint = <公网服务器IP>:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```
**示例 `peer2.conf`（给外部客户端）**：
```ini
[Interface]
Address = 10.0.0.3/24
PrivateKey = yyyyyyyyyyyyyyyyyyyyyyyyyyyyy
DNS = 8.8.8.8

[Peer]
PublicKey = xxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Endpoint = <公网服务器IP>:51820
AllowedIPs = 10.0.0.2/32
PersistentKeepalive = 25
```
💾 **将 `peer1.conf` 复制到内网 Windows，`peer2.conf` 复制到外部客户端**。

---

## **🖥️ 2. 内网 Windows 服务器（连接 VPN）**
### **✅ 2.1 下载并安装 WireGuard**
📥 [WireGuard for Windows](https://www.wireguard.com/install/)

### **✅ 2.2 导入 `peer1.conf` 并连接**
1. **打开 WireGuard**，点击 "Add Tunnel" > "Import from File"。  
2. 选择 `peer1.conf`，点击 "Activate" 启动 VPN。  
3. 检查 VPN 是否连接，运行：
   ```powershell
   ipconfig /all
   ```
   确保 `10.0.0.2` 出现在网络适配器列表。

---

## **📱 3. 外部客户端（访问内网服务器）**
### **✅ 3.1 安装 WireGuard**
- **Windows/Mac**：[WireGuard 官网](https://www.wireguard.com/install/)  
- **Android/iOS**：[Google Play / App Store 下载 WireGuard]  

### **✅ 3.2 导入 `peer2.conf` 并连接**
1. **打开 WireGuard**，点击 "Add Tunnel" > "Import from File"。  
2. 选择 `peer2.conf`，点击 "Activate" 连接 VPN。  
3. 连接后，尝试 `ping 10.0.0.2`，如果成功，表示已访问内网 Windows 服务器！🎉

---

## **🎯 4. 测试和故障排除**
### **✅ 4.1 测试连接**
```bash
ping 10.0.0.2  # 外部客户端 → 内网 Windows
ping 10.0.0.3  # 内网 Windows → 外部客户端
```

### **✅ 4.2 WireGuard 日志**
```bash
docker logs wireguard-server
```

### **✅ 4.3 检查 VPN 连接状态**
```bash
wg show
```

### **✅ 4.4 常见问题**
#### **🔸 外部客户端无法连接？**
- 确保公网服务器 `51820/udp` 端口已开放：
  ```bash
  sudo netstat -tulnp | grep 51820
  ```
- 如果没有监听，尝试重启：
  ```bash
  docker-compose restart
  ```
- 检查防火墙：
  ```bash
  sudo iptables -L -n | grep 51820
  ```

#### **🔸 内网 Windows 服务器连上 VPN 但外部客户端无法访问？**
- 在 Windows 上**关闭防火墙**（或者允许 WireGuard 网段 `10.0.0.0/24`）。
- 确保 WireGuard 服务器 `AllowedIPs = 10.0.0.2/32`。

---

## **🎉 总结**
| 角色             | 配置方式 |
|-----------------|---------|
| **公网服务器**（Docker）| 运行 WireGuard，转发 VPN 流量，`network_mode: "host"` |
| **内网服务器**（Windows） | 安装 WireGuard，连接 VPN，提供服务 |
| **外部客户端** | 连接 WireGuard VPN，访问 `10.0.0.2`（内网服务器） |

💡 **这样，你的公网服务器不会暴露内网，外部客户端可以通过 VPN 访问内网服务器！** 🚀🚀🚀