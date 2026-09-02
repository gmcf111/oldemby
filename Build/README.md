# OldEmby iPad 2 自动部署脚本

## 前提条件

### 必需工具
- **GitHub CLI (gh)** - 用于触发和下载构建
  - 安装: `winget install GitHub.cli`
  - 认证: `gh auth login`

- **SSH 客户端** - Windows 自带 OpenSSH
  - 确保 iPad 2 已越狱并开启 SSH 服务

- **jq** - 用于 JSON 解析（仅 bash 版本需要）
  - 安装: `winget install jqlang.jq`

### 可选工具（用于密码认证）
- **sshpass** - 非交互式 SSH 密码输入
  - Windows: 需要通过 WSL 或 Git Bash 安装
  - 建议: 配置 SSH 密钥认证，避免使用密码

## iPad 2 配置

### 1. 确保 iPad 2 已越狱
- 使用 evasi0n 或 pangu 越狱

### 2. 开启 SSH
- 安装 OpenSSH 或 Dropbear
- 确保 iPad 和电脑在同一网络

### 3. 配置 SSH 密钥（推荐）
```bash
# 在电脑上生成密钥
ssh-keygen -t rsa -b 2048

# 复制公钥到 iPad
ssh-copy-id root@<iPad-IP>
```

## 使用方法

### PowerShell 版本（Windows 推荐）

```powershell
# 基本用法（使用密钥认证）
.\deploy.ps1 -iPadIP "192.168.1.100"

# 使用密码认证
.\deploy.ps1 -iPadIP "192.168.1.100" -iPadPassword "your_password"

# 指定构建类型
.\deploy.ps1 -iPadIP "192.168.1.100" -BuildType "debug"
```

### Bash 版本（Git Bash / WSL / Linux）

```bash
# 基本用法
./deploy.sh -i 192.168.1.100

# 使用密码认证
./deploy.sh -i 192.168.1.100 -u root -p "your_password"

# 指定构建类型
./deploy.sh -i 192.168.1.100 -t debug
```

## 脚本执行流程

1. **触发构建** - 调用 GitHub Actions 构建 OldEmby
2. **等待完成** - 监控构建状态（最多 15 分钟）
3. **下载产物** - 获取构建好的 IPA 文件
4. **传输到 iPad** - 使用 SCP 传输 IPA
5. **安装应用** - 在 iPad 上执行 dpkg 安装
6. **清理文件** - 删除临时文件

## 故障排除

### 1. 构建失败
- 检查 GitHub Actions 日志: `gh run view <run-id> -r gmcf111/oldemby`
- 确认 GitHub CLI 已认证: `gh auth status`

### 2. SSH 连接失败
```bash
# 测试 SSH 连接
ssh root@<iPad-IP>

# 检查 iPad SSH 服务
# 在 iPad 上使用终端检查 sshd 是否运行
```

### 3. 安装失败
- 确保 iPad 已越狱
- 检查 dpkg 是否可用
- 手动安装测试: `dpkg -i /tmp/OldEmby-*.ipa`

### 4. 临时文件清理
脚本会自动清理，如需手动清理:
```powershell
Remove-Item -Recurse -Force .\temp
```

## 文件说明

- `deploy.ps1` - PowerShell 脚本（Windows 原生）
- `deploy.sh` - Bash 脚本（跨平台）
- `README.md` - 本文档

## 注意事项

- 首次运行时，GitHub Actions 可能需要几分钟启动
- iPad 2 需要保持开机和网络连接
- 建议使用稳定的 WiFi 网络进行传输
- IPA 文件会自动从 Build 目录删除，如需保留可修改脚本
