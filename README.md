# ZeroTier 安装指南

> 版本: 1.1  
> 最后更新: 2023-06-01

## 目录
- [简介](#简介)
- [系统要求](#系统要求)
- [安装步骤](#安装步骤)
  - [Linux 系统安装](#linux-系统安装)
  - [Windows 系统安装](#windows-系统安装)
  - [macOS 系统安装](#macos-系统安装)
  - [Android 安装](#android-安装)
  - [iOS 安装](#ios-安装)
- [安装后配置](#安装后配置)
  - [创建或加入网络](#创建或加入网络)
  - [配置网络权限](#配置网络权限)
  - [路由设置](#路由设置)
- [常见问题排查](#常见问题排查)
- [高级配置](#高级配置)
  - [配置 ZeroTier 作为代理服务器](#配置-zerotier-作为代理服务器)
  - [配置 ZeroTier 中继（Moon）节点](#配置-zerotier-中继moon节点)
  - [配置 ZeroTier 普通中继（Relay）节点](#配置-zerotier-普通中继relay节点)
  - [命令行工具](#命令行工具)
  - [本地配置文件](#本地配置文件)
  - [多路径设置](#多路径设置)
  - [性能监控与日志分析](#性能监控与日志分析)
  - [配置向导与状态仪表板](#配置向导与状态仪表板)
- [与OpenVPN配合使用](#与openvpn配合使用)
- [参考资料](#参考资料)

## 简介

ZeroTier 是一个智能网络虚拟化工具，它可以将分散在各地的设备连接到一个虚拟局域网中，就像这些设备都在同一个物理网络中一样。ZeroTier 结合了 VPN 和 SDN（软件定义网络）的特点，提供了一种简单、安全且高效的方式来构建全球性的虚拟网络。

**主要特点：**
- 点对点连接：尽可能建立直接连接，减少延迟
- 端到端加密：使用强加密保护所有通信
- 跨平台支持：几乎支持所有主流操作系统和设备
- 简单易用：安装配置过程简单直观
- 可扩展性：可以连接数千台设备到同一个虚拟网络
- 中继节点：支持配置自定义中继（Moon）节点，提高连接稳定性和性能

## 系统要求

ZeroTier 支持多种操作系统和平台，基本系统要求如下：

- **Windows**：Windows 7 及以上版本
- **macOS**：macOS 10.10 (Yosemite) 及以上版本
- **Linux**：内核 2.6.32 及以上版本，支持大多数主流发行版
- **FreeBSD**：11.0 及以上版本
- **Android**：Android 5.0 及以上版本
- **iOS**：iOS 9.0 及以上版本

网络要求：
- 互联网连接
- 对于最佳性能，建议允许 UDP 通信（端口 9993）

## 快速安装指南

> 想要快速开始？根据您的操作系统选择以下快速安装方式：

| 操作系统 | 快速安装方法 |
|---------|------------|
| **Windows** | 下载并运行 [Windows 安装程序](https://www.zerotier.com/download/) (.msi) |
| **macOS** | 下载并运行 [macOS 安装程序](https://www.zerotier.com/download/) (.pkg) |
| **Linux** | 下载脚本: `curl -s -o install.sh https://raw.githubusercontent.com/rockyshi1993/zerotier-install/main/install.sh`<br>然后执行: `sudo bash install.sh` |
| **Android** | 从 [Google Play](https://play.google.com/store/apps/details?id=com.zerotier.one) 安装 |
| **iOS** | 从 [App Store](https://apps.apple.com/us/app/zerotier-one/id1084101492) 安装 |

安装后，您需要[创建或加入网络](#创建或加入网络)才能开始使用 ZeroTier。

## 详细安装步骤

### Linux 系统安装

#### 安装方法比较

| 安装方法 | 优点 | 适用场景 |
|---------|------|---------|
| **本仓库脚本** | • 自动化安装和配置<br>• 支持代理服务器功能<br>• 支持中继（Moon）节点配置<br>• 提供交互式菜单 | 需要完整功能和简化配置的用户 |
| **官方脚本** | • 官方支持<br>• 简单直接 | 只需基本功能的用户 |

#### 方法 1: 使用本仓库提供的增强安装脚本（推荐）

本仓库提供的脚本不仅可以安装 ZeroTier，还提供以下增强功能：

- 自动检测系统类型并使用适当的安装方法
- 交互式配置选项
- 代理服务器功能配置
- 中继（Moon）节点配置和管理
- 自动加入网络选项
- 故障排除和诊断功能

```bash
# 下载安装脚本
curl -s -o install.sh https://raw.githubusercontent.com/rockyshi1993/zerotier-install/main/install.sh

# 执行安装脚本
sudo bash install.sh
```

#### 方法 2: 使用官方一键安装脚本

如果您只需要基本安装，可以使用官方提供的一键安装脚本：

```bash
curl -s https://install.zerotier.com | sudo bash
```


#### 安装后启动服务

无论使用哪种安装方法，都需要启动服务并加入网络：

```bash
# 启动 ZeroTier 服务
sudo systemctl enable zerotier-one
sudo systemctl start zerotier-one

# 加入网络
sudo zerotier-cli join <network-id>
```

> **提示**: 使用本仓库的安装脚本时，这些步骤会自动完成或通过交互式菜单引导您完成。


### Windows 系统安装

1. 访问 [ZeroTier 官方下载页面](https://www.zerotier.com/download/)
2. 下载 Windows 安装程序（.msi 文件）
3. 双击下载的文件，启动安装向导
4. 按照安装向导的提示完成安装：
   - 接受许可协议
   - 选择安装位置（建议使用默认位置）
   - 点击"安装"按钮
5. 安装完成后，ZeroTier 会在系统托盘中显示一个图标
6. 右键点击托盘图标，选择"Join Network..."
7. 输入您的网络 ID（16 位字符），点击"Join"

**注意**：首次安装时，Windows 可能会显示防火墙警告，请确保允许 ZeroTier 通过防火墙。

### macOS 系统安装

1. 访问 [ZeroTier 官方下载页面](https://www.zerotier.com/download/)
2. 下载 macOS 安装包（.pkg 文件）
3. 双击下载的文件，启动安装向导
4. 按照安装向导的提示完成安装：
   - 点击"继续"
   - 接受许可协议
   - 选择安装位置（建议使用默认位置）
   - 输入管理员密码
   - 点击"安装"按钮
5. 安装完成后，ZeroTier 会在菜单栏中显示一个图标
6. 点击菜单栏图标，选择"Join Network..."
7. 输入您的网络 ID，点击"Join"

**注意**：macOS 可能会要求您在"系统偏好设置 > 安全性与隐私"中批准 ZeroTier 的系统扩展。


### 移动设备安装

#### Android 安装

1. **获取应用**:
   - 在 Google Play 商店中搜索 "ZeroTier"
   - 或直接访问 [ZeroTier 在 Google Play 的页面](https://play.google.com/store/apps/details?id=com.zerotier.one)
   - 点击"安装"按钮

2. **配置应用**:
   - 安装完成后，打开 ZeroTier 应用
   - 点击"+"按钮，输入您的网络 ID
   - 点击"Add Network"按钮
   - 在权限请求提示中，点击"允许"授予 VPN 权限

3. **验证连接**:
   - 成功加入网络后，状态会显示为"ONLINE"
   - 您可以在应用中查看分配的 IP 地址

> **注意**: Android 设备上的 ZeroTier 会在后台运行，并在设备重启后自动启动。如果您遇到连接问题，可以尝试在应用中重新连接网络。

#### iOS 安装

1. **获取应用**:
   - 在 App Store 中搜索 "ZeroTier"
   - 或直接访问 [ZeroTier 在 App Store 的页面](https://apps.apple.com/us/app/zerotier-one/id1084101492)
   - 点击"获取"按钮，然后点击"安装"

2. **配置应用**:
   - 安装完成后，打开 ZeroTier 应用
   - 点击"+"按钮，输入您的网络 ID
   - 点击"Add"按钮
   - 在权限请求提示中，点击"允许"授予 VPN 权限

3. **验证连接**:
   - 成功加入网络后，状态会显示为"ONLINE"
   - 您可以在应用中查看分配的 IP 地址

> **注意**: 由于 iOS 的限制，ZeroTier 在后台运行时可能会被系统暂停。如果您需要持续连接，可以在设备设置中启用"后台应用刷新"功能。

## 安装后配置

完成 ZeroTier 安装后，您需要创建或加入一个网络，并进行适当的配置才能开始使用。以下是配置 ZeroTier 的完整流程：

### 创建或加入网络

#### 创建新网络（管理员）

如果您是首次使用 ZeroTier 或需要创建一个新的虚拟网络：

1. 访问 [ZeroTier Central](https://my.zerotier.com/)
2. 注册账号或登录现有账号
3. 在控制面板中点击 **"Create A Network"** 按钮
4. 系统会自动生成一个 16 位的网络 ID（例如：`a09acf0233e5d948`）
5. 记录此网络 ID，您将需要它来配置客户端

> **提示**：创建网络后，您可以在网络设置页面自定义网络名称、描述和访问控制设置。

#### 加入现有网络（客户端）

根据您的设备类型，使用以下方法加入网络：

| 操作系统 | 加入网络方法 |
|---------|------------|
| **Windows** | 右键点击系统托盘图标 → 选择"Join Network..." → 输入网络 ID → 点击"Join" |
| **macOS** | 点击菜单栏图标 → 选择"Join Network..." → 输入网络 ID → 点击"Join" |
| **Linux** | 在终端中运行：`sudo zerotier-cli join <network-id>` |
| **Android** | 打开应用 → 点击"+"按钮 → 输入网络 ID → 点击"Add Network" |
| **iOS** | 打开应用 → 点击"+"按钮 → 输入网络 ID → 点击"Add" |

### 配置网络权限（管理员）

出于安全考虑，默认情况下，新加入的设备需要网络管理员授权才能访问网络：

1. 登录 [ZeroTier Central](https://my.zerotier.com/)
2. 选择相应的网络
3. 在 **"Members"** 选项卡中，您将看到所有尝试加入网络的设备
4. 找到新加入的设备（通过其 Node ID 或名称）
5. 勾选 **"Auth"** 复选框，授权该设备加入网络
6. 可选：为设备添加描述性名称，便于管理

![ZeroTier授权示例](https://docs.zerotier.com/img/zt-central-auth-member.png)

> **注意**：只有在授权后，设备才能与网络中的其他成员通信。

### 路由设置（高级）

ZeroTier 网络可以配置路由，使网络成员能够访问特定的子网或互联网：

#### 基本路由配置

1. 登录 [ZeroTier Central](https://my.zerotier.com/)
2. 选择相应的网络
3. 在 **"Settings"** 选项卡中，找到 **"Managed Routes"** 部分
4. 点击 **"Add Route"** 按钮
5. 配置路由：
   - **Destination**: 目标网络（例如：`192.168.1.0/24`）
   - **Via**: 网关（通常是充当网关的 ZeroTier 成员的 IP 地址）
6. 点击 **"Submit"** 保存路由

#### 常见路由配置场景

| 目的 | 路由配置 | 说明 |
|-----|---------|-----|
| **访问内部网络** | `192.168.1.0/24` via `10.147.20.5` | 允许访问网关设备所在的内部网络 |
| **互联网访问** | `0.0.0.0/0` via `10.147.20.5` | 通过网关设备访问互联网（代理服务器） |
| **多个子网访问** | `10.0.0.0/8` via `10.147.20.5` | 访问多个私有网络子网 |

> **提示**：配置路由时，确保网关设备已正确配置为允许流量转发，并且已启用适当的防火墙规则。

## 常见问题排查

### 快速诊断工具

在排查问题前，可以使用以下命令获取有用的诊断信息：

```bash
# 查看 ZeroTier 状态
zerotier-cli info

# 查看已加入的网络
zerotier-cli listnetworks

# 查看对等连接
zerotier-cli peers

# 查看路由表
ip route show
```

### 常见问题及解决方案

#### 安装问题

| 问题 | 可能原因 | 解决方案 |
|-----|---------|---------|
| 安装脚本失败 | 网络连接问题 | 检查互联网连接，尝试使用 `--proxy` 参数指定代理 |
| 权限错误 | 未使用 sudo/管理员权限 | 使用 `sudo` (Linux/macOS) 或以管理员身份运行 (Windows) |
| 安装后找不到命令 | 路径问题 | 重启终端或重启系统 |

#### 连接问题

##### 1. 无法加入网络

**症状**: 尝试加入网络时出错或加入后显示 "NOT_FOUND"

**解决方案**:
- 仔细检查网络 ID 是否正确（应为 16 位十六进制字符）
- 确认互联网连接正常
- 检查防火墙是否阻止了 UDP 端口 9993
- 尝试重启 ZeroTier 服务：
  ```bash
  # Linux
  sudo systemctl restart zerotier-one

  # macOS
  sudo launchctl unload /Library/LaunchDaemons/com.zerotier.one.plist
  sudo launchctl load /Library/LaunchDaemons/com.zerotier.one.plist

  # Windows (管理员 PowerShell)
  Restart-Service ZeroTierOneService
  ```

##### 2. 加入网络但无法通信

**症状**: 成功加入网络，但无法与其他设备通信

**解决方案**:
- 检查是否已在 ZeroTier Central 中授权设备（勾选 "Auth" 复选框）
- 检查网络设置中的 IP 分配是否正确
- 验证网络状态：
  ```bash
  zerotier-cli listnetworks
  ```
  确保状态显示为 "OK" 且有分配的 IP 地址
- 检查本地防火墙设置，确保允许 ZeroTier 流量
- 尝试 ping 其他网络成员的 ZeroTier IP 地址

##### 3. 连接速度慢

**症状**: 连接建立但速度明显慢于预期

**解决方案**:
- 检查是否建立了直接连接：
  ```bash
  zerotier-cli peers
  ```
  如果显示 "RELAY"，表示使用了中继服务器
- 调整防火墙设置，允许直接 UDP 通信
- 检查网络拥塞情况
- 考虑使用多路径设置提高可靠性

#### 特定平台问题

##### Windows 特有问题

- **服务未运行**: 打开服务管理器，确保 "ZeroTier One" 服务已启动
- **TAP 适配器问题**: 在设备管理器中检查网络适配器，如有感叹号，尝试重新安装驱动
- **防火墙阻止**: 检查 Windows Defender 防火墙设置，确保允许 ZeroTier

##### macOS 特有问题

- **系统扩展被阻止**: 在"系统偏好设置 > 安全性与隐私"中允许 ZeroTier 系统扩展
- **权限问题**: 确保 ZeroTier 有足够的系统权限
- **Big Sur 及更高版本**: 可能需要在"系统偏好设置 > 网络"中手动启用 ZeroTier 接口

##### Linux 特有问题

- **模块加载问题**: 确保 TUN/TAP 模块已加载：
  ```bash
  lsmod | grep tun
  ```
  如果未加载，运行：
  ```bash
  sudo modprobe tun
  ```
- **SELinux 干扰**: 临时禁用 SELinux 检查问题是否解决：
  ```bash
  sudo setenforce 0
  ```

#### 防火墙配置问题

ZeroTier 需要 UDP 端口 9993 开放才能正常工作。以下是在不同系统上配置防火墙的方法：

##### 使用安装脚本配置防火墙

本仓库提供的安装脚本可以自动配置防火墙规则：

```bash
# 下载安装脚本
curl -s -o install.sh https://raw.githubusercontent.com/rockyshi1993/zerotier-install/main/install.sh

# 执行安装脚本
sudo bash install.sh
```

在安装过程中，脚本会自动检测并配置防火墙。

##### 手动配置防火墙

###### UFW (Ubuntu/Debian)

```bash
# 确保 SSH 端口开放（重要！避免远程连接被锁定）
sudo ufw allow 22/tcp

# 允许 ZeroTier 端口
sudo ufw allow 9993/udp

# 启用 UFW（如果尚未启用）
sudo ufw enable

# 检查状态
sudo ufw status
```

###### firewalld (CentOS/RHEL/Fedora)

```bash
# 允许 ZeroTier 端口
sudo firewall-cmd --permanent --add-port=9993/udp

# 重载防火墙规则
sudo firewall-cmd --reload

# 检查状态
sudo firewall-cmd --list-ports
```

###### iptables

```bash
# 允许 ZeroTier 端口
sudo iptables -A INPUT -p udp --dport 9993 -j ACCEPT

# 保存规则（根据系统不同）
# Debian/Ubuntu
sudo apt-get install iptables-persistent
sudo netfilter-persistent save

# CentOS/RHEL
sudo service iptables save

# 检查状态
sudo iptables -L | grep 9993
```

###### Windows Defender 防火墙

1. 打开 Windows Defender 防火墙设置（控制面板 > 系统和安全 > Windows Defender 防火墙）
2. 点击"允许应用或功能通过 Windows Defender 防火墙"
3. 点击"更改设置"，然后点击"允许其他应用"
4. 浏览并选择 ZeroTier One 程序（通常位于 `C:\Program Files (x86)\ZeroTier\One\ZeroTier One.exe`）
5. 确保同时勾选"专用"和"公用"网络

###### macOS 防火墙

1. 打开系统偏好设置 > 安全性与隐私 > 防火墙
2. 点击"防火墙选项"
3. 确保 ZeroTier One 应用程序被设置为"允许传入连接"

##### 验证防火墙配置

配置完成后，可以使用以下命令验证端口是否开放：

```bash
# 使用 netcat 检查（Linux/macOS）
nc -zuv localhost 9993

# 使用在线端口检查工具
# 访问 https://portchecker.co/ 并检查 UDP 端口 9993
```

### 常见错误代码及含义

| 错误代码 | 含义 | 解决方法 |
|---------|------|---------|
| **ACCESS_DENIED** | 未获授权加入网络 | 联系网络管理员授权您的设备 |
| **NETWORK_NOT_FOUND** | 网络 ID 不存在 | 检查网络 ID 是否正确 |
| **AUTHENTICATION_REQUIRED** | 需要身份验证 | 检查凭据或重新登录 ZeroTier Central |
| **PORT_ERROR** | 端口冲突或无法绑定 | 检查是否有其他服务占用 9993 端口 |
| **IDENTITY_COLLISION** | 节点 ID 冲突 | 删除 `/var/lib/zerotier-one/identity.secret` 并重启服务 |

> **提示**: 如果遇到无法解决的问题，可以查看日志文件获取更多信息：
> - Linux: `/var/log/syslog` 或 `journalctl -u zerotier-one`
> - macOS: `sudo tail -f /var/log/system.log | grep ZeroTier`
> - Windows: 事件查看器 > 应用程序和服务日志 > ZeroTier

## 高级配置

### 配置 ZeroTier 作为代理服务器

ZeroTier 可以配置为代理服务器，允许其他 ZeroTier 客户端通过此服务器访问互联网和私有网络。这在以下场景特别有用：

- 为没有直接互联网访问权限的设备提供互联网连接
- 允许远程设备访问代理服务器所在的私有网络资源
- 创建一个集中式的网络出口点，便于管理和监控

#### 使用安装脚本配置代理服务器

如果您使用本仓库提供的安装脚本，可以在安装过程中轻松配置代理服务器：

```bash
# 下载安装脚本
curl -s -o install.sh https://raw.githubusercontent.com/rockyshi1993/zerotier-install/main/install.sh

# 执行安装脚本
sudo bash install.sh
```

在安装过程中，脚本会询问是否将 ZeroTier 节点配置为代理服务器。选择"是"后，脚本将自动：

1. 启用 IP 转发
2. 配置 NAT（网络地址转换）
3. 设置必要的 iptables 规则
4. 使配置在系统重启后仍然生效

#### 手动配置代理服务器

如果您已经安装了 ZeroTier，也可以手动配置代理服务器功能：

1. 启用 IP 转发：
   ```bash
   # 1. 创建新的系统服务
    sudo sh -c 'cat > /etc/systemd/system/ip-forward.service << EOL
    [Unit]
    Description=Enable IP Forwarding
    After=network.target

    [Service]
    Type=oneshot
    ExecStart=/usr/sbin/sysctl -w net.ipv4.ip_forward=1
    RemainAfterExit=yes

    [Install]
    WantedBy=multi-user.target
    EOL'

    # 2. 启用并启动服务
    sudo systemctl enable ip-forward.service
    sudo systemctl start ip-forward.service
   ```

2. 配置 NAT 和 iptables 规则：
   ```bash
   # 获取网络接口名称
   ZT_INTERFACE=$(ip -o link show | grep zt | awk -F': ' '{print $2}' | head -n 1)
   DEFAULT_INTERFACE=$(ip -o route get 8.8.8.8 | awk '{print $5}')

   # 添加 NAT 规则
   iptables -t nat -D POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE 2>/dev/null
   iptables -D FORWARD -i $ZT_INTERFACE -o $DEFAULT_INTERFACE -j ACCEPT 2>/dev/null
   iptables -D FORWARD -i $DEFAULT_INTERFACE -o $ZT_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null

   # 保存 iptables 规则
   iptables-save > /etc/iptables.rules
   ```

3. 使 iptables 规则持久化：
   ```bash
   # 使用 netfilter-persistent（Ubuntu 推荐方式）
   sudo apt install iptables-persistent
   sudo iptables-save > /etc/iptables/rules.v4
   ```

#### ZeroTier Central 配置

配置代理服务器后，您需要在 ZeroTier Central 中进行额外设置：

1. 登录 [ZeroTier Central](https://my.zerotier.com/)
2. 找到您的网络，点击进入网络设置页面
3. 在 'Managed Routes' 区域添加以下路由：
   - 添加路由：`0.0.0.0/0` via `[代理服务器的 ZeroTier IP]`（允许通过此服务器访问互联网）
   - 添加路由：`[代理服务器的私有网络子网，如 192.168.1.0/24]` via `[代理服务器的 ZeroTier IP]`（允许访问此服务器所在的私有网络）
4. 保存设置
5. 确保您的客户端设备已加入此网络并获得授权

完成上述配置后，您的 ZeroTier 客户端将能够：
- 通过代理服务器访问互联网
- 访问代理服务器所在的私有网络资源

#### 故障排除

如果代理服务器功能不正常，请检查以下几点：

1. 确认 IP 转发已启用：
   ```bash
   cat /proc/sys/net/ipv4/ip_forward
   ```
   应返回 `1`

2. 检查 iptables 规则是否正确配置：
   ```bash
   iptables -L -v
   iptables -t nat -L -v
   ```

3. 确保 ZeroTier Central 中的路由配置正确
4. 检查客户端设备是否已在 ZeroTier Central 中获得授权
5. 验证代理服务器的 ZeroTier 虚拟 IP 是否正确

### 命令行工具

ZeroTier 提供了强大的命令行工具，可用于高级配置和故障排除：

```bash
# 查看所有命令
zerotier-cli help

# 查看当前加入的网络
zerotier-cli listnetworks

# 查看节点信息
zerotier-cli info

# 查看对等节点
zerotier-cli peers

# 离开网络
zerotier-cli leave <network-id>
```

### 本地配置文件

ZeroTier 的配置文件位于以下位置：

- **Windows**：`C:\ProgramData\ZeroTier\One`
- **macOS**：`/Library/Application Support/ZeroTier/One`
- **Linux**：`/var/lib/zerotier-one`

主要配置文件包括：

- `identity.public`：公钥
- `identity.secret`：私钥（请保密）
- `networks.d/`：网络配置目录

### 配置 ZeroTier 中继（Moon）节点

Moon 节点是 ZeroTier 网络中的自定义根服务器，可以提供更稳定的连接和更好的网络性能，特别是在复杂的网络环境中。

#### Moon 节点的优势

- **改善连接稳定性**：提供额外的连接路径，减少连接失败的可能性
- **降低延迟**：在地理位置分散的网络中提供更近的连接点
- **增强 NAT 穿透能力**：帮助位于严格 NAT 后的设备建立连接
- **提高网络控制**：减少对 ZeroTier 公共根服务器的依赖
- **增强私有网络安全性**：可以完全在私有网络内运行，无需公共互联网

#### 使用安装脚本配置 Moon 节点

如果您使用本仓库提供的安装脚本，可以轻松配置 Moon 节点：

```bash
# 下载安装脚本
curl -s -o install.sh https://raw.githubusercontent.com/rockyshi1993/zerotier-install/main/install.sh

# 执行安装脚本
sudo bash install.sh
```

如果 ZeroTier 已安装，脚本会显示菜单选项。选择"配置中继（Moon）节点"选项，然后按照提示操作。脚本将自动：

1. 获取节点信息（ID 和公共 IP）
2. 创建必要的配置文件
3. 生成 Moon 节点签名
4. 部署 Moon 文件到当前节点
5. 创建客户端配置包，便于分发给其他设备
6. 重启 ZeroTier 服务以应用配置

完成后，脚本会显示 Moon ID 和客户端配置包的位置。

#### 手动配置 Moon 节点

如果您想手动配置 Moon 节点，可以按照以下步骤操作：

1. 获取节点 ID：
   ```bash
   zerotier-cli info | awk '{print $3}'
   ```

2. 创建 moon.json 配置文件：
   ```bash
   # 获取公共 IP
   PUBLIC_IP=$(curl -s https://api.ipify.org)

   # 创建配置文件
   cat > /tmp/moon.json << EOF
   {
       "id": "$(zerotier-cli info | awk '{print $3}')",
       "stableEndpoints": ["$PUBLIC_IP:9993"],
       "rootEndpoints": ["$PUBLIC_IP:9993"]
   }
   EOF
   ```

3. 生成 Moon 配置：
   ```bash
   zerotier-idtool initmoon /tmp/moon.json > /tmp/moon.conf
   ```

4. 提取 Moon ID：
   ```bash
   MOON_ID=$(grep -oP '(?<="id": ")[^"]*' /tmp/moon.conf)
   ```

5. 生成 Moon 文件：
   ```bash
   cd /tmp
   zerotier-idtool genmoon /tmp/moon.conf
   ```

6. 部署 Moon 文件：
   ```bash
   mkdir -p /var/lib/zerotier-one/moons.d
   cp /tmp/${MOON_ID}.moon /var/lib/zerotier-one/moons.d/
   ```

7. 重启 ZeroTier 服务：
   ```bash
   systemctl restart zerotier-one
   ```

#### 连接到 Moon 节点

其他 ZeroTier 客户端可以通过以下方式连接到您的 Moon 节点：

##### 使用客户端配置包（推荐）

如果您使用了安装脚本，脚本会生成一个客户端配置包，通常位于：
```
/path/to/zerotier_moon_<MOON_ID>.zip
```

将此包分发给需要连接的客户端，然后按照包中的 README.md 文件中的说明操作。

##### 手动连接

客户端可以使用以下命令手动连接到 Moon 节点：

```bash
zerotier-cli orbit <MOON_ID> <MOON_ID>
```

注意：需要输入两次 Moon ID，这不是错误。第一个参数是 Moon 的 ID，第二个参数是 Moon 的"世界 ID"，通常与 Moon ID 相同。

##### 验证连接

连接后，可以使用以下命令验证 Moon 节点是否正常工作：

```bash
zerotier-cli listpeers | grep MOON
```

如果显示了您的 Moon 节点，则表示连接成功。

#### 移除 Moon 节点

如果您需要移除 Moon 节点，可以使用安装脚本中的"移除中继（Moon）节点"选项，或手动执行以下操作：

```bash
# 移除 Moon 文件
rm -f /var/lib/zerotier-one/moons.d/*.moon

# 重启 ZeroTier 服务
systemctl restart zerotier-one
```

客户端上，可以使用以下命令取消连接到 Moon 节点：

```bash
zerotier-cli deorbit <MOON_ID>
```

### 配置 ZeroTier 普通中继（Relay）节点

除了 Moon 中继节点外，ZeroTier 还支持配置普通中继（Relay）节点。与 Moon 节点相比，普通中继节点的特点是：

- **自动发现**：客户端无需特殊配置即可自动发现并使用可用的中继节点
- **配置简单**：设置过程更简单，无需生成和分发客户端配置包
- **适用场景**：适合网络环境复杂，节点之间难以直接连接的情况

#### 普通中继节点与 Moon 节点的区别

| 特性 | 普通中继（Relay）节点 | Moon 中继节点 |
|------|---------------------|-------------|
| 客户端配置 | 无需特殊配置，自动发现 | 需要手动配置客户端连接到特定 Moon |
| 控制粒度 | 全局性，所有客户端可能使用 | 可控性强，只有配置了特定 Moon 的客户端才会使用 |
| 配置复杂度 | 简单 | 相对复杂，需要生成和分发配置 |
| 适用场景 | 一般性连接辅助 | 特定网络环境优化，私有网络控制 |

#### 使用安装脚本配置普通中继节点

如果您使用本仓库提供的安装脚本，可以轻松配置普通中继节点：

```bash
# 下载安装脚本
curl -s -o install.sh https://raw.githubusercontent.com/rockyshi1993/zerotier-install/main/install.sh

# 执行安装脚本
sudo bash install.sh
```

在安装脚本的菜单中，选择"配置中继节点"，然后选择"配置普通中继（Relay）节点"选项。

#### 手动配置普通中继节点

如果您已经安装了 ZeroTier，也可以手动配置普通中继节点：

1. 创建或修改 local.conf 文件：
   ```bash
   # 创建配置文件
   cat > /var/lib/zerotier-one/local.conf << EOF
   {
     "settings": {
       "allowTcpFallbackRelay": true,
       "allowDefault": true
     }
   }
   EOF
   ```

2. 设置正确的权限：
   ```bash
   chmod 644 /var/lib/zerotier-one/local.conf
   ```

3. 重启 ZeroTier 服务：
   ```bash
   # 使用 systemd
   systemctl restart zerotier-one

   # 或使用 service
   service zerotier-one restart
   ```

#### 验证普通中继节点功能

配置完成后，可以使用以下命令验证中继节点功能：

```bash
# 查看连接的对等节点
zerotier-cli listpeers

# 检查 UDP 端口 9993 是否开放
nc -zuv <您的公网IP> 9993
```

#### 监控中继节点性能

您可以使用安装脚本中的监控功能查看中继节点性能，或手动检查以下指标：

```bash
# 查看 CPU 和内存使用情况
top -bn1 | grep zerotier-one

# 查看连接数
zerotier-cli listpeers | wc -l
```

### 多路径设置

对于需要高可用性的环境，可以配置 ZeroTier 使用多个物理路径：

```bash
# 启用多路径
zerotier-cli set <network-id> allowMultipath=1

# 设置多路径模式（active-backup 或 broadcast）
zerotier-cli set <network-id> multipathMode=active-backup
```

### 性能监控与日志分析

ZeroTier 提供了多种方式来监控网络性能和分析日志，这对于排查问题和优化网络至关重要。

#### 性能监控

使用本仓库提供的安装脚本，您可以轻松监控 ZeroTier 节点的性能：

```bash
# 执行安装脚本
sudo bash install.sh
```

在菜单中选择"管理中继节点"，然后选择"监控中继节点性能"或"持续监控中继节点"选项。

##### 手动监控性能

您也可以使用以下命令手动监控 ZeroTier 的性能：

```bash
# 查看 CPU 和内存使用情况
ps -o pid,ppid,cmd,%mem,%cpu -p $(pgrep zerotier-one)

# 查看网络连接
zerotier-cli listpeers

# 查看网络流量（如果安装了 vnstat）
vnstat -i $(ip -o link show | grep zt | awk -F': ' '{print $2}' | head -n 1) -h 1
```

#### 日志分析

ZeroTier 的日志包含了重要的诊断信息，可以帮助您排查问题：

##### 使用安装脚本分析日志

在安装脚本菜单中选择"分析 ZeroTier 日志"选项，脚本将自动：

1. 收集系统日志中与 ZeroTier 相关的条目
2. 提取错误和警告信息
3. 分析连接事件和 Moon 节点事件
4. 生成综合报告

##### 手动查看日志

您也可以手动查看 ZeroTier 的日志：

```bash
# 在 Linux 系统上
journalctl -u zerotier-one --no-pager | tail -n 100

# 或者查看系统日志
grep -i "zerotier" /var/log/syslog | tail -n 100

# 在 macOS 上
sudo tail -f /var/log/system.log | grep ZeroTier

# 在 Windows 上（PowerShell）
Get-EventLog -LogName Application | Where-Object {$_.Source -like "*ZeroTier*"} | Select-Object -First 20
```

#### 检查更新

定期检查 ZeroTier 更新可以确保您获得最新的功能和安全修复：

```bash
# 使用安装脚本检查更新
sudo bash install.sh
```

在菜单中选择"检查更新"选项。

### 配置向导与状态仪表板

本仓库提供的安装脚本包含了配置向导和状态仪表板功能，可以简化 ZeroTier 的配置和监控过程。

#### 配置向导

配置向导提供了一种交互式方式来配置 ZeroTier：

```bash
# 执行安装脚本
sudo bash install.sh
```

在菜单中选择"配置向导"选项，然后按照提示进行操作。配置向导将引导您完成以下步骤：

1. 基本信息收集（节点 ID、公网 IP 等）
2. 选择配置类型（标准节点、中继节点或代理服务器）
3. 根据选择进行详细配置
4. 验证配置

#### 状态仪表板

状态仪表板提供了 ZeroTier 网络的实时概览：

```bash
# 执行安装脚本
sudo bash install.sh
```

在菜单中选择"状态仪表板"选项。仪表板将显示以下信息：

- 基本节点信息
- 网络连接状态
- Moon 节点信息
- 系统资源使用情况
- 连接统计
- 最近的日志条目
- 防火墙状态

这些工具可以帮助您更有效地管理和监控 ZeroTier 网络，特别是在复杂的网络环境中。

## 与OpenVPN配合使用

### 概述

当您需要同时使用 OpenVPN 和 ZeroTier 两种网络工具时，可能会遇到路由冲突问题。本章节详细说明了如何配置 OpenVPN 客户端，使其与 ZeroTier 和谐共存，实现不同网络流量的精确路由控制。

### 应用场景

这种配置特别适用于以下场景：
- **ZeroTier**：仅用于远程访问特定设备或内部网络资源
- **OpenVPN**：用于代理互联网流量（网络代理/VPN 隧道）

### OpenVPN 配置详解

要实现上述功能分离，需要在 OpenVPN 客户端配置文件中添加以下路由指令：

```
route-nopull
route 0.0.0.0 128.0.0.0
route 128.0.0.0 128.0.0.0
route 172.30.0.0 255.255.0.0 net_gateway
```

#### 每条配置的详细解释

1. **`route-nopull`**：
    - 作用：阻止 OpenVPN 服务器推送的路由表自动应用到客户端
    - 目的：允许客户端完全控制自己的路由配置
    - 重要性：防止服务器推送的路由覆盖本地配置，是实现精确路由控制的基础

2. **`route 0.0.0.0 128.0.0.0`** 和 **`route 128.0.0.0 128.0.0.0`**：
    - 作用：将所有 IPv4 流量路由到 OpenVPN 隧道
    - 技术细节：
        - 第一条路由覆盖 0.0.0.0 到 127.255.255.255 的 IP 地址范围
        - 第二条路由覆盖 128.0.0.0 到 255.255.255.255 的 IP 地址范围
        - 两条路由结合覆盖了整个 IPv4 地址空间（0.0.0.0/0）
    - 目的：确保所有普通互联网流量通过 VPN 隧道传输

3. **`route 172.30.0.0 255.255.0.0 net_gateway`**：
    - 作用：将发往 172.30.0.0/16 网段的流量通过本地网关（而非 VPN 隧道）发送
    - 技术解释：
        - `172.30.0.0`：目标网络地址（ZeroTier 网络）
        - `255.255.0.0`：子网掩码，表示整个 172.30.x.x 网段
        - `net_gateway`：指定使用本地默认网关，而非 VPN 网关
    - 目的：确保 ZeroTier 相关流量不经过 OpenVPN 隧道，避免路由循环和连接问题

### ZeroTier 网络地址说明

- **172.30.0.0/16** 是一个常见的 ZeroTier 虚拟网络地址段，通常分配给连接到 ZeroTier 网络的设备
- 您的实际 ZeroTier 网络可能使用不同的地址段，需要根据实际情况调整配置
- 重要提示：如果您的 ZeroTier 网络使用不同地址段，必须修改上述配置中的 `172.30.0.0 255.255.0.0` 为您的实际网段

### 如何确定您的 ZeroTier 网络地址

可通过以下两种方式查看 ZeroTier 网络地址：

1. **命令行方式**：
```
ip addr show ztyxazah2z
```

其中 `ztyxazah2z` 是 ZeroTier 网络接口名，可能因安装而异

2. **ZeroTier 控制台**：
    - 登录 ZeroTier Central 管理界面
    - 查看您的网络设置中的 "Managed Routes" 或 "IPv4 Auto-Assign" 部分

### 流量路由逻辑

设置完成后，网络流量将按以下逻辑路由：
- 发往 ZeroTier 网络（172.30.0.0/16）的流量 → 通过本地网络接口直接发送
- 所有其他流量 → 通过 OpenVPN 隧道发送

### 注意事项

1. 确保 OpenVPN 配置文件中的路由指令顺序正确
2. 如有多个需要绕过 OpenVPN 的网段，需为每个网段添加单独的 route 语句
3. 修改配置后需要重新连接 OpenVPN 才能生效
4. 若遇到连接问题，请检查 ZeroTier 网段是否与配置匹配

此配置方案可确保 ZeroTier 和 OpenVPN 各司其职，互不干扰，同时充分发挥两者的优势。

## 参考资料

- [ZeroTier 官方文档](https://docs.zerotier.com/)
- [ZeroTier GitHub 仓库](https://github.com/zerotier/ZeroTierOne)
- [ZeroTier Central 管理界面](https://my.zerotier.com/)
- [ZeroTier 社区论坛](https://discuss.zerotier.com/)
