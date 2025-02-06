


### 一键脚本zsh_setup
```bash
bash <(curl -s https://raw.githubusercontent.com/EasyStartBox/esb/main/scripts/linux/zsh_setup.sh)
```
***


### 一键脚本sh_main.sh
```bash
bash <(curl -s https://raw.githubusercontent.com/EasyStartBox/esb/main/scripts/linux/patch_sh/sh_main.sh)
```
***

### BIND和简单管理bind-manager.py
```bash
curl -sL https://raw.githubusercontent.com/EasyStartBox/esb/main/scripts/linux/setup_bind.sh | bash && wget -q https://raw.githubusercontent.com/EasyStartBox/esb/main/scripts/linux/bind-manager.py -O bind-manager.py
```
***

### 使用 `curl` 或 `wget` 下载并执行例子

1. **使用 `curl`**：
   
   假设你要下载的脚本文件 URL 是 `https://raw.githubusercontent.com/username/repository/branch/script.sh`，你可以运行以下命令来下载并执行它：

   ```bash
   curl -sL https://raw.githubusercontent.com/username/repository/branch/script.sh | bash && curl -sL https://raw.githubusercontent.com/username/repository/branch/script.sh | bash
   ```

   这里的 `-sL` 参数是：
   - `-s` 表示静默模式，不输出下载过程。
   - `-L` 表示如果服务器返回 3xx 重定向，就自动跟随重定向。

2. **使用 `wget`**：

   如果你更喜欢 `wget`，可以用以下命令：

   ```bash
   wget -qO- https://raw.githubusercontent.com/username/repository/branch/script.sh | bash
   ```

   这里的 `-qO-` 参数是：
   - `-q` 表示静默模式，不输出下载过程。
   - `-O-` 表示将下载内容直接输出到标准输出（`stdout`），而不是保存到文件。



