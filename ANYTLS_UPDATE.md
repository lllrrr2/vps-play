# VPS-play AnyTLS 协议更新

## 更新内容

### 🎉 新增功能

1. **改进 AnyTLS 协议支持**
   - 添加 `padding_scheme` 字段
   - 完善分享链接格式（添加 `insecure=1&allowInsecure=1` 参数）
   - 实现三层证书备用方案（EC → RSA → 远程下载）
   - 改进 JSON 配置输出

2. **新增 Any-Reality 协议**
   - AnyTLS + Reality 组合协议
   - 自动生成 Reality 密钥对
   - 支持自定义目标网站和 SNI
   - 完整的分享链接生成

3. **菜单更新**
   - sing-box 菜单新增 "Any-Reality" 选项
   - 菜单编号从 0-13 扩展到 0-14

## 代码来源

参考 **argosbx** 项目的实现：
- GitHub: https://github.com/yonggekkk/argosbx
- 作者: yonggekkk

## 主要文件变更

- `modules/singbox/manager.sh`:
  - 改进 `install_anytls()` 函数（约 150 行）
  - 新增 `install_any_reality()` 函数（约 170 行）
  - 更新 `show_singbox_menu()` 函数

## 使用方法

### 安装 AnyTLS

```bash
bash start.sh
# → 1. sing-box 节点
# → 4. AnyTLS (新)
```

### 安装 Any-Reality

```bash
bash start.sh
# → 1. sing-box 节点
# → 5. Any-Reality (AnyTLS + Reality)
```

## 技术要求

- sing-box v1.12.0+（脚本会自动升级）
- 客户端需支持 AnyTLS 协议（sing-box 或 Clash Meta）

## 详细文档

- **分析文档**: `ANYTLS_ANALYSIS.md`
- **完整报告**: `ANYTLS_INTEGRATION_REPORT.md`

## 测试状态

- ✅ 代码已集成
- ⚠️ 待实际环境测试
- 📝 文档已完善

## 致谢

感谢 yonggekkk 提供的 argosbx 脚本实现参考。

---

**更新时间**: 2025-12-26  
**版本**: v1.1.0
