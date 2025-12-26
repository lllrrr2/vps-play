# 许可证更新说明

## 更新时间

2025-12-26

## 更新内容

VPS-play 项目许可证已从 **MIT License** 更新为 **GPL-3.0 License**

## 更新原因

### 法律合规性

本项目的 AnyTLS 协议实现参考了 [argosbx](https://github.com/yonggekkk/argosbx) 项目，该项目使用 **GPL-3.0 许可证**。

根据 GPL-3.0 许可证第 5 条规定：
> "You must license the entire work, as a whole, under this License to anyone who comes into possession of a copy."

因此，为确保合法合规，我们将整个项目更新为 GPL-3.0 许可证。

## GPL-3.0 许可证说明

### ✅ 您可以：

1. **自由使用**：在任何环境下使用本项目
2. **自由修改**：根据您的需求修改源代码
3. **自由分发**：将本项目分发给他人
4. **商业使用**：用于商业目的（但必须开源）

### ⚠️ 您必须：

1. **保持开源**：您的修改版本也必须开源
2. **相同许可**：使用相同的 GPL-3.0 许可证
3. **提供源码**：向用户提供完整的源代码
4. **声明修改**：明确标注您所做的修改
5. **保留版权**：保留原始版权声明

### ❌ 您不可以：

1. **闭源使用**：将本项目用于闭源产品
2. **隐藏源码**：不提供源代码
3. **更改许可**：使用其他不兼容的许可证

## 对用户的影响

### 对普通用户

**几乎没有影响**：
- ✅ 您仍然可以免费使用本项目
- ✅ 您仍然可以修改和分发
- ✅ 功能保持不变

### 对开发者

**需要注意**：
- ⚠️ 如果您修改了代码并分发，必须开源
- ⚠️ 如果您在项目中使用本代码，也需要使用 GPL-3.0
- ⚠️ 不能将本项目集成到闭源商业软件中

### 兼容性

GPL-3.0 与以下许可证兼容：
- ✅ GPL-2.0 (可升级)
- ✅ LGPL-3.0
- ✅ AGPL-3.0
- ✅ Apache-2.0 (单向兼容)

GPL-3.0 与以下许可证**不兼容**：
- ❌ MIT (不能用于闭源)
- ❌ BSD (不能用于闭源)
- ❌ Apache-2.0 (双向不兼容)
- ❌ 专有许可证

## 文件变更

### 新增文件

- `LICENSE` - GPL-3.0 完整许可证文本

### 修改文件

- `README.md` - 更新许可证说明
- `start.sh` - 添加 GPL-3.0 版权声明头
- `modules/singbox/manager.sh` - 添加 GPL-3.0 版权声明头

## 参考资料

### GPL-3.0 官方资源

- 完整文本：https://www.gnu.org/licenses/gpl-3.0.txt
- 官方说明：https://www.gnu.org/licenses/gpl-3.0.html
- FAQ：https://www.gnu.org/licenses/gpl-faq.html

### 为什么选择 GPL-3.0？

1. **保护开源**：确保代码始终开源
2. **法律合规**：遵守引用项目的许可证要求
3. **社区精神**：与开源社区价值观一致
4. **专利保护**：GPL-3.0 包含专利授权条款

### 其他使用 GPL-3.0 的知名项目

- Linux 内核 (GPL-2.0)
- Git (GPL-2.0)
- WordPress (GPL-2.0)
- QEMU (GPL-2.0)
- Bash (GPL-3.0)
- GCC (GPL-3.0)

## 如果您不同意？

如果您不能接受 GPL-3.0 许可证，您有以下选择：

1. **使用旧版本**：使用 v1.1.0 及之前的 MIT 版本（不包含 AnyTLS）
2. **自行实现**：不使用 argosbx 的代码自行实现 AnyTLS
3. **联系我们**：讨论特殊许可安排（需获得所有贡献者同意）

## 致谢

特别感谢 [argosbx](https://github.com/yonggekkk/argosbx) 项目提供的优秀 AnyTLS 实现参考。

## 问题反馈

如果您对许可证有任何疑问，请通过以下方式联系：

- GitHub Issues: https://github.com/hxzlplp7/vps-play/issues
- 提问前请先阅读 GPL-3.0 FAQ

---

**本文档最后更新**：2025-12-26  
**生效版本**：v1.2.0 及以后
