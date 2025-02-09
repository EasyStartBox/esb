#!/usr/bin/env python3
# dns_api_server.py
#
# 极简版，只实现 add_domain：
#   如果 IP 包含 ":"(判定为 IPv6)，则追加 AAAA 记录，否则追加 A 记录。
#   不更新 SOA 序列号，只做简单文本追加 + rndc reload。

import socketserver
import json
import subprocess
import os

ZONE_FILE = "/etc/bind/db.ns.washvoid.com"

class DNSRequestHandler(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            data = self.request.recv(4096).strip()
            request = json.loads(data.decode('utf-8'))
            action = request.get("action")
            if action == "add_domain":
                domain = request.get("domain")
                ip = request.get("ip")
                result, msg = add_domain_record(domain, ip)
                resp = {"status": "success" if result else "error", "message": msg}
            else:
                resp = {"status": "error", "message": "Invalid action"}
        except Exception as e:
            resp = {"status": "error", "message": str(e)}

        # 返回 JSON 给客户端
        self.request.sendall(json.dumps(resp, ensure_ascii=False).encode('utf-8'))

def add_domain_record(domain, ip):
    """
    追加一条 A 或 AAAA 记录到 ZONE_FILE 中（不更新SOA序列号），然后 rndc reload。
    """
    try:
        if not domain or not ip:
            return False, "域名或IP为空。"

        with open(ZONE_FILE, "r") as f:
            content = f.read()

        # 判断记录是否已存在
        check_str = domain + "."
        if check_str in content:
            return False, f"域名 {domain} 已存在。"

        # 判断 A / AAAA
        if ":" in ip:
            # IPv6
            record_line = f"{domain}.   IN  AAAA  {ip}"
        else:
            # IPv4
            record_line = f"{domain}.   IN  A     {ip}"

        # 直接拼接到文件尾部
        new_content = content.rstrip("\n") + "\n" + record_line + "\n"

        # 备份原文件
        backup_file = ZONE_FILE + ".bak"
        os.rename(ZONE_FILE, backup_file)

        with open(ZONE_FILE, "w") as f:
            f.write(new_content)

        # reload bind
        ret = subprocess.run(["rndc", "reload"], capture_output=True, text=True)
        if ret.returncode != 0:
            # 失败了就恢复备份
            os.rename(backup_file, ZONE_FILE)
            return False, f"rndc reload 失败: {ret.stderr}"

        return True, f"成功添加{'AAAA' if ':' in ip else 'A'}记录: {domain} -> {ip}"
    except Exception as e:
        return False, str(e)

if __name__ == "__main__":
    HOST, PORT = "", 5050
    with socketserver.TCPServer((HOST, PORT), DNSRequestHandler) as server:
        print(f"DNS API Server 正在端口 {PORT} 监听...")
        server.serve_forever()