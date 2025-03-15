#!/usr/bin/env python3
# dns_api_server.py - Enhanced DNS API Server
# 
# 功能扩展：
# 1. 添加域名 (add_domain) - A/AAAA记录
# 2. 删除域名 (delete_domain)
# 3. 更新域名 (update_domain)
# 4. 列出所有域名 (list_domains)
# 5. 自动更新SOA序列号
# 6. 日志记录和错误处理

import socketserver
import json
import subprocess
import os
import re
import logging
import time
import ipaddress
import threading
from datetime import datetime

# 配置
ZONE_FILE = "/etc/bind/db.uk.00-0.top"
BACKUP_DIR = "/var/backups/dns_api"
LOG_FILE = "/var/log/dns_api.log"
SOA_PATTERN = r'(\s+\d+\s*;\s*serial)'

# 设置日志
logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True

class DNSRequestHandler(socketserver.BaseRequestHandler):
    def handle(self):
        client_ip = self.client_address[0]
        logging.info(f"接收来自 {client_ip} 的连接")
        
        try:
            data = self.request.recv(4096).strip()
            if not data:
                logging.warning(f"从 {client_ip} 接收到空数据")
                return
                
            request = json.loads(data.decode('utf-8'))
            action = request.get("action")
            
            logging.info(f"从 {client_ip} 接收到动作: {action}")
            
            if action == "add_domain":
                domain = request.get("domain")
                ip = request.get("ip")
                result, msg = self._validate_and_execute(add_domain_record, domain, ip)
                resp = {"status": "success" if result else "error", "message": msg}
            
            elif action == "delete_domain":
                domain = request.get("domain")
                result, msg = self._validate_and_execute(delete_domain_record, domain)
                resp = {"status": "success" if result else "error", "message": msg}
                
            elif action == "update_domain":
                domain = request.get("domain")
                ip = request.get("ip")
                result, msg = self._validate_and_execute(update_domain_record, domain, ip)
                resp = {"status": "success" if result else "error", "message": msg}
                
            elif action == "list_domains":
                result, resp_data = list_domain_records()
                msg = "获取域名列表成功" if result else "获取域名列表失败"
                resp = {"status": "success" if result else "error", "message": msg}
                if result:
                    resp["domains"] = resp_data
            
            else:
                logging.warning(f"从 {client_ip} 接收到无效动作: {action}")
                resp = {"status": "error", "message": "无效的操作类型"}
                
        except json.JSONDecodeError:
            logging.error(f"从 {client_ip} 接收到无效的JSON数据")
            resp = {"status": "error", "message": "无效的JSON格式"}
            
        except Exception as e:
            logging.error(f"处理请求时发生错误: {str(e)}", exc_info=True)
            resp = {"status": "error", "message": f"服务器错误: {str(e)}"}
        
        # 返回响应
        try:
            self.request.sendall(json.dumps(resp, ensure_ascii=False).encode('utf-8'))
            logging.info(f"已发送响应到 {client_ip}: {resp.get('status')}")
        except Exception as e:
            logging.error(f"发送响应到 {client_ip} 时出错: {str(e)}")
    
    def _validate_and_execute(self, func, domain=None, ip=None):
        """验证输入参数并执行函数"""
        # 验证域名
        if domain is not None:
            if not re.match(r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$', domain):
                return False, "无效的域名格式"
        
        # 验证IP地址
        if ip is not None:
            try:
                ipaddress.ip_address(ip)
            except ValueError:
                return False, "无效的IP地址格式"
        
        # 执行函数
        if ip is not None:
            return func(domain, ip)
        else:
            return func(domain)

def ensure_backup_dir():
    """确保备份目录存在"""
    if not os.path.exists(BACKUP_DIR):
        os.makedirs(BACKUP_DIR)

def backup_zone_file():
    """备份区域文件"""
    ensure_backup_dir()
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = os.path.join(BACKUP_DIR, f"db.uk.00-0.top.{timestamp}")
    try:
        with open(ZONE_FILE, "r") as src, open(backup_path, "w") as dst:
            dst.write(src.read())
        logging.info(f"已创建区域文件备份: {backup_path}")
        return True
    except Exception as e:
        logging.error(f"备份区域文件失败: {str(e)}")
        return False

def update_soa_serial(content):
    """更新SOA序列号"""
    def replace_serial(match):
        serial_part = match.group(1).strip()
        old_serial = int(re.search(r'\d+', serial_part).group())
        
        # 使用当前日期作为序列号前缀 (YYYYMMDD)
        today = datetime.now().strftime("%Y%m%d")
        today_prefix = int(today) * 100
        
        # 如果当前序列号的前缀已经是今天的日期，则递增
        if old_serial >= today_prefix and old_serial < today_prefix + 99:
            new_serial = old_serial + 1
        else:
            new_serial = today_prefix + 1
            
        return f" {new_serial} ; serial"
    
    return re.sub(SOA_PATTERN, replace_serial, content)

def reload_bind():
    """重新加载BIND配置"""
    try:
        ret = subprocess.run(["rndc", "reload"], capture_output=True, text=True)
        if ret.returncode != 0:
            logging.error(f"rndc reload 失败: {ret.stderr}")
            return False, ret.stderr
        return True, "BIND配置已重新加载"
    except Exception as e:
        logging.error(f"执行rndc reload时出错: {str(e)}")
        return False, str(e)

def get_record_type(ip):
    """根据IP地址确定记录类型"""
    try:
        addr = ipaddress.ip_address(ip)
        return "AAAA" if isinstance(addr, ipaddress.IPv6Address) else "A"
    except ValueError:
        return "A"  # 默认返回A记录类型

def add_domain_record(domain, ip):
    """添加域名记录"""
    try:
        if not domain or not ip:
            return False, "域名或IP为空"
            
        # 备份区域文件
        if not backup_zone_file():
            return False, "无法备份区域文件"
            
        with open(ZONE_FILE, "r") as f:
            content = f.read()
            
        # 判断记录是否已存在
        check_str = f"{domain}."
        domain_regex = re.compile(rf"{re.escape(check_str)}\s+IN\s+[A|AAAA]")
        if domain_regex.search(content):
            return False, f"域名 {domain} 已存在"
            
        # 确定记录类型并创建记录行
        record_type = get_record_type(ip)
        record_line = f"{domain}.   IN  {record_type}     {ip}"
        
        # 更新SOA序列号
        content = update_soa_serial(content)
        
        # 追加记录
        new_content = content.rstrip("\n") + "\n" + record_line + "\n"
        
        # 写入文件
        with open(ZONE_FILE, "w") as f:
            f.write(new_content)
            
        # 重新加载BIND
        result, msg = reload_bind()
        if not result:
            # 恢复备份
            backup_zone_file()  # 先备份当前的错误文件
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            latest_backup = sorted([f for f in os.listdir(BACKUP_DIR) if f.startswith("db.uk.00-0.top")])[-2]
            os.system(f"cp {os.path.join(BACKUP_DIR, latest_backup)} {ZONE_FILE}")
            return False, f"重新加载BIND失败: {msg}"
            
        logging.info(f"已添加域名记录: {domain} -> {ip} ({record_type})")
        return True, f"成功添加{record_type}记录: {domain} -> {ip}"
        
    except Exception as e:
        logging.error(f"添加域名记录时出错: {str(e)}", exc_info=True)
        return False, f"添加域名记录时出错: {str(e)}"

def delete_domain_record(domain):
    """删除域名记录"""
    try:
        if not domain:
            return False, "域名为空"
            
        # 备份区域文件
        if not backup_zone_file():
            return False, "无法备份区域文件"
            
        with open(ZONE_FILE, "r") as f:
            content = f.readlines()
            
        # 查找并删除匹配的记录
        check_str = f"{domain}."
        domain_regex = re.compile(rf"{re.escape(check_str)}\s+IN\s+[A|AAAA]")
        
        found = False
        new_content = []
        for line in content:
            if domain_regex.search(line):
                found = True
                continue
            new_content.append(line)
            
        if not found:
            return False, f"域名 {domain} 不存在"
            
        # 更新SOA序列号
        new_content_str = "".join(new_content)
        new_content_str = update_soa_serial(new_content_str)
        
        # 写入文件
        with open(ZONE_FILE, "w") as f:
            f.write(new_content_str)
            
        # 重新加载BIND
        result, msg = reload_bind()
        if not result:
            # 恢复备份
            backup_zone_file()  # 先备份当前的错误文件
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            latest_backup = sorted([f for f in os.listdir(BACKUP_DIR) if f.startswith("db.uk.00-0.top")])[-2]
            os.system(f"cp {os.path.join(BACKUP_DIR, latest_backup)} {ZONE_FILE}")
            return False, f"重新加载BIND失败: {msg}"
            
        logging.info(f"已删除域名记录: {domain}")
        return True, f"成功删除域名记录: {domain}"
        
    except Exception as e:
        logging.error(f"删除域名记录时出错: {str(e)}", exc_info=True)
        return False, f"删除域名记录时出错: {str(e)}"

def update_domain_record(domain, ip):
    """更新域名记录"""
    try:
        if not domain or not ip:
            return False, "域名或IP为空"
            
        # 备份区域文件
        if not backup_zone_file():
            return False, "无法备份区域文件"
            
        with open(ZONE_FILE, "r") as f:
            content = f.readlines()
            
        # 确定记录类型
        record_type = get_record_type(ip)
        
        # 查找并更新匹配的记录
        check_str = f"{domain}."
        domain_regex = re.compile(rf"{re.escape(check_str)}\s+IN\s+[A|AAAA]")
        
        found = False
        new_content = []
        for line in content:
            if domain_regex.search(line):
                found = True
                new_line = f"{domain}.   IN  {record_type}     {ip}\n"
                new_content.append(new_line)
            else:
                new_content.append(line)
                
        if not found:
            return False, f"域名 {domain} 不存在"
            
        # 更新SOA序列号
        new_content_str = "".join(new_content)
        new_content_str = update_soa_serial(new_content_str)
        
        # 写入文件
        with open(ZONE_FILE, "w") as f:
            f.write(new_content_str)
            
        # 重新加载BIND
        result, msg = reload_bind()
        if not result:
            # 恢复备份
            backup_zone_file()  # 先备份当前的错误文件
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            latest_backup = sorted([f for f in os.listdir(BACKUP_DIR) if f.startswith("db.uk.00-0.top")])[-2]
            os.system(f"cp {os.path.join(BACKUP_DIR, latest_backup)} {ZONE_FILE}")
            return False, f"重新加载BIND失败: {msg}"
            
        logging.info(f"已更新域名记录: {domain} -> {ip} ({record_type})")
        return True, f"成功更新域名记录: {domain} -> {ip} ({record_type})"
        
    except Exception as e:
        logging.error(f"更新域名记录时出错: {str(e)}", exc_info=True)
        return False, f"更新域名记录时出错: {str(e)}"

def list_domain_records():
    """列出所有域名记录"""
    try:
        with open(ZONE_FILE, "r") as f:
            content = f.readlines()
            
        # 查找所有A和AAAA记录
        record_regex = re.compile(r'^([a-zA-Z0-9\-\.]+)\.\s+IN\s+(A|AAAA)\s+([0-9a-fA-F\.:]+)')
        
        domains = []
        for line in content:
            match = record_regex.search(line)
            if match:
                domain_name = match.group(1)
                record_type = match.group(2)
                ip_address = match.group(3)
                
                domains.append({
                    "domain": domain_name,
                    "type": record_type,
                    "ip": ip_address
                })
                
        logging.info(f"已获取域名列表，共 {len(domains)} 条记录")
        return True, domains
        
    except Exception as e:
        logging.error(f"获取域名列表时出错: {str(e)}", exc_info=True)
        return False, []

def check_zone_file_health():
    """检查区域文件健康状态"""
    try:
        # 使用named-checkzone检查区域文件
        zone_name = "uk.00-0.top"  # 假设这是区域名称
        ret = subprocess.run(["named-checkzone", zone_name, ZONE_FILE], 
                            capture_output=True, text=True)
        
        if ret.returncode != 0:
            logging.error(f"区域文件检查失败: {ret.stderr}")
            return False
            
        logging.info("区域文件检查通过")
        return True
    except Exception as e:
        logging.error(f"检查区域文件时出错: {str(e)}")
        return False

def perform_zone_file_cleanup():
    """清理过期的备份文件（保留最近30个）"""
    try:
        backup_files = sorted([os.path.join(BACKUP_DIR, f) 
                              for f in os.listdir(BACKUP_DIR) 
                              if f.startswith("db.uk.00-0.top")])
        
        # 保留最近30个备份
        files_to_delete = backup_files[:-30] if len(backup_files) > 30 else []
        
        for file_path in files_to_delete:
            os.remove(file_path)
            logging.info(f"已删除过期备份: {file_path}")
            
        return True
    except Exception as e:
        logging.error(f"清理备份文件时出错: {str(e)}")
        return False

def cleanup_thread():
    """执行定期清理任务的线程"""
    while True:
        try:
            # 每24小时执行一次清理
            time.sleep(24 * 60 * 60)
            perform_zone_file_cleanup()
        except Exception as e:
            logging.error(f"清理线程出错: {str(e)}")

def start_cleanup_thread():
    """启动清理线程"""
    thread = threading.Thread(target=cleanup_thread, daemon=True)
    thread.start()
    logging.info("清理线程已启动")

if __name__ == "__main__":
    # 确保备份目录存在
    ensure_backup_dir()
    
    # 检查区域文件健康状态
    if not check_zone_file_health():
        logging.error("区域文件检查失败，服务退出")
        exit(1)
    
    # 启动清理线程
    start_cleanup_thread()
    
    # 启动服务器
    HOST, PORT = "", 5050
    
    try:
        with ThreadedTCPServer((HOST, PORT), DNSRequestHandler) as server:
            logging.info(f"DNS API Server 正在端口 {PORT} 监听...")
            print(f"DNS API Server 正在端口 {PORT} 监听...")
            server.serve_forever()
    except KeyboardInterrupt:
        logging.info("服务器正在关闭...")
        print("服务器正在关闭...")
    except Exception as e:
        logging.critical(f"服务器启动或运行时发生错误: {str(e)}", exc_info=True)
        print(f"服务器启动或运行时发生错误: {str(e)}")