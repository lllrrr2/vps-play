# VPS-play 项目总结

## 项目概述

VPS-play 是一个通用的 VPS 管理工具，设计目标是在一个统一的界面下管理多种服务和工具，同时自动适配不同的运行环境。

## 核心设计理念

### 1. 环境自适应

脚本会自动检测运行环境并调整行为：
- **普通 VPS**: 使用 systemd 管理服务，iptables 管理端口
- **NAT VPS**: 使用 socat 进行端口转发
- **FreeBSD**: 使用 rc.d 或 cron 管理服务
- **Serv00/Hostuno**: 使用 devil 管理端口，cron 保活

### 2. 模块化架构

每个功能独立成模块，便于维护和扩展：
```
modules/
├── singbox/    # sing-box 代理节点
├── gost/       # GOST 流量中转
├── xui/        # X-UI 面板
├── frpc/       # FRPC 客户端
├── frps/       # FRPS 服务端
├── cloudflared/# Cloudflare 隧道
├── nezha/      # 哪吒监控
├── warp/       # WARP 代理
└── docker/     # Docker 管理
```

### 3. 统一工具库

所有模块共享一套工具库：
- `env_detect.sh` - 环境检测
- `port_manager.sh` - 端口管理
- `process_manager.sh` - 进程管理
- `network.sh` - 网络工具
- `system_clean.sh` - 系统清理

## 功能列表

### 代理节点
| 模块 | 功能 | Serv00 支持 |
|------|------|-------------|
| sing-box | Hysteria2/TUIC/VLESS Reality | ✅ |
| GOST | TCP/UDP 端口转发 | ✅ |
| X-UI | 可视化面板 | ❌ |

### 内网穿透
| 模块 | 功能 | Serv00 支持 |
|------|------|-------------|
| FRPC | 内网穿透客户端 | ✅ |
| FRPS | 内网穿透服务端 | ❌ |
| Cloudflared | Cloudflare Tunnel | ✅ |

### 系统工具
| 模块 | 功能 | Serv00 支持 |
|------|------|-------------|
| 哪吒监控 | 服务器监控 Agent | ✅ |
| WARP | IP 代理 | ❌ |
| Docker | 容器管理 | ❌ |

### 内置工具
- 端口管理 (添加/删除/列出)
- 进程管理 (启动/停止/查看)
- 网络工具 (IP/端口测试)
- 环境检测 (系统/权限/网络)
- 保活设置 (Cron 任务)
- 系统清理 (释放磁盘空间)

## 技术实现

### 路径检测
```bash
# 多方法检测脚本目录
1. BASH_SOURCE[0] + dirname
2. $0 + dirname
3. 常见安装路径遍历
4. 健全性检查 (防止误判为子目录)
```

### 环境缓存
```bash
# 首次检测后保存到 env.conf
~/.vps-play/env.conf
# 后续启动直接加载，加速启动
```

### 错误处理
```bash
# 函数存在性检查
if type function_name &>/dev/null; then
    function_name
else
    echo "功能未加载，提供备用方案"
fi
```

## 使用方式

### 安装
```bash
curl -sL https://raw.githubusercontent.com/hxzlplp7/vps-play/main/install.sh | bash
```

### 运行
```bash
vps-play
```

### 更新
```bash
# 在菜单中选择 16. 更新脚本
# 或重新运行安装命令
```

## 文件结构

```
~/vps-play/           # 安装目录
├── start.sh          # 主入口
├── install.sh        # 安装脚本
├── utils/            # 工具库
├── modules/          # 功能模块
├── keepalive/        # 保活脚本
└── config/           # 配置目录

~/.vps-play/          # 数据目录
├── env.conf          # 环境配置缓存
├── gost/             # GOST 数据
├── singbox/          # sing-box 数据
└── ...               # 其他模块数据

~/bin/vps-play        # 快捷命令
```

## 版本历史

### v1.0.0 (2025-12-19)
- 初始正式版本
- 9个功能模块
- 5个系统工具
- 多环境支持
- Serv00/Hostuno 完整兼容

## 许可证

MIT License

## 相关链接

- GitHub: https://github.com/hxzlplp7/vps-play
- Issues: https://github.com/hxzlplp7/vps-play/issues
