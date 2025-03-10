

# **已弃用(2025-03-10暂时保留在这)**
# **采用frp(直接经过公网服务器或xtcp与socat配合的UoT点对点)或基于wireguard的netbird和tailscale点对点更好**

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
    network_mode: "host"
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
      - SERVERURL=auto                # 自动检测服务器公网IP或指定具体IP
      - SERVERPORT=51820              # WireGuard监听端口
      - INTERNAL_SUBNET=10.0.0.0/24   # 设置内部子网
      - PEERS=2                       # 配置2个客户端
      - PEERDNS=auto                  # 可以指定为10.0.0.1或其他DNS服务器
      - ALLOWEDIPS=0.0.0.0/0          # 允许客户端访问的IP范围
    volumes:
      - ./config:/config
      - /lib/modules:/lib/modules
    sysctls:
      - net.ipv4.ip_forward=1         # 开启IP转发
      - net.ipv4.conf.all.src_valid_mark=1
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



### **🚀 1.7 重新部署 WireGuard**
1. **删除旧容器**
   ```bash
   docker-compose down
   ```

2. **重新启动 WireGuard**
   ```bash
   docker-compose up -d
   ```

3. **检查服务器 IP 是否更新**
   ```bash
   cat /opt/wireguard/config/wg_confs/wg0.conf
   ```
   应该看到：
   ```ini
   [Interface]
   Address = 10.0.0.1
   ```

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




























是的，在 **Docker** 里运行 WireGuard **可以减少防火墙配置**，因为 Docker 会自动管理 **iptables 规则**，但仍需正确配置 **端口转发** 和 **网络模式**。

---

## **Docker 部署 WireGuard 作为中转服务器**
### **1. 安装 Docker 和 WireGuard**
在 **服务器 S** 上：
```sh
apt update && apt install docker.io -y
```

安装 `wireguard-tools`：
```sh
apt install wireguard-tools -y
```

---

### **2. 运行 WireGuard 容器**
推荐使用 [`linuxserver/wireguard`](https://hub.docker.com/r/linuxserver/wireguard) 镜像：
```sh
docker run -d \
  --name=wireguard \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  -e PUID=1000 -e PGID=1000 \
  -e TZ=Asia/Shanghai \
  -e SERVERPORT=51820 \
  -p 51820:51820/udp \
  -v /path/to/config:/config \
  --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
  --restart unless-stopped \
  lscr.io/linuxserver/wireguard:latest
```

**说明**
- `-p 51820:51820/udp`：**无需额外防火墙规则**，Docker 自动处理端口映射。
- `--cap-add=NET_ADMIN`：允许容器管理网络。
- `--sysctl="net.ipv4.conf.all.src_valid_mark=1"`：支持 NAT 转发。

---

### **3. 配置 WireGuard**
#### **生成密钥**
```sh
docker exec -it wireguard bash
wg genkey | tee /config/privatekey | wg pubkey > /config/publickey
```
- `cat /config/privatekey` → **服务器私钥**
- `cat /config/publickey` → **服务器公钥**

#### **编辑 `/etc/wireguard/wg0.conf`**
```ini
[Interface]
PrivateKey = 服务器私钥
Address = 10.100.100.1/24
ListenPort = 51820

[Peer]
PublicKey = A 的公钥
AllowedIPs = 10.100.100.2/32

[Peer]
PublicKey = B 的公钥
AllowedIPs = 10.100.100.3/32
```
**重启容器**
```sh
docker restart wireguard
```

---

### **4. 客户端 A、B 配置**
#### **`wg0.conf` 示例**
```ini
[Interface]
PrivateKey = 客户端私钥
Address = 10.100.100.2/24

[Peer]
PublicKey = 服务器公钥
Endpoint = x.x.x.x:51820
AllowedIPs = 10.100.100.0/24
PersistentKeepalive = 25
```
然后启动：
```sh
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0
```

---

## **5. Docker 方式下防火墙的优化**
**优势**
- **无需手动配置 `iptables` 规则**，Docker **自动管理端口映射**。
- **简化 `sysctl` 配置**，Docker 处理 `net.ipv4.ip_forward`。

**可能的调整**
如果 **宿主机防火墙开启了 UFW**，执行：
```sh
ufw allow 51820/udp
```
如果仍然无法通信，可尝试：
```sh
ufw disable
systemctl restart docker
```

---

## **6. 测试连通性**
在 **客户端 A** 运行：
```sh
ping 10.100.100.3
```
在 **客户端 B** 运行：
```sh
ping 10.100.100.2
```
如果通了，就表示 Docker 方式的 WireGuard 中转成功！🚀