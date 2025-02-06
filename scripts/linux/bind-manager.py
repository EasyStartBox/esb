#!/usr/bin/env python3
import curses
import os
import re

# BIND 相关路径及区域文件名前缀
BIND_DIR = "/etc/bind"
ZONE_FILE_PREFIX = "db."

def get_zone_files():
    """扫描 BIND 目录，返回所有以 db. 开头的区域文件名列表"""
    files = []
    try:
        for f in os.listdir(BIND_DIR):
            if f.startswith(ZONE_FILE_PREFIX) and os.path.isfile(os.path.join(BIND_DIR, f)):
                files.append(f)
    except Exception as e:
        pass
    return sorted(files)

def get_zone_name_from_file(file):
    """从区域文件名中提取区域名（去除前缀 db.）"""
    return file[len(ZONE_FILE_PREFIX):]

def load_zone_file(zone_file):
    """读取区域文件内容，返回文件各行组成的列表"""
    path = os.path.join(BIND_DIR, zone_file)
    with open(path, "r") as f:
        lines = f.readlines()
    return lines

def write_zone_file(zone_file, lines):
    """将更新后的内容写入区域文件"""
    path = os.path.join(BIND_DIR, zone_file)
    with open(path, "w") as f:
        f.writelines(lines)

def parse_records(lines):
    """
    解析区域文件中“记录”行（不包括 SOA、$TTL、注释等）
    返回列表，每项为字典：{'line_index': 行号, 'name':, 'type':, 'value':, 'full_line': 原始行}
    """
    records = []
    # 简单正则匹配：行首非空字段，然后 "IN" ，再一个字段（类型）和后面的内容（值）
    record_pattern = re.compile(r'^\s*(\S+)\s+IN\s+(\S+)\s+(.+)$')
    for i, line in enumerate(lines):
        s = line.strip()
        if not s:
            continue
        # 跳过以 $ 或 ; 开头的行，以及包含 SOA 的行（忽略 SOA 记录）
        if s.startswith("$") or s.startswith(";") or "SOA" in s:
            continue
        m = record_pattern.match(line)
        if m:
            name, rtype, value = m.groups()
            # 如有注释，则只取分号前的部分
            value = value.split(";")[0].strip()
            records.append({
                'line_index': i,
                'name': name,
                'type': rtype,
                'value': value,
                'full_line': line
            })
    return records

def menu(stdscr, title, options):
    """
    通用菜单界面，返回选中选项的索引。
    使用上下箭头选择，回车确认，ESC 退出（返回 None）
    """
    curses.curs_set(0)
    current = 0
    while True:
        stdscr.clear()
        stdscr.addstr(0, 0, title, curses.A_BOLD)
        h, w = stdscr.getmaxyx()
        for idx, option in enumerate(options):
            y = idx + 2
            if y >= h - 1:
                break
            if idx == current:
                stdscr.addstr(y, 2, option, curses.A_REVERSE)
            else:
                stdscr.addstr(y, 2, option)
        stdscr.refresh()
        key = stdscr.getch()
        if key == curses.KEY_UP:
            current = (current - 1) % len(options)
        elif key == curses.KEY_DOWN:
            current = (current + 1) % len(options)
        elif key in (10, 13):  # Enter 键
            return current
        elif key == 27:  # ESC
            return None

def form_input(stdscr, title, fields):
    """
    简单表单处理函数，fields 为字段列表，每个字段为字典：
      { 'label': 显示标签, 'value': 当前内容, 'row': 行号, 'col': 列号, 'width': 输入框宽度 }
    使用上下方向键切换，Enter 保存，ESC 取消。
    返回各字段的输入值列表（按字段顺序），若取消则返回 None。
    """
    curses.curs_set(1)
    current_field = 0
    while True:
        stdscr.clear()
        stdscr.addstr(0, 0, title, curses.A_BOLD)
        for idx, field in enumerate(fields):
            label = field['label'] + ": "
            stdscr.addstr(field['row'], field['col'] - len(label), label)
            text = field['value']
            if idx == current_field:
                stdscr.attron(curses.A_REVERSE)
                stdscr.addstr(field['row'], field['col'], text.ljust(field['width']))
                stdscr.attroff(curses.A_REVERSE)
                stdscr.move(field['row'], field['col'] + len(text))
            else:
                stdscr.addstr(field['row'], field['col'], text.ljust(field['width']))
        stdscr.refresh()
        key = stdscr.getch()
        if key in (10, 13):  # Enter 键：返回所有字段的值
            return [f['value'] for f in fields]
        elif key == 27:  # ESC 取消
            return None
        elif key == curses.KEY_UP:
            current_field = (current_field - 1) % len(fields)
        elif key == curses.KEY_DOWN:
            current_field = (current_field + 1) % len(fields)
        elif key in (curses.KEY_BACKSPACE, 127, 8):
            if fields[current_field]['value']:
                fields[current_field]['value'] = fields[current_field]['value'][:-1]
        elif 32 <= key <= 126:
            ch = chr(key)
            if len(fields[current_field]['value']) < fields[current_field]['width']:
                fields[current_field]['value'] += ch

def add_record(stdscr, zone_file, lines):
    """新增记录：调用表单输入，生成记录行并追加到文件末尾"""
    title = "【新增记录】请输入记录数据 (ESC 取消)"
    fields = [
        {'label': 'Name', 'value': '', 'row': 2, 'col': 15, 'width': 30},
        {'label': 'Type', 'value': '', 'row': 4, 'col': 15, 'width': 10},
        {'label': 'Value', 'value': '', 'row': 6, 'col': 15, 'width': 30},
    ]
    result = form_input(stdscr, title, fields)
    if result:
        name, rtype, value = result
        new_line = f"{name}\tIN\t{rtype}\t{value}\n"
        lines.append(new_line)
        write_zone_file(zone_file, lines)
        return True
    return False

def modify_record(stdscr, zone_file, lines, record):
    """修改记录：预填原记录数据，编辑后更新该行内容"""
    title = "【修改记录】编辑数据 (ESC 取消)"
    fields = [
        {'label': 'Name', 'value': record['name'], 'row': 2, 'col': 15, 'width': 30},
        {'label': 'Type', 'value': record['type'], 'row': 4, 'col': 15, 'width': 10},
        {'label': 'Value', 'value': record['value'], 'row': 6, 'col': 15, 'width': 30},
    ]
    result = form_input(stdscr, title, fields)
    if result:
        name, rtype, value = result
        new_line = f"{name}\tIN\t{rtype}\t{value}\n"
        lines[record['line_index']] = new_line
        write_zone_file(zone_file, lines)
        return True
    return False

def delete_record(stdscr, zone_file, lines, record):
    """删除记录：确认后删除对应行"""
    stdscr.clear()
    prompt = f"确认删除记录: {record['name']} IN {record['type']} {record['value']} ? (y/n)"
    stdscr.addstr(0, 0, prompt, curses.A_BOLD)
    stdscr.refresh()
    while True:
        key = stdscr.getch()
        if key in (ord('y'), ord('Y')):
            del lines[record['line_index']]
            write_zone_file(zone_file, lines)
            return True
        elif key in (ord('n'), ord('N'), 27):
            return False

def manage_zone(stdscr, zone_file):
    """
    管理指定区域文件：
      - 先读取文件内容并解析记录（扫描记录行，不使用绝对文件名做管理）
      - 显示菜单：第一行为“新增记录”，后续每一行展示记录的“名称 IN 类型 值”
      - 选择记录后进入子菜单（修改/删除）
    """
    while True:
        lines = load_zone_file(zone_file)
        records = parse_records(lines)
        menu_options = ["【新增记录】"]
        for rec in records:
            menu_options.append(f"{rec['name']} IN {rec['type']} {rec['value']}")
        menu_options.append("返回上级")
        title = f"管理区域：{get_zone_name_from_file(zone_file)}"
        choice = menu(stdscr, title, menu_options)
        if choice is None or choice == len(menu_options)-1:
            break
        elif choice == 0:
            # 新增记录
            add_record(stdscr, zone_file, lines)
        else:
            # 选择的记录（注意：菜单第一项是新增，所以记录列表索引为 choice-1）
            record = records[choice-1]
            sub_options = ["修改记录", "删除记录", "返回"]
            sub_title = f"记录：{record['name']} IN {record['type']} {record['value']}"
            sub_choice = menu(stdscr, sub_title, sub_options)
            if sub_choice == 0:
                modify_record(stdscr, zone_file, lines, record)
            elif sub_choice == 1:
                delete_record(stdscr, zone_file, lines, record)
            # 返回时自动刷新区域文件内容

def main(stdscr):
    """主程序：先扫描所有区域文件，显示区域列表，选择后进入记录管理界面"""
    curses.use_default_colors()
    while True:
        zone_files = get_zone_files()
        if not zone_files:
            stdscr.clear()
            stdscr.addstr(0,0,"未找到任何区域文件于 /etc/bind 下，按任意键退出。")
            stdscr.refresh()
            stdscr.getch()
            break
        menu_options = [get_zone_name_from_file(zf) for zf in zone_files]
        menu_options.append("退出")
        title = "请选择要管理的区域（扫描 /etc/bind 中的 db.* 文件）"
        choice = menu(stdscr, title, menu_options)
        if choice is None or choice == len(menu_options)-1:
            break
        selected_zone_file = zone_files[choice]
        manage_zone(stdscr, selected_zone_file)

if __name__ == "__main__":
    curses.wrapper(main)








###########################
# 实现2
###########################

# #!/usr/bin/env python3
# import curses
# import re
# import os
# import subprocess
# from datetime import datetime

# BIND_DIR = "/etc/bind"
# NAMED_CONF_LOCAL = os.path.join(BIND_DIR, "named.conf.local")

# def parse_zones():
#     zones = []
#     with open(NAMED_CONF_LOCAL, 'r') as f:
#         content = f.read()
#         # 使用正则匹配zone定义
#         pattern = r'zone\s+"(.*?)"\s*{\s*type\s+master;\s*file\s+"(.*?)";'
#         matches = re.findall(pattern, content, re.DOTALL)
#         for domain, file_path in matches:
#             if not os.path.isabs(file_path):
#                 file_path = os.path.join(BIND_DIR, file_path)
#             zones.append({
#                 'domain': domain,
#                 'file': file_path,
#                 'records': parse_zone_file(file_path)
#             })
#     return zones

# def parse_zone_file(file_path):
#     records = []
#     try:
#         with open(file_path, 'r') as f:
#             for line in f:
#                 line = line.strip()
#                 if line.startswith(';') or not line:
#                     continue
#                 # 匹配记录格式：name [ttl] [class] type data
#                 match = re.match(r'^(\S+)\s+(\d+[A-Z]+\s+)?(IN\s+)?(\S+)\s+(.*)$', line)
#                 if match:
#                     name = match.group(1).rstrip('.')
#                     rtype = match.group(4)
#                     data = match.group(5).rstrip(';')
#                     records.append({
#                         'name': name,
#                         'type': rtype,
#                         'data': data,
#                         'raw': line
#                     })
#     except FileNotFoundError:
#         pass
#     return records

# def increment_serial(zone_file):
#     new_lines = []
#     serial_updated = False
#     with open(zone_file, 'r') as f:
#         for line in f:
#             if '; Serial' in line:
#                 # 匹配序列号：2024020601
#                 match = re.search(r'(\d{8})(\d{2})', line)
#                 if match:
#                     date_str = match.group(1)
#                     num = int(match.group(2))
#                     today = datetime.now().strftime("%Y%m%d")
#                     if today == date_str:
#                         new_num = num + 1
#                     else:
#                         new_num = 1
#                     new_serial = f"{today}{new_num:02d}"
#                     line = re.sub(r'\d{10}', new_serial, line)
#                     serial_updated = True
#             new_lines.append(line)
    
#     if serial_updated:
#         with open(zone_file, 'w') as f:
#             f.writelines(new_lines)
#     return serial_updated

# def save_zone_file(zone_file, records):
#     with open(zone_file, 'w') as f:
#         for record in records:
#             f.write(record['raw'] + '\n')

# def edit_record_form(stdscr, record=None):
#     fields = [
#         {"label": "Record Name", "value": record['name'] if record else "", "type": str},
#         {"label": "Record Type", "value": record['type'] if record else "A", "type": "list", "options": ["A", "AAAA", "CNAME", "MX", "TXT"]},
#         {"label": "Record Data", "value": record['data'] if record else "", "type": str},
#     ]
    
#     current_field = 0
#     while True:
#         stdscr.clear()
#         h, w = stdscr.getmaxyx()
        
#         # 绘制表单
#         stdscr.addstr(0, 2, "Use Tab/Arrow keys to navigate, Enter to save, ESC to cancel")
#         for idx, field in enumerate(fields):
#             y = idx * 2 + 2
#             label = f"{field['label']}: "
#             stdscr.addstr(y, 2, label)
            
#             if idx == current_field:
#                 stdscr.attron(curses.A_REVERSE)
            
#             # 显示字段值
#             display_value = ""
#             if field['type'] == "list":
#                 display_value = f"<{field['value']}>"
#             else:
#                 display_value = field['value']
            
#             stdscr.addstr(y, len(label)+2, display_value)
#             if idx == current_field:
#                 stdscr.attroff(curses.A_REVERSE)
        
#         stdscr.refresh()
#         key = stdscr.getch()
        
#         if key == 27:  # ESC
#             return None
#         elif key == 9:  # Tab
#             current_field = (current_field + 1) % len(fields)
#         elif key == 10:  # Enter
#             break
#         elif key == curses.KEY_UP:
#             current_field = (current_field - 1) % len(fields)
#         elif key == curses.KEY_DOWN:
#             current_field = (current_field + 1) % len(fields)
#         elif key == curses.KEY_LEFT and fields[current_field]['type'] == "list":
#             options = fields[current_field]['options']
#             current_idx = options.index(fields[current_field]['value'])
#             fields[current_field]['value'] = options[(current_idx - 1) % len(options)]
#         elif key == curses.KEY_RIGHT and fields[current_field]['type'] == "list":
#             options = fields[current_field]['options']
#             current_idx = options.index(fields[current_field]['value'])
#             fields[current_field]['value'] = options[(current_idx + 1) % len(options)]
#         elif key >= 32 and key <= 126 and fields[current_field]['type'] == str:
#             fields[current_field]['value'] += chr(key)
#         elif key in (curses.KEY_BACKSPACE, 127, 8) and fields[current_field]['type'] == str:
#             fields[current_field]['value'] = fields[current_field]['value'][:-1]
    
#     return {
#         'name': fields[0]['value'],
#         'type': fields[1]['value'],
#         'data': fields[2]['value']
#     }

# def main(stdscr):
#     curses.curs_set(0)
#     stdscr.keypad(True)
    
#     zones = parse_zones()
#     current_selection = 0
    
#     while True:
#         stdscr.clear()
#         h, w = stdscr.getmaxyx()
        
#         # 显示域名列表
#         stdscr.addstr(0, 2, "BIND域名管理 (使用方向键选择，Enter进入，Q退出)")
#         for idx, zone in enumerate(zones):
#             y = idx + 2
#             if idx == current_selection:
#                 stdscr.attron(curses.A_REVERSE)
#             stdscr.addstr(y, 4, f"{zone['domain']} ({len(zone['records'])} records)")
#             if idx == current_selection:
#                 stdscr.attroff(curses.A_REVERSE)
        
#         stdscr.refresh()
#         key = stdscr.getch()
        
#         if key == ord('q'):
#             break
#         elif key == curses.KEY_UP:
#             current_selection = max(0, current_selection - 1)
#         elif key == curses.KEY_DOWN:
#             current_selection = min(len(zones)-1, current_selection + 1)
#         elif key == 10:  # Enter
#             manage_zone(stdscr, zones[current_selection])

# def manage_zone(stdscr, zone):
#     current_selection = 0
#     while True:
#         stdscr.clear()
#         h, w = stdscr.getmaxyx()
        
#         # 显示记录列表
#         stdscr.addstr(0, 2, f"管理域名: {zone['domain']} (Enter编辑，N新增，D删除，Q返回)")
#         for idx, rec in enumerate(zone['records']):
#             y = idx + 2
#             # 跳过SOA和NS记录
#             if rec['type'] in ['SOA', 'NS']:
#                 continue
#             if idx == current_selection:
#                 stdscr.attron(curses.A_REVERSE)
#             display = f"{rec['name'].ljust(20)} {rec['type'].ljust(6)} {rec['data']}"
#             stdscr.addstr(y, 4, display)
#             if idx == current_selection:
#                 stdscr.attroff(curses.A_REVERSE)
        
#         stdscr.refresh()
#         key = stdscr.getch()
        
#         if key == ord('q'):
#             break
#         elif key == ord('n'):
#             new_rec = edit_record_form(stdscr)
#             if new_rec:
#                 # 生成记录行
#                 new_line = f"{new_rec['name']}.{zone['domain']}.   IN  {new_rec['type']}   {new_rec['data']}"
#                 zone['records'].append({
#                     'name': new_rec['name'],
#                     'type': new_rec['type'],
#                     'data': new_rec['data'],
#                     'raw': new_line
#                 })
#                 if increment_serial(zone['file']):
#                     save_zone_file(zone['file'], zone['records'])
#                     subprocess.run(["systemctl", "reload", "bind9"])
#         elif key == ord('d') and zone['records']:
#             del zone['records'][current_selection]
#             if increment_serial(zone['file']):
#                 save_zone_file(zone['file'], zone['records'])
#                 subprocess.run(["systemctl", "reload", "bind9"])
#         elif key == curses.KEY_UP:
#             current_selection = max(0, current_selection - 1)
#         elif key == curses.KEY_DOWN:
#             current_selection = min(len(zone['records'])-1, current_selection + 1)
#         elif key == 10:  # Enter
#             selected_rec = zone['records'][current_selection]
#             edited_rec = edit_record_form(stdscr, selected_rec)
#             if edited_rec:
#                 # 更新记录
#                 selected_rec.update({
#                     'name': edited_rec['name'],
#                     'type': edited_rec['type'],
#                     'data': edited_rec['data'],
#                     'raw': f"{edited_rec['name']}.{zone['domain']}.   IN  {edited_rec['type']}   {edited_rec['data']}"
#                 })
#                 if increment_serial(zone['file']):
#                     save_zone_file(zone['file'], zone['records'])
#                     subprocess.run(["systemctl", "reload", "bind9"])

# if __name__ == "__main__":
#     try:
#         curses.wrapper(main)
#     except KeyboardInterrupt:
#         pass




