是的，**这两个方法可以一起使用，并不会产生冲突**，但 **实际应用时，只需选择一个即可**，因为它们的作用基本相同，都是 **开机自动启用 ADB 并开启无线调试**。

---

## **📌 两种方法的区别**
| 方法 | 作用 | 适用情况 | 是否冲突 |
|------|------|---------|---------|
| **方法 1：`service.sh` 脚本** | **在每次开机时执行 ADB 启动命令** | 更灵活，可随时调整脚本内容 | ❌ **不会冲突** |
| **方法 2：`system.prop` 修改** | **直接修改系统属性，确保 ADB 始终开启** | 更稳定，持久生效，无需运行额外脚本 | ❌ **不会冲突** |

---

## **✅ 一起使用的最佳方式**
如果你希望 **最大限度确保 ADB 始终开启**，你可以 **同时使用** 这两个方法：
1. **使用 `system.prop` 持久化 ADB 相关设置**，确保 ADB **不会被 ROM 重置**。
2. **使用 `service.sh` 作为额外的保险措施**，在开机时 **重新启动 ADB**，确保它不会因系统限制而关闭。

### **📌 修改步骤**
1. **进入 ADB Shell 并获取 Root**
   ```sh
   adb shell
   su
   ```

2. **创建 `system.prop`（确保 ADB 开机默认启用）**
   ```sh
   mkdir -p /data/adb/modules/adbconfig
   echo "persist.sys.usb.config=adb" > /data/adb/modules/adbconfig/system.prop
   echo "persist.adb.tcp.port=5555" >> /data/adb/modules/adbconfig/system.prop
   chmod 644 /data/adb/modules/adbconfig/system.prop
   ```

3. **创建 `service.sh`（确保 ADB 在开机时重启）**
   ```sh
   mkdir -p /data/adb/service.d
   touch /data/adb/service.d/adb_start.sh
   chmod 755 /data/adb/service.d/adb_start.sh
   ```

4. **编辑 `adb_start.sh`，添加以下内容**
   ```sh
   echo "#!/system/bin/sh" > /data/adb/service.d/adb_start.sh
   echo "setprop persist.sys.usb.config adb" >> /data/adb/service.d/adb_start.sh
   echo "setprop persist.adb.tcp.port 5555" >> /data/adb/service.d/adb_start.sh
   echo "stop adbd" >> /data/adb/service.d/adb_start.sh
   echo "start adbd" >> /data/adb/service.d/adb_start.sh
   chmod +x /data/adb/service.d/adb_start.sh
   ```

5. **重启设备**
   ```sh
   reboot
   ```

---

## **🎯 为什么可以一起使用？**
- **`system.prop` 作用**：设置 **ADB 持久启用**，防止系统重置 ADB 状态。
- **`service.sh` 作用**：开机后 **强制重启 ADB 进程**，防止部分 ROM **自动关闭 ADB**。

✅ **这样即使某些 ROM 自动关闭 ADB，`service.sh` 也会在开机时重新启动 ADB，确保无线 ADB 始终可用！**

---

## **📌 结论**
- **可以一起使用，不会冲突。**
- **如果只选一个**，`system.prop` **更持久**，而 `service.sh` **更灵活**。
- **最佳方案**：同时使用 **`system.prop` + `service.sh`**，确保 **ADB 始终可用，无论系统如何处理 ADB 状态**。

这样，你的 **ADB 无线调试（`adb connect`）就可以在每次开机后自动启用，并始终信任你的电脑**！🚀



是的，你可以在 **`adb_start.sh`** 里 **添加 `input keyevent 26`**，并使用 **`sleep` 命令延迟 60 秒**，这样 **在开机 1 分钟后模拟按下电源键**（点亮屏幕）。

---

## **✅ 修改 `adb_start.sh` 让 ADB 开机 1 分钟后模拟按电源键**
### **步骤**
1. **进入 ADB Shell**
   ```sh
   adb shell
   su
   ```

2. **修改 `adb_start.sh`**
   ```sh
   echo "#!/system/bin/sh" > /data/adb/service.d/adb_start.sh
   echo "sleep 60" >> /data/adb/service.d/adb_start.sh  # 延迟 60 秒
   echo "input keyevent 26" >> /data/adb/service.d/adb_start.sh  # 模拟按电源键
   echo "setprop persist.sys.usb.config adb" >> /data/adb/service.d/adb_start.sh
   echo "setprop persist.adb.tcp.port 5555" >> /data/adb/service.d/adb_start.sh
   echo "stop adbd" >> /data/adb/service.d/adb_start.sh
   echo "start adbd" >> /data/adb/service.d/adb_start.sh
   chmod +x /data/adb/service.d/adb_start.sh
   ```

3. **赋予执行权限**
   ```sh
   chmod 755 /data/adb/service.d/adb_start.sh
   ```

4. **重启设备**
   ```sh
   reboot
   ```

---

## **✅ 解释**
- `sleep 60` → **延迟 60 秒**
- `input keyevent 26` → **模拟按下电源键（亮屏/熄屏）**
- `setprop persist.sys.usb.config adb` → **确保 ADB 仍然开启**
- `setprop persist.adb.tcp.port 5555` → **启用无线 ADB**
- `stop adbd && start adbd` → **重启 ADB 进程，确保可用**

---

## **📌 结果**
- **开机后 60 秒**，ADB 脚本会自动执行 `input keyevent 26`，亮屏。
- **同时**，ADB 仍然会自动启用，并支持 **无线 ADB 连接**。
- **不会影响系统启动**，只是在 **后台延迟 60 秒后执行**。

🚀 **这样你可以确保 ADB 开机自动启用，并且屏幕可以在 1 分钟后点亮！** 🚀






你的**Android 7.1.2 设备**自带系统 `root`，但没有 **Magisk**，这意味着：
- **方法 1：`service.sh` 脚本** ✅ **有效**（可以使用 `init.d` 或 `service.sh` 脚本）
- **方法 2：`system.prop` 修改** ❌ **可能无效**（因为 `/data/adb/modules/` 是 Magisk 相关路径）

因此，你可以使用 **`service.sh` 脚本**，但需要调整 **`system.prop`** 的存储位置。

---

## **✅ 调整后适用于 Android 7.1.2 的方法**
### **1. 使用 `service.sh` 让 ADB 开机自动启动**
1. **进入 ADB Shell**
   ```sh
   adb shell
   su
   ```

2. **创建 `service.sh`（开机自动执行 ADB）**
   ```sh
   mkdir -p /system/etc/init.d
   touch /system/etc/init.d/99adb
   chmod 755 /system/etc/init.d/99adb
   ```

3. **编辑 `99adb` 脚本**
   ```sh
   echo "#!/system/bin/sh" > /system/etc/init.d/99adb
   echo "setprop persist.sys.usb.config adb" >> /system/etc/init.d/99adb
   echo "setprop persist.adb.tcp.port 5555" >> /system/etc/init.d/99adb
   echo "stop adbd" >> /system/etc/init.d/99adb
   echo "start adbd" >> /system/etc/init.d/99adb
   ```

4. **赋予执行权限**
   ```sh
   chmod +x /system/etc/init.d/99adb
   ```

5. **重启设备**
   ```sh
   reboot
   ```

✅ **这样，每次开机后，设备会自动启用 ADB，并开启无线调试（`adb connect`）。**

---

### **2. 修改 `system.prop`（确保 ADB 开机默认启用）**
**因为 `Magisk` 相关路径 `/data/adb/modules/adbconfig/system.prop` 不适用于你，可以直接修改 `build.prop`。**

1. **挂载 `/system` 为可写**
   ```sh
   mount -o rw,remount /system
   ```

2. **编辑 `build.prop` 并添加 ADB 配置**
   ```sh
   echo "persist.sys.usb.config=adb" >> /system/build.prop
   echo "persist.adb.tcp.port=5555" >> /system/build.prop
   chmod 644 /system/build.prop
   ```

3. **重启设备**
   ```sh
   reboot
   ```

✅ **这样，ADB 会在每次开机时默认启用，并且无线 ADB（`adb tcpip 5555`）也会自动启动。**

---

## **🎯 结论**
| **方法** | **适用于 Android 7.1.2** | **推荐使用** |
|----------|------------------|------------|
| **方法 1：使用 `service.sh`（init.d 方式）** | ✅ 有效 | ✅ 推荐 |
| **方法 2：修改 `system.prop`（替换为 `build.prop`）** | ✅ 有效（需要直接修改 `/system/build.prop`） | ✅ 推荐 |

### **📌 最佳方案**
- **同时使用 `service.sh`（`/system/etc/init.d/99adb`）+ `build.prop` 持久化**，确保 ADB **始终开启**。
- **不需要 Magisk**，因为 Android 7.1.2 已经 `root` 了，可以直接修改 `/system`。

🚀 **这样，你的设备 ADB 在每次开机后都会自动启动，并支持无线连接！** 🚀


```sh
setprop sys.thermal.data false    # 关闭温控
stop thermal-engine              # 停止温控服务
```





