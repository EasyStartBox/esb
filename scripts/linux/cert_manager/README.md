

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