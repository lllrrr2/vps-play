import tkinter as tk
from tkinter import scrolledtext, messagebox, ttk
import subprocess
import os
import sys
import threading
import shutil
import time

# 尝试导入 requests，如果没有则提示
try:
    import requests
except ImportError:
    print("请先安装 requests 库: pip install requests")
    try:
        import tkinter.messagebox
        root = tk.Tk()
        root.withdraw()
        tkinter.messagebox.showerror("缺少依赖", "请先安装 requests 库:\n\npip install requests")
        sys.exit(1)
    except:
        sys.exit(1)

class WarpKeyGenApp:
    def __init__(self, root):
        self.root = root
        self.root.title("WARP 配置文件生成器 (VPS-Play)")
        self.root.geometry("700x600")
        
        # 样式配置
        style = ttk.Style()
        style.configure("TButton", padding=6, font=("Microsoft YaHei", 10))
        style.configure("TLabel", font=("Microsoft YaHei", 10))
        
        # 顶部框架：代理设置
        top_frame = ttk.LabelFrame(root, text="网络设置", padding=10)
        top_frame.pack(fill="x", padx=10, pady=5)
        
        ttk.Label(top_frame, text="HTTP 代理 (例如 http://127.0.0.1:7890):").pack(side="left")
        self.proxy_var = tk.StringVar(value="")
        ttk.Entry(top_frame, textvariable=self.proxy_var, width=30).pack(side="left", padx=5)
        ttk.Label(top_frame, text="(留空则直连)").pack(side="left")
        
        # 中部框架：操作按钮
        action_frame = ttk.Frame(root, padding=10)
        action_frame.pack(fill="x", padx=10)
        
        self.btn_gen = ttk.Button(action_frame, text="一键注册并生成配置", command=self.start_generate)
        self.btn_gen.pack(side="left", fill="x", expand=True, padx=5)
        
        self.btn_copy = ttk.Button(action_frame, text="复制配置内容", command=self.copy_config)
        self.btn_copy.pack(side="left", fill="x", expand=True, padx=5)
        
        # 日志和输出区域
        self.log_area = scrolledtext.ScrolledText(root, font=("Consolas", 10), state='disabled', height=8)
        self.log_area.pack(fill="x", padx=10, pady=5)
        
        ttk.Label(root, text="生成的 WireGuard 配置 (请复制下方内容到 VPS):").pack(anchor="w", padx=10)
        self.result_area = scrolledtext.ScrolledText(root, font=("Consolas", 10))
        self.result_area.pack(fill="both", expand=True, padx=10, pady=5)
        
        # 状态栏
        self.status_var = tk.StringVar(value="准备就绪")
        ttk.Label(root, textvariable=self.status_var, relief="sunken").pack(fill="x", side="bottom")

        # 检查 wgcf
        self.wgcf_path = os.path.join(os.getcwd(), "wgcf.exe")
        self.check_env()

    def log(self, message):
        self.log_area.config(state='normal')
        self.log_area.insert(tk.END, message + "\n")
        self.log_area.see(tk.END)
        self.log_area.config(state='disabled')
        self.status_var.set(message)
        self.root.update()

    def check_env(self):
        if not os.path.exists(self.wgcf_path):
            self.log("未检测到 wgcf.exe，准备下载...")
        else:
            self.log(f"已检测到 wgcf.exe")

    def download_wgcf(self):
        url = "https://github.com/ViRb3/wgcf/releases/latest/download/wgcf_windows_amd64.exe"
        proxies = {}
        if self.proxy_var.get():
            proxies = {"http": self.proxy_var.get(), "https": self.proxy_var.get()}
            self.log(f"使用代理下载: {self.proxy_var.get()}")
        
        try:
            self.log("正在下载 wgcf.exe (GitHub)...")
            r = requests.get(url, proxies=proxies, stream=True, timeout=30)
            r.raise_for_status()
            with open(self.wgcf_path, 'wb') as f:
                for chunk in r.iter_content(chunk_size=8192):
                    f.write(chunk)
            self.log("wgcf.exe 下载成功！")
            return True
        except Exception as e:
            self.log(f"下载失败: {e}")
            messagebox.showerror("下载失败", f"无法下载 wgcf.exe:\n{e}\n\n请检查代理设或手动下载 wgcf_windows_amd64.exe 放入此目录。")
            return False

    def run_wgcf_command(self, args):
        env = os.environ.copy()
        if self.proxy_var.get():
            env["HTTP_PROXY"] = self.proxy_var.get()
            env["HTTPS_PROXY"] = self.proxy_var.get()
            
        try:
            # 在 Windows 上隐藏窗口运行
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            
            process = subprocess.Popen(
                [self.wgcf_path] + args,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
                startupinfo=startupinfo,
                encoding='utf-8', 
                errors='ignore' # 防止编码错误
            )
            stdout, stderr = process.communicate()
            return process.returncode, stdout, stderr
        except Exception as e:
            return -1, "", str(e)

    def start_generate(self):
        self.btn_gen.config(state="disabled")
        threading.Thread(target=self._generate_thread).start()

    def _generate_thread(self):
        try:
            # 1. 检查/下载 wgcf
            if not os.path.exists(self.wgcf_path):
                if not self.download_wgcf():
                    self.btn_gen.config(state="normal")
                    return

            # 清理旧文件
            if os.path.exists("wgcf-account.toml"): os.remove("wgcf-account.toml")
            if os.path.exists("wgcf-profile.conf"): os.remove("wgcf-profile.conf")

            # 2. 注册账户
            self.log("正在注册 WARP 账户...")
            code, out, err = self.run_wgcf_command(["register", "--accept-tos"])
            
            if code != 0:
                self.log(f"注册失败 (代码 {code})")
                self.log(f"错误信息: {err.strip()}")
                self.log(f"标准输出: {out.strip()}")
                
                if "429" in err or "429" in out:
                    self.log("提示: 请求过多 (429)，请更换代理 IP 或稍后重试。")
                self.btn_gen.config(state="normal")
                return
            
            self.log("注册成功！")
            
            # 3. 生成配置
            self.log("正在生成 WireGuard 配置文件...")
            code, out, err = self.run_wgcf_command(["generate"])
            
            if code != 0:
                self.log(f"生成失败: {err}")
                self.btn_gen.config(state="normal")
                return

            # 4. 读取配置
            if os.path.exists("wgcf-profile.conf"):
                with open("wgcf-profile.conf", "r", encoding='utf-8') as f:
                    config_content = f.read()
                
                self.result_area.delete("1.0", tk.END)
                self.result_area.insert(tk.END, config_content)
                self.log("配置生成完毕！请复制上方内容。")
            else:
                self.log("错误: 未找到生成的配置文件")

        except Exception as e:
            self.log(f"发生未预期的错误: {e}")
        finally:
            self.btn_gen.config(state="normal")

    def copy_config(self):
        content = self.result_area.get("1.0", tk.END).strip()
        if content:
            self.root.clipboard_clear()
            self.root.clipboard_append(content)
            self.log("配置已复制到剪贴板！")
            messagebox.showinfo("成功", "配置已复制到剪贴板！\n请回到 VPS 脚本选择 '手动输入' 并粘贴。")
        else:
            messagebox.showwarning("提示", "没有可复制的内容，请先生成。")

if __name__ == "__main__":
    root = tk.Tk()
    app = WarpKeyGenApp(root)
    root.mainloop()
