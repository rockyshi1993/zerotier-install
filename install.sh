#!/bin/bash

# ZeroTier 自动安装脚本
# 基于 ZeroTier安装指南.md 文档中的步骤自动化安装和配置 ZeroTier
# 支持 Ubuntu/Debian、CentOS/RHEL、macOS 系统
#
# 版本: 1.0
# 最后更新: 2025-05-26
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 日志文件
LOG_FILE="/var/log/zerotier-install.log"

# 失败命令日志
FAILED_COMMANDS=""

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 默认设置
NETWORK_ID=""
AUTO_JOIN=false
AUTO_ACCEPT=false
PROXY_SERVER=false

# 临时文件和目录
TEMP_DIR=""

# 函数: 清理临时文件和中断的安装
cleanup() {
    log "${BLUE}执行清理操作...${NC}"

    # 如果存在临时目录，则删除
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        log "${GREEN}已删除临时目录${NC}"
    fi

    log "${GREEN}清理完成${NC}"
}

# 设置信号处理
trap cleanup EXIT INT TERM

# 函数: 显示帮助信息
show_help() {
    echo -e "${BLUE}ZeroTier 自动安装脚本${NC}"
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help                显示此帮助信息"
    echo "  -n, --network NETWORK_ID  设置要加入的 ZeroTier 网络 ID"
    echo "  -j, --join                安装后自动加入指定的网络"
    echo "  -a, --accept              如果是 ZeroTier 网络管理员，自动接受新节点"
    echo ""
    echo "示例:"
    echo "  $0 --network abcdef1234567890 --join"
    echo "  $0 --network abcdef1234567890 --join --accept"
    echo ""
    echo "功能说明:"
    echo "  1. 脚本会自动检测操作系统并使用适当的方法安装 ZeroTier"
    echo "  2. 如果指定了网络 ID 并使用 --join 选项，安装后会自动加入该网络"
    echo "  3. 如果使用 --accept 选项，脚本会尝试自动授权新节点（需要管理员权限）"
    echo "  4. 脚本可以配置 ZeroTier 作为代理服务器，允许其他 ZeroTier 客户端通过此服务器访问互联网和私有网络"
    echo ""
}

# 函数: 记录日志
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 函数: 执行命令并记录失败
run_cmd() {
    local cmd="$1"
    local desc="$2"

    # 执行命令
    eval "$cmd"
    local status=$?

    # 如果命令失败，记录到失败命令日志
    if [ $status -ne 0 ]; then
        local error_msg="${RED}命令失败: ${desc}${NC}"
        log "$error_msg"
        FAILED_COMMANDS="${FAILED_COMMANDS}• ${desc} (命令: $cmd)\n"
        return 1
    fi

    return 0
}

# 函数: 错误处理
error_exit() {
    log "${RED}错误: $1${NC}"
    exit 1
}

# 函数: 验证输入参数
validate_inputs() {
    log "${BLUE}验证输入参数...${NC}"

    # 验证网络 ID（如果提供）
    if [ -n "$NETWORK_ID" ]; then
        if ! [[ "$NETWORK_ID" =~ ^[a-f0-9]{16}$ ]]; then
            error_exit "网络 ID 必须是 16 位十六进制字符"
        fi
    fi

    log "${GREEN}输入参数验证通过${NC}"
}

# 函数: 检查是否为 root 用户
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error_exit "此脚本必须以 root 用户身份运行。请使用 sudo 或切换到 root 用户。"
    fi
}

# 函数: 检查必要的命令是否可用
check_commands() {
    log "${BLUE}检查必要的命令...${NC}"

    local required_commands=("curl" "grep" "awk" "sed")
    local missing_commands=()

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -ne 0 ]; then
        log "${YELLOW}警告: 以下命令不可用: ${missing_commands[*]}${NC}"
        log "${YELLOW}尝试安装缺失的命令...${NC}"

        if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
            apt update -y
            apt install -y curl grep gawk sed
        elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "fedora" ]]; then
            yum install -y curl grep gawk sed
        elif [[ "$OS" == "macos" ]]; then
            log "${YELLOW}在 macOS 上，请使用 Homebrew 安装缺失的命令:${NC}"
            log "${YELLOW}brew install curl grep gawk sed${NC}"
            exit 1
        fi

        # 再次检查
        missing_commands=()
        for cmd in "${required_commands[@]}"; do
            if ! command -v "$cmd" &>/dev/null; then
                missing_commands+=("$cmd")
            fi
        done

        if [ ${#missing_commands[@]} -ne 0 ]; then
            error_exit "无法安装必要的命令: ${missing_commands[*]}"
        fi
    fi

    log "${GREEN}所有必要的命令都可用${NC}"
}

# 函数: 检测操作系统
detect_os() {
    log "${BLUE}检测操作系统...${NC}"

    if [ "$(uname)" == "Darwin" ]; then
        OS="macos"
        log "${GREEN}检测到操作系统: macOS${NC}"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        if [ -f /etc/lsb-release ]; then
            OS="ubuntu"
        fi
        log "${GREEN}检测到操作系统: $OS${NC}"
    elif [ -f /etc/redhat-release ]; then
        if grep -q "CentOS" /etc/redhat-release; then
            OS="centos"
        elif grep -q "Red Hat" /etc/redhat-release; then
            OS="rhel"
        elif grep -q "Fedora" /etc/redhat-release; then
            OS="fedora"
        else
            OS="centos" # 默认为 CentOS
        fi
        log "${GREEN}检测到操作系统: $OS${NC}"
    else
        log "${YELLOW}警告: 无法确定操作系统类型，将尝试使用通用安装方法${NC}"
        OS="unknown"
    fi
}

# 函数: 检查 ZeroTier 是否已安装
check_zerotier_installed() {
    log "${BLUE}检查 ZeroTier 是否已安装...${NC}"

    if command -v zerotier-cli &>/dev/null; then
        log "${YELLOW}检测到 ZeroTier 已安装${NC}"

        # 显示菜单
        echo -e "${BLUE}ZeroTier 已安装在此系统上。请选择操作:${NC}"
        echo "1) 加入新网络"
        echo "2) 离开网络"
        echo "3) 查看当前网络状态"
        echo "4) 重启 ZeroTier 服务"
        echo "5) 卸载 ZeroTier"
        echo "6) 退出"

        read -p "请选择 [1-6]: " choice

        case $choice in
            1)
                join_network
                ;;
            2)
                leave_network
                ;;
            3)
                show_status
                ;;
            4)
                restart_service
                ;;
            5)
                uninstall_zerotier
                ;;
            6)
                log "${GREEN}退出脚本${NC}"
                exit 0
                ;;
            *)
                log "${RED}无效选择${NC}"
                exit 1
                ;;
        esac

        exit 0
    else
        log "${GREEN}ZeroTier 未安装，将继续安装过程${NC}"
    fi
}

# 函数: 安装 ZeroTier
install_zerotier() {
    log "${BLUE}开始安装 ZeroTier...${NC}"

    case $OS in
        ubuntu|debian)
            log "${BLUE}使用一键安装脚本安装 ZeroTier...${NC}"
            run_cmd "curl -s https://install.zerotier.com | bash" "使用一键安装脚本" || error_exit "ZeroTier 安装失败"
            ;;

        centos|rhel|fedora)
            log "${BLUE}使用一键安装脚本安装 ZeroTier...${NC}"
            run_cmd "curl -s https://install.zerotier.com | bash" "使用一键安装脚本" || error_exit "ZeroTier 安装失败"
            ;;

        macos)
            log "${BLUE}在 macOS 上安装 ZeroTier...${NC}"
            log "${YELLOW}注意: 在 macOS 上，此脚本将下载 ZeroTier 安装包，但需要手动安装${NC}"

            # 下载 ZeroTier 安装包
            run_cmd "curl -L -o /tmp/ZeroTier.pkg https://download.zerotier.com/dist/ZeroTier%20One.pkg" "下载 ZeroTier 安装包" || error_exit "无法下载 ZeroTier 安装包"

            log "${GREEN}ZeroTier 安装包已下载到 /tmp/ZeroTier.pkg${NC}"
            log "${YELLOW}请手动安装该包，然后继续此脚本${NC}"

            # 提示用户手动安装
            read -p "安装完成后按回车键继续..." dummy

            # 检查是否安装成功
            if ! [ -f "/usr/local/bin/zerotier-cli" ]; then
                error_exit "ZeroTier 安装失败或未完成"
            fi
            ;;

        *)
            log "${BLUE}使用通用安装方法...${NC}"
            run_cmd "curl -s https://install.zerotier.com | bash" "使用一键安装脚本" || error_exit "ZeroTier 安装失败"
            ;;
    esac

    # 启动 ZeroTier 服务
    log "${BLUE}启动 ZeroTier 服务...${NC}"

    if [ "$OS" == "macos" ]; then
        log "${YELLOW}在 macOS 上，ZeroTier 服务应该已经自动启动${NC}"
    else
        if command -v systemctl &>/dev/null; then
            run_cmd "systemctl enable zerotier-one" "启用 ZeroTier 服务" || log "${YELLOW}警告: 无法启用 ZeroTier 服务${NC}"
            run_cmd "systemctl start zerotier-one" "启动 ZeroTier 服务" || error_exit "无法启动 ZeroTier 服务"
        elif command -v service &>/dev/null; then
            run_cmd "service zerotier-one start" "启动 ZeroTier 服务" || error_exit "无法启动 ZeroTier 服务"
        else
            log "${YELLOW}警告: 无法确定服务管理器，尝试直接启动 ZeroTier${NC}"
            run_cmd "zerotier-one -d" "启动 ZeroTier 服务" || error_exit "无法启动 ZeroTier 服务"
        fi
    fi

    # 等待服务启动
    log "${BLUE}等待 ZeroTier 服务启动...${NC}"
    sleep 5

    # 检查安装是否成功
    if ! command -v zerotier-cli &>/dev/null; then
        error_exit "ZeroTier 安装失败，无法找到 zerotier-cli 命令"
    fi

    log "${GREEN}ZeroTier 安装成功${NC}"

    # 显示节点 ID
    NODE_ID=$(zerotier-cli info | awk '{print $3}')
    log "${GREEN}ZeroTier 节点 ID: ${NODE_ID}${NC}"
}

# 函数: 加入网络
join_network() {
    if [ -z "$NETWORK_ID" ]; then
        read -p "请输入要加入的 ZeroTier 网络 ID: " NETWORK_ID
    fi

    if ! [[ "$NETWORK_ID" =~ ^[a-f0-9]{16}$ ]]; then
        error_exit "无效的网络 ID。网络 ID 必须是 16 位十六进制字符。"
    fi

    log "${BLUE}加入 ZeroTier 网络: ${NETWORK_ID}...${NC}"
    run_cmd "zerotier-cli join $NETWORK_ID" "加入 ZeroTier 网络" || error_exit "无法加入网络"

    log "${GREEN}已成功加入网络 ${NETWORK_ID}${NC}"
    log "${YELLOW}注意: 网络管理员需要在 ZeroTier Central 中授权此设备${NC}"

    # 如果启用了自动接受，尝试授权节点
    if [ "$AUTO_ACCEPT" = true ]; then
        log "${BLUE}尝试自动授权节点...${NC}"
        log "${YELLOW}注意: 此功能需要 ZeroTier Central API 访问权限${NC}"

        # 这里可以添加使用 ZeroTier API 自动授权节点的代码
        # 由于需要 API 密钥和额外的依赖，此功能在此脚本中未实现
        log "${YELLOW}自动授权功能尚未实现，请手动授权节点${NC}"
    fi
}

# 函数: 离开网络
leave_network() {
    # 获取当前加入的网络列表
    NETWORKS=$(zerotier-cli listnetworks | tail -n +2 | awk '{print $3}')

    if [ -z "$NETWORKS" ]; then
        log "${YELLOW}当前未加入任何网络${NC}"
        return
    fi

    echo -e "${BLUE}当前加入的网络:${NC}"
    local i=1
    local network_array=()

    while read -r network; do
        echo "$i) $network"
        network_array+=("$network")
        ((i++))
    done <<< "$NETWORKS"

    echo "$i) 取消"

    read -p "请选择要离开的网络 [1-$i]: " choice

    if [ "$choice" -eq "$i" ]; then
        log "${GREEN}操作已取消${NC}"
        return
    fi

    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$((i-1))" ]; then
        log "${RED}无效选择${NC}"
        return
    fi

    SELECTED_NETWORK="${network_array[$((choice-1))]}"

    log "${BLUE}离开网络: ${SELECTED_NETWORK}...${NC}"
    run_cmd "zerotier-cli leave $SELECTED_NETWORK" "离开网络" || error_exit "无法离开网络"

    log "${GREEN}已成功离开网络 ${SELECTED_NETWORK}${NC}"
}

# 函数: 显示当前网络状态
show_status() {
    log "${BLUE}ZeroTier 状态:${NC}"
    zerotier-cli info

    log "${BLUE}当前加入的网络:${NC}"
    zerotier-cli listnetworks

    log "${BLUE}对等节点:${NC}"
    zerotier-cli peers
}

# 函数: 重启 ZeroTier 服务
restart_service() {
    log "${BLUE}重启 ZeroTier 服务...${NC}"

    if [ "$OS" == "macos" ]; then
        log "${YELLOW}在 macOS 上重启 ZeroTier 服务...${NC}"
        run_cmd "killall zerotier-one" "停止 ZeroTier 服务" || log "${YELLOW}警告: 无法停止 ZeroTier 服务${NC}"
        run_cmd "open /Applications/ZeroTier\\ One.app" "启动 ZeroTier 服务" || error_exit "无法启动 ZeroTier 服务"
    else
        if command -v systemctl &>/dev/null; then
            run_cmd "systemctl restart zerotier-one" "重启 ZeroTier 服务" || error_exit "无法重启 ZeroTier 服务"
        elif command -v service &>/dev/null; then
            run_cmd "service zerotier-one restart" "重启 ZeroTier 服务" || error_exit "无法重启 ZeroTier 服务"
        else
            log "${YELLOW}警告: 无法确定服务管理器，尝试手动重启 ZeroTier${NC}"
            run_cmd "killall zerotier-one" "停止 ZeroTier 服务" || log "${YELLOW}警告: 无法停止 ZeroTier 服务${NC}"
            run_cmd "zerotier-one -d" "启动 ZeroTier 服务" || error_exit "无法启动 ZeroTier 服务"
        fi
    fi

    log "${GREEN}ZeroTier 服务已重启${NC}"
}

# 函数: 卸载 ZeroTier
uninstall_zerotier() {
    log "${BLUE}卸载 ZeroTier...${NC}"

    read -p "确定要卸载 ZeroTier 吗? [y/N]: " confirm
    if [[ "$confirm" != [yY] ]]; then
        log "${GREEN}卸载已取消${NC}"
        return
    fi

    case $OS in
        ubuntu|debian)
            run_cmd "apt-get remove -y zerotier-one" "卸载 ZeroTier" || error_exit "无法卸载 ZeroTier"
            run_cmd "apt-get autoremove -y" "自动移除依赖" || log "${YELLOW}警告: 无法自动移除依赖${NC}"
            ;;

        centos|rhel|fedora)
            if [ "$OS" == "fedora" ]; then
                run_cmd "dnf remove -y zerotier-one" "卸载 ZeroTier" || error_exit "无法卸载 ZeroTier"
            else
                run_cmd "yum remove -y zerotier-one" "卸载 ZeroTier" || error_exit "无法卸载 ZeroTier"
            fi
            ;;

        macos)
            log "${YELLOW}在 macOS 上卸载 ZeroTier...${NC}"
            log "${YELLOW}请手动卸载 ZeroTier:${NC}"
            log "${YELLOW}1. 打开应用程序文件夹${NC}"
            log "${YELLOW}2. 将 ZeroTier One 应用拖到垃圾桶${NC}"
            log "${YELLOW}3. 清空垃圾桶${NC}"
            ;;

        *)
            log "${YELLOW}使用通用卸载方法...${NC}"
            if [ -f /usr/bin/zerotier-one ]; then
                run_cmd "rm -f /usr/bin/zerotier-*" "删除 ZeroTier 二进制文件" || log "${YELLOW}警告: 无法删除 ZeroTier 二进制文件${NC}"
            fi

            if [ -d /var/lib/zerotier-one ]; then
                run_cmd "rm -rf /var/lib/zerotier-one" "删除 ZeroTier 数据目录" || log "${YELLOW}警告: 无法删除 ZeroTier 数据目录${NC}"
            fi
            ;;
    esac

    log "${GREEN}ZeroTier 已卸载${NC}"
}

# 函数: 配置代理服务器
configure_proxy_server() {
    log "${BLUE}配置 ZeroTier 作为代理服务器...${NC}"

    # 检查是否为 macOS
    if [ "$OS" == "macos" ]; then
        log "${YELLOW}警告: 在 macOS 上配置代理服务器需要手动操作${NC}"
        log "${YELLOW}请参考 ZeroTier 文档进行手动配置${NC}"
        return
    fi

    # 启用 IP 转发
    log "${BLUE}启用 IP 转发...${NC}"
    run_cmd "echo 1 > /proc/sys/net/ipv4/ip_forward" "启用 IP 转发" || log "${YELLOW}警告: 无法启用 IP 转发${NC}"

    # 使 IP 转发在重启后仍然生效
    if [ -f /etc/sysctl.conf ]; then
        if ! grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
            run_cmd "echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf" "配置持久化 IP 转发" || log "${YELLOW}警告: 无法配置持久化 IP 转发${NC}"
        else
            run_cmd "sed -i 's/net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/sysctl.conf" "更新 IP 转发配置" || log "${YELLOW}警告: 无法更新 IP 转发配置${NC}"
        fi
        run_cmd "sysctl -p" "应用 sysctl 配置" || log "${YELLOW}警告: 无法应用 sysctl 配置${NC}"
    else
        log "${YELLOW}警告: 找不到 sysctl.conf 文件，IP 转发可能在重启后失效${NC}"
    fi

    # 配置 NAT
    log "${BLUE}配置 NAT...${NC}"

    # 获取 ZeroTier 网络接口
    ZT_INTERFACE=$(ip -o link show | grep zt | awk -F': ' '{print $2}' | head -n 1)
    if [ -z "$ZT_INTERFACE" ]; then
        log "${YELLOW}警告: 找不到 ZeroTier 网络接口，请确保 ZeroTier 已正确安装并加入网络${NC}"
        return
    fi

    # 获取默认网络接口
    DEFAULT_INTERFACE=$(ip -o route get 8.8.8.8 | awk '{print $5}')
    if [ -z "$DEFAULT_INTERFACE" ]; then
        log "${YELLOW}警告: 找不到默认网络接口${NC}"
        return
    fi

    log "${BLUE}ZeroTier 接口: ${ZT_INTERFACE}, 默认接口: ${DEFAULT_INTERFACE}${NC}"

    # 配置 iptables 规则
    log "${BLUE}配置 iptables 规则...${NC}"

    # 检查 iptables 是否可用
    if ! command -v iptables &>/dev/null; then
        log "${YELLOW}警告: iptables 不可用，无法配置 NAT${NC}"
        return
    fi

    # 添加 NAT 规则
    run_cmd "iptables -t nat -A POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE" "添加 MASQUERADE 规则" || log "${YELLOW}警告: 无法添加 MASQUERADE 规则${NC}"
    run_cmd "iptables -A FORWARD -i $ZT_INTERFACE -o $DEFAULT_INTERFACE -j ACCEPT" "添加转发规则 (ZT -> 互联网)" || log "${YELLOW}警告: 无法添加转发规则${NC}"
    run_cmd "iptables -A FORWARD -i $DEFAULT_INTERFACE -o $ZT_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT" "添加转发规则 (互联网 -> ZT)" || log "${YELLOW}警告: 无法添加转发规则${NC}"

    # 使 iptables 规则持久化
    if command -v iptables-save &>/dev/null; then
        if [ -d /etc/iptables ]; then
            run_cmd "iptables-save > /etc/iptables/rules.v4" "保存 iptables 规则" || log "${YELLOW}警告: 无法保存 iptables 规则${NC}"
        elif [ -d /etc/sysconfig ]; then
            run_cmd "iptables-save > /etc/sysconfig/iptables" "保存 iptables 规则" || log "${YELLOW}警告: 无法保存 iptables 规则${NC}"
        else
            run_cmd "iptables-save > /etc/iptables.rules" "保存 iptables 规则" || log "${YELLOW}警告: 无法保存 iptables 规则${NC}"

            # 创建网络接口启动脚本
            if [ -d /etc/network/if-up.d ]; then
                cat > /etc/network/if-up.d/iptables << 'EOF'
#!/bin/sh
iptables-restore < /etc/iptables.rules
EOF
                chmod +x /etc/network/if-up.d/iptables
            fi
        fi
    else
        log "${YELLOW}警告: iptables-save 不可用，iptables 规则在重启后可能失效${NC}"
    fi

    log "${GREEN}ZeroTier 代理服务器配置完成${NC}"
}

# 函数: 检测私有网络子网
detect_private_subnet() {
    # 获取默认网络接口
    DEFAULT_INTERFACE=$(ip -o route get 8.8.8.8 | awk '{print $5}')
    if [ -z "$DEFAULT_INTERFACE" ]; then
        log "${YELLOW}警告: 找不到默认网络接口${NC}"
        return ""
    fi

    # 获取私有网络子网
    PRIVATE_SUBNET=$(ip -o addr show dev $DEFAULT_INTERFACE | grep -v inet6 | grep inet | awk '{print $4}' | head -n 1)
    echo "$PRIVATE_SUBNET"
}

# 函数: 显示代理服务器配置说明
show_proxy_instructions() {
    NODE_ID=$(zerotier-cli info | awk '{print $3}')

    log "${BLUE}ZeroTier 代理服务器配置说明:${NC}"
    log "${YELLOW}请在 ZeroTier Central 中执行以下操作:${NC}"
    log "${YELLOW}1. 登录 https://my.zerotier.com/${NC}"
    log "${YELLOW}2. 找到您的网络，点击进入网络设置页面${NC}"
    log "${YELLOW}3. 在 'Managed Routes' 区域添加路由：${NC}"
    log "${YELLOW}   - 0.0.0.0/0 via <节点IP>      （实现通过该节点访问互联网）${NC}"

    PRIVATE_SUBNET=$(detect_private_subnet)
    if [ -n "$PRIVATE_SUBNET" ]; then
        log "${YELLOW}   - ${PRIVATE_SUBNET} via <节点IP>（实现访问节点所在私有网络）${NC}"
    fi

    log ""
    log "${YELLOW}⚠️ 注意：${NC}"
    log "${YELLOW}   - <节点IP> 必须是该节点在 ZeroTier 网络中的实际 IP 地址（如 172.22.231.20）${NC}"
    log "${YELLOW}   - 请不要填写节点 ID（如 ${NODE_ID}）${NC}"
    log ""
    log "${YELLOW}4. 保存设置${NC}"
    log "${YELLOW}5. 确保您的客户端设备已加入此网络并获得授权${NC}"
    log "${YELLOW}完成上述配置后，您的 ZeroTier 客户端将能够:${NC}"
    log "${YELLOW}- 通过此服务器访问互联网${NC}"
    log "${YELLOW}- 访问此服务器所在的私有网络资源${NC}"
}

# 函数: 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -n|--network)
                NETWORK_ID="$2"
                shift 2
                ;;
            -j|--join)
                AUTO_JOIN=true
                shift
                ;;
            -a|--accept)
                AUTO_ACCEPT=true
                shift
                ;;
            *)
                error_exit "未知选项: $1"
                ;;
        esac
    done
}

# 主函数
main() {
    # 创建日志文件目录
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

    log "${BLUE}ZeroTier 自动安装脚本启动${NC}"
    log "${BLUE}版本: 1.0${NC}"

    # 解析命令行参数
    parse_args "$@"

    # 验证输入参数
    validate_inputs

    # 检查是否为 root 用户（非 macOS）
    if [ "$(uname)" != "Darwin" ]; then
        check_root
    fi

    # 检测操作系统
    detect_os

    # 检查必要的命令
    check_commands

    # 检查 ZeroTier 是否已安装
    check_zerotier_installed

    # 安装 ZeroTier
    install_zerotier

    # 询问用户是否要配置代理服务器
    if [ "$OS" != "macos" ]; then
        read -p "是否将此 ZeroTier 节点配置为代理服务器? [y/N]: " proxy_choice
        if [[ "$proxy_choice" == [yY] ]]; then
            PROXY_SERVER=true
            configure_proxy_server
        fi
    fi

    # 如果启用了自动加入，加入网络
    if [ "$AUTO_JOIN" = true ] && [ -n "$NETWORK_ID" ]; then
        join_network
    else
        # 询问用户是否要加入网络
        read -p "是否要加入 ZeroTier 网络? [y/N]: " join_choice
        if [[ "$join_choice" == [yY] ]]; then
            join_network
        fi
    fi

    # 显示安装总结
    log "${GREEN}ZeroTier 安装和配置完成${NC}"
    log "${GREEN}节点 ID: $(zerotier-cli info | awk '{print $3}')${NC}"

    if [ -n "$FAILED_COMMANDS" ]; then
        log "${YELLOW}警告: 以下命令执行失败:${NC}"
        echo -e "$FAILED_COMMANDS"
    fi

    # 如果配置了代理服务器，显示配置说明
    if [ "$PROXY_SERVER" = true ]; then
        log ""
        show_proxy_instructions
        log ""
    fi

    log "${BLUE}使用以下命令管理 ZeroTier:${NC}"
    log "${BLUE}- 查看状态: zerotier-cli info${NC}"
    log "${BLUE}- 列出网络: zerotier-cli listnetworks${NC}"
    log "${BLUE}- 加入网络: zerotier-cli join <network-id>${NC}"
    log "${BLUE}- 离开网络: zerotier-cli leave <network-id>${NC}"

    log "${GREEN}感谢使用 ZeroTier 自动安装脚本!${NC}"
}

# 执行主函数
main "$@"
