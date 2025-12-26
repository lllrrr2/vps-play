# VPS-play

> 通用 VPS 管理工具，支持普通VPS、NAT VPS、FreeBSD、Serv00/Hostuno

## ✨ 特性

- 🌐 **多环境支持**: 自动识别并适配不同VPS环境
  - 普通VPS (有root权限)
  - NAT VPS (端口映射)
  - FreeBSD 系统
  - Serv00/Hostuno 特殊环境（自动检测并提示不兼容模块）
  
- 🛠️ **统一管理**: 一个脚本管理所有服务
  - sing-box 节点 (Hysteria2/TUIC/VLESS Reality/**多协议组合**)
  - **Argo 节点** (VLESS/VMess+WS+Cloudflare隧道)
  - GOST 流量中转
  - X-UI 可视化面板
  - FRPC/FRPS 内网穿透
  - Cloudflared 隧道
  - **跳板服务器** (SSH远程管理)
  - 哪吒监控
  - WARP 代理
  - Docker 管理

- 🔧 **智能端口管理**: 自动适配端口管理方式
  - devil (Serv00/Hostuno)
  - iptables (VPS)
  - socat (NAT环境)
  - 直接绑定

- 🔄 **保活功能**: 多种保活方式
  - 本地进程保活
  - 远程SSH复活
  - Cron定时任务
  - systemd 服务

- 🧹 **系统清理**: 一键释放磁盘空间
  - 清理包管理器缓存
  - 清理日志文件
  - 清理 Docker 垃圾
  - 清理临时文件

## 📦 支持的环境

| 环境类型 | 权限 | 端口管理 | 服务管理 | 状态 |
|---------|------|---------|---------|------|
| 普通VPS | root | direct/iptables | systemd | ✅ 支持 |
| NAT VPS | root/limited | iptables/socat | systemd/cron | ✅ 支持 |
| FreeBSD | root | direct | rc.d/cron | ✅ 支持 |
| Serv00/Hostuno | limited | devil | cron | ✅ 支持 |

### Serv00/Hostuno 兼容性

| 模块 | 支持 | 说明 |
|------|------|------|
| sing-box | ✅ | 直接运行二进制文件 |
| Argo节点 | ✅ | 使用Cloudflare隧道 |
| GOST | ✅ | 直接运行二进制文件 |
| Cloudflared | ✅ | 推荐使用 |
| FRPC | ✅ | 内网穿透客户端 |
| 跳板服务器 | ✅ | SSH远程管理 |
| 哪吒 Agent | ✅ | 监控探针 |
| Docker | ❌ | 需要 root 权限 |
| WARP | ❌ | 需要内核模块 |
| X-UI | ❌ | 需要 Docker 或 root |

## 🚀 快速开始

### 一键安装

```bash
# 一键安装 (推荐)
curl -sL https://raw.githubusercontent.com/hxzlplp7/vps-play/main/install.sh | bash

# 或使用 wget
wget -qO- https://raw.githubusercontent.com/hxzlplp7/vps-play/main/install.sh | bash

# 安装完成后运行
vps-play
```

### 基本使用

```bash
# 启动主菜单
vps-play

# 或直接运行
bash ~/vps-play/start.sh

# 环境检测
bash ~/vps-play/utils/env_detect.sh
```

## 📖 功能模块

### 1. sing-box 节点

支持多种协议的代理节点：
- Hysteria2 (推荐)
- TUIC v5
- VLESS Reality
- **AnyTLS** (新，sing-box v1.12.0+)
- **Any-Reality** (AnyTLS + Reality 组合)
- Shadowsocks
- Trojan
- **多协议组合安装** (一键部署多个协议)
- **预设组合** (标准/全能/免费端口/完整)
- 自动生成分享链接

### 2. Argo 节点 (新增)

使用 Cloudflare Argo 隧道搭建节点：
- VLESS+WS+Argo (临时隧道)
- VMess+WS+Argo (临时隧道)
- 多协议组合 (VLESS+VMess)
- Token 固定隧道模式
- 自动获取 Cloudflare 域名
- 无需公网IP/端口

### 3. GOST 流量中转

强大的流量中转工具 (v3)：
- TCP/UDP 端口转发
- 多协议支持
- 自动配置生成

### 4. X-UI 面板

可视化管理面板：
- Web界面管理
- 多用户支持
- 流量统计
- (需要 Docker 或 root 权限)

### 5. FRPC/FRPS 内网穿透

- FRPC 客户端：连接到远程服务器
- FRPS 服务端：搭建自己的穿透服务器
- 多隧道支持
- 配置持久化

### 6. Cloudflared 隧道

Cloudflare Tunnel：
- 无需公网IP
- HTTPS支持
- Quick Tunnel 快速体验
- 免费使用

### 7. 跳板服务器 (新增)

SSH 远程管理功能：
- 服务器列表管理 (支持密码/密钥认证)
- SSH 快速连接
- SSH 跳板链 (多跳 A->B->C)
- 本地端口转发 (访问远程服务)
- 远程端口转发 (反向隧道)
- SOCKS5 动态代理
- 批量执行命令
- 批量上传文件

### 8. 哪吒监控

服务器监控：
- 实时监控
- 告警通知
- 多服务器管理

### 9. WARP 代理

Cloudflare WARP：
- 解锁流媒体
- 更换出口IP
- WARP+ 支持
- (需要 root 和内核模块)

### 10. Docker 管理

容器管理：
- 一键安装 Docker
- Docker Compose
- 镜像加速配置
- (不支持 Serv00)

## 🔧 系统工具

### 端口管理
- 添加/删除端口
- 端口可用性检查
- 随机端口分配

### 进程管理
- 查看运行中的进程
- 启动/停止服务

### 网络工具
- IP 信息查看
- 端口连通性测试

### 环境检测
- 操作系统类型
- 架构信息
- 权限级别
- 网络环境

### 保活设置
- 进程保活配置
- Cron 任务管理

### 系统清理与重置

清理功能：
- 清理包管理器缓存 (APT/YUM/PKG等)
- 清理系统日志
- 清理临时文件
- 清理 Docker 垃圾
- 清理 VPS-play 缓存

重置功能 (支持 VPS/FreeBSD/Serv00/Hostuno)：
- 重置 VPS-play (删除所有数据和配置)
- 重置单个模块
- 系统完全重置 (恢复初始状态)
  - 停止所有用户进程
  - 删除所有用户端口 (Serv00)
  - 清理 cron 任务
  - 删除 systemd 服务 (Linux)
  - 删除用户程序和配置


## 📁 项目结构

```
vps-play/
├── start.sh              # 主入口脚本
├── install.sh            # 一键安装脚本
├── utils/                # 工具库
│   ├── env_detect.sh     # 环境检测
│   ├── port_manager.sh   # 端口管理
│   ├── process_manager.sh # 进程管理
│   ├── network.sh        # 网络工具
│   └── system_clean.sh   # 系统清理
├── modules/              # 功能模块
│   ├── singbox/          # sing-box (多协议组合)
│   ├── argo/             # Argo节点 (NEW)
│   ├── gost/             # GOST
│   ├── xui/              # X-UI
│   ├── frpc/             # FRPC
│   ├── frps/             # FRPS
│   ├── cloudflared/      # Cloudflared
│   ├── jumper/           # 跳板服务器 (NEW)
│   ├── nezha/            # 哪吒监控
│   ├── warp/             # WARP
│   └── docker/           # Docker
├── keepalive/            # 保活脚本
└── README.md
```

## 🔄 更新日志

### v1.2.0 (2025-12-26)

- ✨ 新增: **AnyTLS 协议支持**
  - AnyTLS 基础协议（sing-box v1.12.0+）
  - 三层证书备用方案（EC → RSA → 远程下载）
  - 完善分享链接格式（添加 insecure 参数）
- ✨ 新增: **Any-Reality 协议支持**
  - AnyTLS + Reality 组合协议
  - 自动生成 Reality 密钥对
  - 支持自定义目标网站和 SNI
- 🔧 改进: sing-box 菜单优化
  - 添加 AnyTLS 和 Any-Reality 选项
  - 自动版本检查和升级
- 📚 文档: 新增详细配置文档
  - `ANYTLS_ANALYSIS.md` - 协议分析
  - `ANYTLS_INTEGRATION_REPORT.md` - 集成报告
  - `ANYTLS_QUICK_REFERENCE.md` - 快速参考
- 🙏 致谢: 感谢 [argosbx](https://github.com/yonggekkk/argosbx) 提供参考实现

### v1.1.0 (2025-12-24)

- ✨ 新增: **跳板服务器模块** (SSH远程管理)
  - 服务器列表管理
  - SSH 跳板链 (多跳连接)
  - 端口转发 (本地/远程/SOCKS5)
  - 批量执行命令和文件上传
- ✨ 新增: **Argo 节点模块** (Cloudflare隧道)
  - VLESS+WS+Argo
  - VMess+WS+Argo
  - 临时隧道和Token固定隧道
- ✨ 新增: **sing-box 多协议组合**
  - 自定义组合 (多选协议)
  - 预设组合 (一键安装)
  - 支持 5 种协议
- ✨ 新增: **系统重置功能**
  - 重置 VPS-play 数据
  - 重置单个模块
  - 系统完全重置 (VPS/FreeBSD/Serv00/Hostuno)

### v1.0.0 (2025-12-19)

- ✨ 初始版本发布
- ✅ 9个功能模块
- ✅ 环境自动检测
- ✅ Serv00/Hostuno 兼容性检测
- ✅ 统一端口管理
- ✅ 系统清理功能
- ✅ 多种保活方式

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

GPL-3.0 License

**重要说明**：本项目参考了 GPL-3.0 许可的 [argosbx](https://github.com/yonggekkk/argosbx) 项目（AnyTLS 协议实现），因此整个项目采用 GPL-3.0 许可证，以确保合法合规。

根据 GPL-3.0 许可证：
- ✅ 您可以自由使用、修改和分发本项目
- ✅ 您可以用于商业目的
- ⚠️ 您必须开源您的修改版本
- ⚠️ 您必须保持相同的 GPL-3.0 许可证
- ⚠️ 您必须提供完整的源代码

详细条款请查看 [LICENSE](LICENSE) 文件。

## 🙏 致谢

本项目参考了以下优秀项目：
- [argosbx](https://github.com/yonggekkk/argosbx) - AnyTLS 协议实现参考
- [serv00-play](https://github.com/frankiejun/serv00-play)
- [GostXray](https://github.com/hxzlplp7/GostXray)
- [serv00-xui](https://github.com/hxzlplp7/serv00-xui)
- [Misaka-blog sing-box](https://github.com/Misaka-blog)

## 📞 联系方式

- GitHub Issues: [提交问题](https://github.com/hxzlplp7/vps-play/issues)

---

⭐ 如果这个项目对你有帮助，请给个 Star！

