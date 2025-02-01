#!/usr/bin/env python3
import curses
import time
import threading
import subprocess
import re

# ───────────────────────────────────────────────────────────
# 1. 菜单数据及功能函数定义
# ───────────────────────────────────────────────────────────

left_menu = [
    "a3. 系统信息查询",
    "a2. 系统更新",
    "333. 系统清理",
    "e. Docker管理",
    "5. 脚本更新"
]
right_menu = [
    "1. 网络设置",
    "b. 资源监控",
    "3. 安全检查",
    "D. 服务管理",
    "93. 数据备份"
]

def pause(stdscr):
    """暂停，等待用户按任意键，然后恢复非阻塞模式"""
    stdscr.nodelay(False)
    stdscr.getch()
    stdscr.nodelay(True)

def linux_ps(stdscr):
    stdscr.clear()
    stdscr.addstr(0, 0, "系统信息展示")
    stdscr.addstr(2, 0, "操作完成，请按任意键返回菜单...")
    stdscr.refresh()
    pause(stdscr)

def linux_update(stdscr):
    stdscr.clear()
    stdscr.addstr(0, 0, "系统更新中...")
    stdscr.addstr(2, 0, "操作完成，请按任意键返回菜单...")
    stdscr.refresh()
    pause(stdscr)

def linux_clean(stdscr):
    stdscr.clear()
    stdscr.addstr(0, 0, "系统清理中...")
    stdscr.addstr(2, 0, "操作完成，请按任意键返回菜单...")
    stdscr.refresh()
    pause(stdscr)

def linux_docker(stdscr):
    stdscr.clear()
    stdscr.addstr(0, 0, "Docker 管理中...")
    stdscr.addstr(2, 0, "操作完成，请按任意键返回菜单...")
    stdscr.refresh()
    pause(stdscr)

def network_config(stdscr):
    stdscr.clear()
    stdscr.addstr(0, 0, "网络设置...")
    stdscr.addstr(2, 0, "操作完成，请按任意键返回菜单...")
    stdscr.refresh()
    pause(stdscr)

def resource_monitor(stdscr):
    stdscr.clear()
    stdscr.addstr(0, 0, "资源监控中...")
    stdscr.addstr(2, 0, "操作完成，请按任意键返回菜单...")
    stdscr.refresh()
    pause(stdscr)

def security_check(stdscr):
    stdscr.clear()
    stdscr.addstr(0, 0, "安全检查中...")
    stdscr.addstr(2, 0, "操作完成，请按任意键返回菜单...")
    stdscr.refresh()
    pause(stdscr)

def service_management(stdscr):
    stdscr.clear()
    stdscr.addstr(0, 0, "服务管理中...")
    stdscr.addstr(2, 0, "操作完成，请按任意键返回菜单...")
    stdscr.refresh()
    pause(stdscr)

def data_backup(stdscr):
    stdscr.clear()
    stdscr.addstr(0, 0, "数据备份中...")
    stdscr.addstr(2, 0, "操作完成，请按任意键返回菜单...")
    stdscr.refresh()
    pause(stdscr)

actions_left = [linux_ps, linux_update, linux_clean, linux_docker, linux_update]
actions_right = [network_config, resource_monitor, security_check, service_management, data_backup]

# ───────────────────────────────────────────────────────────
# 2. 动态信息（CPU、内存、网络）更新（采用全局变量和线程）
# ───────────────────────────────────────────────────────────

dynamic_cpu = "CPU占用: 加载中..."
dynamic_memory = "内存占用: 加载中..."
dynamic_net = "网络流量: 加载中..."
dynamic_lock = threading.Lock()
running = True

def update_dynamic_info():
    global dynamic_cpu, dynamic_memory, dynamic_net, running
    while running:
        try:
            # 获取 CPU 信息：调用 top，解析 id（空闲率）后计算使用率
            try:
                top_output = subprocess.check_output(["top", "-bn1"], universal_newlines=True)
                cpu_line = ""
                for line in top_output.splitlines():
                    if "Cpu(s)" in line:
                        cpu_line = line
                        break
                cpu_usage = "未知"
                if cpu_line:
                    m = re.search(r"(\d+\.\d+)\s*id", cpu_line)
                    if m:
                        idle = float(m.group(1))
                        usage = 100 - idle
                        cpu_usage = f"{usage:.1f}%"
            except Exception:
                cpu_usage = "未知"

            # 获取内存使用情况（调用 free -m）
            try:
                free_output = subprocess.check_output(["free", "-m"], universal_newlines=True)
                mem_line = ""
                for line in free_output.splitlines():
                    if line.startswith("Mem:"):
                        mem_line = line
                        break
                memory_info = "未知"
                if mem_line:
                    parts = mem_line.split()
                    if len(parts) >= 3:
                        used = parts[2]
                        total = parts[1]
                        memory_info = f"{used}/{total} MB"
            except Exception:
                memory_info = "未知"

            # 获取网络流量（调用 ifstat -q 1 1）
            try:
                ifstat_output = subprocess.check_output(["ifstat", "-q", "1", "1"],
                                                         universal_newlines=True,
                                                         stderr=subprocess.DEVNULL)
                lines = ifstat_output.splitlines()
                if len(lines) >= 3:
                    net_line = lines[2]
                    parts = net_line.split()
                    if len(parts) >= 2:
                        net_info = f"入站: {parts[0]} KB/s 出站: {parts[1]} KB/s"
                    else:
                        net_info = "--"
                else:
                    net_info = "--"
            except Exception:
                net_info = "--"

            with dynamic_lock:
                dynamic_cpu = f"CPU占用: {cpu_usage}"
                dynamic_memory = f"内存占用: {memory_info}"
                dynamic_net = f"网络流量: {net_info}"
        except Exception:
            with dynamic_lock:
                dynamic_cpu = "CPU占用: 错误"
                dynamic_memory = "内存占用: 错误"
                dynamic_net = "网络流量: 错误"
        time.sleep(1)

# ───────────────────────────────────────────────────────────
# 3. 绘制界面（采用局部窗口更新）
# ───────────────────────────────────────────────────────────

def draw_dynamic_info(win):
    """绘制屏幕上方的动态信息区域"""
    win.erase()
    with dynamic_lock:
        win.addstr(0, 0, dynamic_cpu.ljust(50))
        win.addstr(1, 0, dynamic_memory.ljust(50))
        win.addstr(2, 0, dynamic_net.ljust(50))
    win.noutrefresh()

def draw_menu(menu_win, current_row, current_col, input_buffer=""):
    """绘制菜单及底部提示信息"""
    menu_win.erase()
    menu_win.addstr(0, 0, "=======超级菜单=======")
    # 菜单区在窗口内从第2行开始绘制（全局行：dyn_win 高度 3 + 2 = 5）
    start_row = 2
    for idx, item in enumerate(left_menu):
        if idx == current_row and current_col == 0:
            menu_win.addstr(start_row+idx, 0, "> " + item, curses.A_REVERSE)
        else:
            menu_win.addstr(start_row+idx, 0, "  " + item)
    # 绘制右侧菜单，从窗口内第2行、列30开始
    for idx, item in enumerate(right_menu):
        if idx == current_row and current_col == 1:
            menu_win.addstr(start_row+idx, 30, "> " + item, curses.A_REVERSE)
        else:
            menu_win.addstr(start_row+idx, 30, "  " + item)
    # 底部提示
    bottom = start_row + len(left_menu) + 1
    menu_win.addstr(bottom, 0, "↑ ↓ 调整行；左右箭头切换菜单栏；")
    menu_win.addstr(bottom+1, 0, "数字字母组合（半秒）快速定位；")
    menu_win.addstr(bottom+2, 0, "鼠标单击：首次点击选中，点击已选中项则确认；")
    menu_win.addstr(bottom+3, 0, "输入缓冲: " + input_buffer)
    menu_win.noutrefresh()

def execute_current_option(stdscr, current_row, current_col):
    """调用当前菜单项对应的功能函数，并等待用户按键后返回"""
    if current_col == 0:
        action = actions_left[current_row]
    else:
        action = actions_right[current_row]
    stdscr.clear()
    stdscr.refresh()
    action(stdscr)

# ───────────────────────────────────────────────────────────
# 4. 主循环及事件处理
# ───────────────────────────────────────────────────────────

def main(stdscr):
    global running
    curses.curs_set(0)
    stdscr.nodelay(True)   # 主循环采用非阻塞模式
    stdscr.timeout(100)    # 每 100 毫秒轮询一次
    curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)

    # 创建两个子窗口：上部用于动态信息，下部用于菜单
    height, width = stdscr.getmaxyx()
    dyn_win = curses.newwin(3, width, 0, 0)         # 动态信息区域（3行）
    menu_win = curses.newwin(height-3, width, 3, 0)   # 菜单区域

    # 全局菜单第一项在全局行：动态区3行 + 菜单窗口内偏移2行 = 5
    menu_global_start = 5

    current_row = 0
    current_col = 0
    input_buffer = ""
    last_input_time = 0

    while True:
        # 分别局部更新动态信息和菜单
        draw_dynamic_info(dyn_win)
        draw_menu(menu_win, current_row, current_col, input_buffer)
        curses.doupdate()

        try:
            c = stdscr.getch()
        except KeyboardInterrupt:
            break

        if c == -1:
            # 若无输入，检测数字/字母缓冲是否超时
            if input_buffer and (time.time() - last_input_time) > 0.5:
                found = False
                for idx, item in enumerate(left_menu):
                    key = item.split('.')[0].strip()
                    if key == input_buffer:
                        current_row = idx
                        current_col = 0
                        found = True
                        break
                if not found:
                    for idx, item in enumerate(right_menu):
                        key = item.split('.')[0].strip()
                        if key == input_buffer:
                            current_row = idx
                            current_col = 1
                            found = True
                            break
                if not found and input_buffer:
                    menu_win.addstr(len(left_menu)+4, 0, f"未找到匹配项 [{input_buffer}]！", curses.A_BOLD)
                    menu_win.noutrefresh()
                    curses.doupdate()
                    time.sleep(1)
                input_buffer = ""
            continue

        if c == curses.KEY_MOUSE:
            try:
                _, mx, my, _, bstate = curses.getmouse()
                # 判断鼠标点击是否在菜单区域内
                # 菜单区域全局起始行为 menu_global_start
                if menu_global_start <= my < menu_global_start + len(left_menu):
                    new_row = my - menu_global_start
                    if mx < 30:
                        new_col = 0
                    elif 30 <= mx < 60:
                        new_col = 1
                    else:
                        new_col = current_col
                    # 如果点击的菜单项与当前选中项不同，仅更新选中
                    if (new_row, new_col) != (current_row, current_col):
                        current_row, current_col = new_row, new_col
                    else:
                        # 若点击的是当前选中项，则直接执行对应功能
                        execute_current_option(stdscr, current_row, current_col)
                    draw_menu(menu_win, current_row, current_col, input_buffer)
                # 否则忽略
            except Exception:
                pass

        elif c == curses.KEY_UP:
            current_row = (current_row - 1) % len(left_menu)
        elif c == curses.KEY_DOWN:
            current_row = (current_row + 1) % len(left_menu)
        elif c in (curses.KEY_LEFT, curses.KEY_RIGHT):
            # 左右箭头切换当前菜单栏（若当前在左栏则切换到右栏，反之亦然）
            current_col = 1 - current_col
        elif c in (10, 13):  # Enter 键
            if input_buffer:
                found = False
                for idx, item in enumerate(left_menu):
                    key = item.split('.')[0].strip()
                    if key == input_buffer:
                        current_row = idx
                        current_col = 0
                        found = True
                        break
                if not found:
                    for idx, item in enumerate(right_menu):
                        key = item.split('.')[0].strip()
                        if key == input_buffer:
                            current_row = idx
                            current_col = 1
                            found = True
                            break
                input_buffer = ""
            execute_current_option(stdscr, current_row, current_col)
        elif c == 27:  # ESC 键退出
            break
        else:
            # 如果输入为字母或数字，则加入缓冲
            if 32 <= c <= 126:
                ch = chr(c)
                if ch.isalnum():
                    input_buffer += ch
                    last_input_time = time.time()

    running = False
    time.sleep(0.2)

if __name__ == "__main__":
    # 启动动态信息更新线程
    dyn_thread = threading.Thread(target=update_dynamic_info, daemon=True)
    dyn_thread.start()
    curses.wrapper(main)
