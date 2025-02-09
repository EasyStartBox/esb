

> **可选：systemd 启动**  
> 例如在 `/etc/systemd/system/dns-api.service` 中写：
> ```ini
> [Unit]
> Description=DNS API Server
> After=network.target
>
> [Service]
> Type=simple
> ExecStart=/usr/bin/python3 /root/dns_api_server.py
> User=root
> Restart=on-failure
>
> [Install]
> WantedBy=multi-user.target
> ```
> 保存后 `systemctl daemon-reload && systemctl enable dns-api && systemctl start dns-api`。

---

### 一键脚本auto_cert_acme.sh
```bash
bash <(curl -sL https://raw.githubusercontent.com/EasyStartBox/esb/main/scripts/linux/cert_manager/auto_cert_acme.sh)
```
***
### 或一键脚本auto_cert_certbot.sh
```bash
bash <(curl -sL https://raw.githubusercontent.com/EasyStartBox/esb/main/scripts/linux/cert_manager/auto_cert_certbot.sh)
```
***