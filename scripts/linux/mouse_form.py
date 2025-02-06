#!/usr/bin/env python3
import curses
import random
import string
import json
import os

SAVE_FILE = "form_data.json"

def generate_random_data(field_name):
    """根据字段名称生成不同的随机数据"""
    if "Name" in field_name:
        return ''.join(random.choices(string.ascii_letters, k=8))
    elif "Age" in field_name:
        return str(random.randint(18, 99))
    elif "Email" in field_name:
        return ''.join(random.choices(string.ascii_lowercase, k=6)) + "@example.com"
    else:
        return ''.join(random.choices(string.ascii_letters + string.digits, k=10))

def save_to_json(fields):
    """将表单数据保存到 JSON 文件"""
    data = {field["label"]: field["value"] for field in fields}
    with open(SAVE_FILE, "w") as f:
        json.dump(data, f, indent=4)
    return SAVE_FILE

def main(stdscr):
    # 初始化 curses
    curses.curs_set(1)
    stdscr.keypad(True)
    curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)

    # 定义表单字段
    fields = [
        {"label": "Name",  "value": "", "row": 2, "col": 15, "width": 30, "cursor": 0, "button_col": 50},
        {"label": "Age",   "value": "", "row": 4, "col": 15, "width": 5,  "cursor": 0, "button_col": 25},
        {"label": "Email", "value": "", "row": 6, "col": 15, "width": 40, "cursor": 0, "button_col": 60},
    ]
    current_field = 0  # 当前选中的字段索引

    while True:
        stdscr.clear()
        stdscr.addstr(0, 2, "Tab (→) / Shift+Tab (←) 切换，Enter 保存，ESC 退出，鼠标可点击按钮生成随机数据。")

        # 绘制表单
        for idx, field in enumerate(fields):
            label = field["label"] + ":"
            stdscr.addstr(field["row"], 2, label)
            
            # 显示输入框
            text = field["value"]
            display_text = text + " " * (field["width"] - len(text))  # 确保输入框显示完整
            if idx == current_field:
                stdscr.attron(curses.A_REVERSE)
                stdscr.addstr(field["row"], field["col"], display_text[:field["width"]])
                stdscr.attroff(curses.A_REVERSE)
            else:
                stdscr.addstr(field["row"], field["col"], display_text[:field["width"]])

            # 显示随机数据按钮
            stdscr.addstr(field["row"], field["button_col"], "[生成]", curses.A_BOLD)

        # 确保光标在当前字段的输入区域
        cur_field = fields[current_field]
        if cur_field["cursor"] > len(cur_field["value"]):
            cur_field["cursor"] = len(cur_field["value"])
        cursor_x = cur_field["col"] + cur_field["cursor"]
        cursor_y = cur_field["row"]
        stdscr.move(cursor_y, cursor_x)
        stdscr.refresh()

        # 读取用户输入
        key = stdscr.getch()

        if key == 27:  # ESC 退出
            break
        elif key in (9, 258):  # Tab 或 ↓  (切换到下一个字段)
            current_field = (current_field + 1) % len(fields)
        elif key in (353, 259):  # Shift+Tab 或 ↑ (切换到上一个字段)
            current_field = (current_field - 1) % len(fields)
        elif key == curses.KEY_LEFT:
            if fields[current_field]["cursor"] > 0:
                fields[current_field]["cursor"] -= 1
        elif key == curses.KEY_RIGHT:
            if fields[current_field]["cursor"] < len(fields[current_field]["value"]):
                fields[current_field]["cursor"] += 1
        elif key == 10:  # Enter 键，保存到 JSON 文件
            file_saved = save_to_json(fields)
            stdscr.addstr(len(fields) + 8, 2, f"数据已保存到 {file_saved}", curses.A_BOLD)
            stdscr.refresh()
            curses.napms(1000)  # 显示 1 秒后继续
        elif key in (curses.KEY_BACKSPACE, 127, 8):
            cur_field = fields[current_field]
            pos = cur_field["cursor"]
            if pos > 0:
                cur_field["value"] = cur_field["value"][:pos-1] + cur_field["value"][pos:]
                cur_field["cursor"] -= 1
        elif key == curses.KEY_MOUSE:
            try:
                _, mx, my, _, _ = curses.getmouse()
                for idx, field in enumerate(fields):
                    # 检测是否点击在输入框内
                    if my == field["row"]:
                        if field["col"] <= mx < field["col"] + field["width"]:
                            current_field = idx
                            pos = mx - field["col"]
                            if pos > len(field["value"]):
                                pos = len(field["value"])
                            field["cursor"] = pos
                            break
                        # 检测是否点击按钮
                        elif field["button_col"] <= mx < field["button_col"] + 5:
                            field["value"] = generate_random_data(field["label"])
                            field["cursor"] = len(field["value"])
                            break
            except Exception:
                pass
        elif 32 <= key <= 126:  # 可打印字符（字母、数字、符号等）
            ch = chr(key)
            cur_field = fields[current_field]
            pos = cur_field["cursor"]
            new_value = cur_field["value"][:pos] + ch + cur_field["value"][pos:]
            if len(new_value) <= cur_field["width"]:
                cur_field["value"] = new_value
                cur_field["cursor"] += 1

if __name__ == "__main__":
    curses.wrapper(main)
