#!/bin/bash

# ZeroTier 自动安装脚本
# 基于 ZeroTier安装指南.md 文档中的步骤自动化安装和配置 ZeroTier
# 支持 Ubuntu/Debian、CentOS/RHEL、macOS 系统
#
# 版本: 1.1
# 最后更新: 2025-06-01
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
    echo "  5. 脚本可以配置 ZeroTier 作为中继（Moon）节点，提供更稳定的连接和自定义路由"
    echo ""
    echo "中继（Moon）节点功能:"
    echo "  - 配置中继节点: 将当前服务器配置为 ZeroTier 中继节点，提供更稳定的连接"
    echo "  - 管理中继节点: 查看状态、更新配置、重新生成客户端分发包"
    echo "  - 移除中继节点: 安全地移除中继节点配置"
    echo "  - 客户端分发包: 自动生成包含安装脚本和说明文档的客户端配置包"
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

# 函数: 验证 IP 地址
validate_ip() {
    local ip=$1
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi

    IFS='.' read -r -a ip_segments <<< "$ip"
    for segment in "${ip_segments[@]}"; do
        if [[ "$segment" -gt 255 ]]; then
            return 1
        fi
    done

    return 0
}

# 函数: 处理错误并提供恢复建议
handle_error() {
    local error_type="$1"
    local error_msg="$2"
    local suggestion="$3"
    local recovery_cmd="$4"

    log "${RED}错误 [${error_type}]: ${error_msg}${NC}"
    log "${YELLOW}建议: ${suggestion}${NC}"

    # 如果提供了恢复命令，询问是否执行
    if [ -n "$recovery_cmd" ]; then
        read -p "是否尝试自动修复? [y/N]: " fix_choice
        if [[ "$fix_choice" == [yY] ]]; then
            log "${BLUE}尝试修复...${NC}"
            eval "$recovery_cmd"
            return $?
        fi
    fi

    return 1
}

# 函数: 验证路径
validate_path() {
    local path=$1
    # 检查路径是否包含危险字符
    if echo "$path" | grep -q "[\'|&\$;]"; then
        return 1
    fi
    return 0
}

# 函数: 提示输入网络 ID
prompt_network_id() {
    read -p "请重新输入正确的网络 ID: " NETWORK_ID
    if [[ "$NETWORK_ID" =~ ^[a-f0-9]{16}$ ]]; then
        return 0
    else
        return 1
    fi
}

# 函数: 提示输入 IP 地址
prompt_ip_address() {
    local var_name="${1:-NEW_IP}"
    read -p "请重新输入正确的 IP 地址: " "$var_name"
    if validate_ip "${!var_name}"; then
        return 0
    else
        return 1
    fi
}

# 函数: 验证输入参数
validate_inputs() {
    log "${BLUE}验证输入参数...${NC}"

    # 验证网络 ID（如果提供）
    if [ -n "$NETWORK_ID" ]; then
        if ! [[ "$NETWORK_ID" =~ ^[a-f0-9]{16}$ ]]; then
            handle_error "CONFIG_ERROR" "无效的网络 ID" "网络 ID 必须是 16 位十六进制字符，请检查输入是否正确" "prompt_network_id"
            if ! [[ "$NETWORK_ID" =~ ^[a-f0-9]{16}$ ]]; then
                log "${RED}网络 ID 仍然无效，退出操作${NC}"
                exit 1
            fi
        fi
    fi

    log "${GREEN}输入参数验证通过${NC}"
}

# 函数: 检查是否为 root 用户
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        handle_error "PERMISSION_ERROR" "此脚本必须以 root 用户身份运行" "请使用 sudo 或切换到 root 用户重新运行此脚本" "echo '请使用 sudo 重新运行此脚本'"
        exit 1
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
            handle_error "DEPENDENCY_ERROR" "无法安装必要的命令: ${missing_commands[*]}" "请手动安装缺失的命令，或检查系统包管理器是否正常工作" "apt-get update -y && apt-get install -y ${missing_commands[*]}"
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

        # 检查是否已创建 Moon 节点
        MOON_CREATED=false
        if is_moon_node_created; then
            MOON_CREATED=true
        fi

        # 显示菜单
        echo -e "${BLUE}ZeroTier 已安装在此系统上。请选择操作:${NC}"
        echo "1) 加入新网络"
        echo "2) 离开网络"
        echo "3) 查看当前网络状态"
        echo "4) 配置代理服务器"

        # 根据 Moon 节点状态显示不同的菜单选项
        if [ "$MOON_CREATED" = true ]; then
            echo "5) 管理中继（Moon）节点"
        else
            echo "5) 配置中继（Moon）节点"
        fi

        echo "6) 重启 ZeroTier 服务"
        echo "7) 卸载 ZeroTier"
        echo "8) 检查更新"
        echo "9) 配置向导"
        echo "10) 状态仪表板"
        echo "11) 退出"

        read -p "请选择 [1-11]: " choice

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
                # 配置代理服务器
                PROXY_SERVER=false
                read -p "是否配置代理服务器以支持特殊网络环境? [y/N]: " proxy_choice
                if [[ "$proxy_choice" == [yY] ]]; then
                    PROXY_SERVER=true
                    configure_proxy_server
                    show_proxy_instructions
                fi
                ;;
            5)
                if [ "$MOON_CREATED" = true ]; then
                    # 管理中继（Moon）节点
                    echo -e "${BLUE}ZeroTier 中继（Moon）节点管理${NC}"
                    echo "1) 查看中继节点状态"
                    echo "2) 更新中继节点配置"
                    echo "3) 移除中继节点"
                    echo "4) 返回主菜单"

                    read -p "请选择 [1-4]: " moon_choice

                    case $moon_choice in
                        1)
                            view_moon_status
                            ;;
                        2)
                            update_moon_config
                            ;;
                        3)
                            read -p "确定要移除 ZeroTier 中继（Moon）节点吗? [y/N]: " remove_choice
                            if [[ "$remove_choice" == [yY] ]]; then
                                remove_moon_node
                            fi
                            ;;
                        4)
                            log "${GREEN}返回主菜单${NC}"
                            ;;
                        *)
                            log "${RED}无效选择${NC}"
                            ;;
                    esac
                else
                    # 配置中继（Moon）节点
                    read -p "是否将当前节点配置为 ZeroTier 中继（Moon）节点? [y/N]: " moon_choice
                    if [[ "$moon_choice" == [yY] ]]; then
                        configure_moon_node
                    fi
                fi
                ;;
            6)
                restart_service
                ;;
            7)
                uninstall_zerotier
                ;;
            8)
                check_for_updates
                ;;
            9)
                configuration_wizard
                ;;
            10)
                show_dashboard
                ;;
            11)
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
            run_cmd "curl -s https://install.zerotier.com | bash" "使用一键安装脚本" || handle_error "INSTALLATION_ERROR" "ZeroTier 安装失败" "请检查网络连接或手动安装 ZeroTier" "curl -s https://install.zerotier.com | bash"
            ;;

        centos|rhel|fedora)
            log "${BLUE}使用一键安装脚本安装 ZeroTier...${NC}"
            run_cmd "curl -s https://install.zerotier.com | bash" "使用一键安装脚本" || handle_error "INSTALLATION_ERROR" "ZeroTier 安装失败" "请检查网络连接或手动安装 ZeroTier" "curl -s https://install.zerotier.com | bash"
            ;;

        macos)
            log "${BLUE}在 macOS 上安装 ZeroTier...${NC}"
            log "${YELLOW}注意: 在 macOS 上，此脚本将下载 ZeroTier 安装包，但需要手动安装${NC}"

            # 下载 ZeroTier 安装包
            run_cmd "curl -L -o /tmp/ZeroTier.pkg https://download.zerotier.com/dist/ZeroTier%20One.pkg" "下载 ZeroTier 安装包" || handle_error "NETWORK_ERROR" "无法下载 ZeroTier 安装包" "请检查网络连接或手动下载安装包" "curl -L -o /tmp/ZeroTier.pkg https://download.zerotier.com/dist/ZeroTier%20One.pkg"

            log "${GREEN}ZeroTier 安装包已下载到 /tmp/ZeroTier.pkg${NC}"
            log "${YELLOW}请手动安装该包，然后继续此脚本${NC}"

            # 提示用户手动安装
            read -p "安装完成后按回车键继续..." dummy

            # 检查是否安装成功
            if ! [ -f "/usr/local/bin/zerotier-cli" ]; then
                handle_error "INSTALLATION_ERROR" "ZeroTier 安装失败或未完成" "请确保已正确安装 ZeroTier 安装包" "open /tmp/ZeroTier.pkg"
                return 1
            fi
            ;;

        *)
            log "${BLUE}使用通用安装方法...${NC}"
            run_cmd "curl -s https://install.zerotier.com | bash" "使用一键安装脚本" || handle_error "INSTALLATION_ERROR" "ZeroTier 安装失败" "请检查网络连接或手动安装 ZeroTier" "curl -s https://install.zerotier.com | bash"
            ;;
    esac

    # 启动 ZeroTier 服务
    log "${BLUE}启动 ZeroTier 服务...${NC}"

    if [ "$OS" == "macos" ]; then
        log "${YELLOW}在 macOS 上，ZeroTier 服务应该已经自动启动${NC}"
    else
        if command -v systemctl &>/dev/null; then
            run_cmd "systemctl enable zerotier-one" "启用 ZeroTier 服务" || log "${YELLOW}警告: 无法启用 ZeroTier 服务${NC}"
            run_cmd "systemctl start zerotier-one" "启动 ZeroTier 服务" || handle_error "SERVICE_ERROR" "无法启动 ZeroTier 服务" "尝试重新安装 ZeroTier 或检查系统日志" "systemctl restart zerotier-one"
        elif command -v service &>/dev/null; then
            run_cmd "service zerotier-one start" "启动 ZeroTier 服务" || handle_error "SERVICE_ERROR" "无法启动 ZeroTier 服务" "尝试重新安装 ZeroTier 或检查系统日志" "service zerotier-one restart"
        else
            log "${YELLOW}警告: 无法确定服务管理器，尝试直接启动 ZeroTier${NC}"
            run_cmd "zerotier-one -d" "启动 ZeroTier 服务" || handle_error "SERVICE_ERROR" "无法启动 ZeroTier 服务" "尝试重新安装 ZeroTier 或检查系统日志" "killall zerotier-one 2>/dev/null; sleep 2; zerotier-one -d"
        fi
    fi

    # 等待服务启动
    log "${BLUE}等待 ZeroTier 服务启动...${NC}"
    sleep 5

    # 检查安装是否成功
    if ! command -v zerotier-cli &>/dev/null; then
        handle_error "INSTALLATION_ERROR" "ZeroTier 安装失败，无法找到 zerotier-cli 命令" "请确保 ZeroTier 已正确安装，或尝试重新安装" "curl -s https://install.zerotier.com | bash"
        return 1
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
        handle_error "CONFIG_ERROR" "无效的网络 ID" "网络 ID 必须是 16 位十六进制字符，请检查输入是否正确" "prompt_network_id"
        if ! [[ "$NETWORK_ID" =~ ^[a-f0-9]{16}$ ]]; then
            log "${RED}网络 ID 仍然无效，退出操作${NC}"
            return 1
        fi
    fi

    log "${BLUE}加入 ZeroTier 网络: ${NETWORK_ID}...${NC}"
    run_cmd "zerotier-cli join $NETWORK_ID" "加入 ZeroTier 网络" || handle_error "NETWORK_ERROR" "无法加入网络" "请检查网络连接和网络 ID 是否正确" "zerotier-cli leave $NETWORK_ID 2>/dev/null; sleep 2; zerotier-cli join $NETWORK_ID"

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
    run_cmd "zerotier-cli leave $SELECTED_NETWORK" "离开网络" || handle_error "NETWORK_ERROR" "无法离开网络" "请检查网络连接和网络 ID 是否正确" "zerotier-cli listnetworks | grep $SELECTED_NETWORK && zerotier-cli leave $SELECTED_NETWORK"

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
        run_cmd "open /Applications/ZeroTier\\ One.app" "启动 ZeroTier 服务" || handle_error "SERVICE_ERROR" "无法启动 ZeroTier 服务" "尝试手动启动 ZeroTier 应用程序或重新安装" "killall zerotier-one 2>/dev/null; sleep 2; open /Applications/ZeroTier\\ One.app"
    else
        if command -v systemctl &>/dev/null; then
            run_cmd "systemctl restart zerotier-one" "重启 ZeroTier 服务" || handle_error "SERVICE_ERROR" "无法重启 ZeroTier 服务" "尝试手动重启服务或检查系统日志" "systemctl stop zerotier-one; sleep 2; systemctl start zerotier-one"
        elif command -v service &>/dev/null; then
            run_cmd "service zerotier-one restart" "重启 ZeroTier 服务" || handle_error "SERVICE_ERROR" "无法重启 ZeroTier 服务" "尝试手动重启服务或检查系统日志" "service zerotier-one stop; sleep 2; service zerotier-one start"
        else
            log "${YELLOW}警告: 无法确定服务管理器，尝试手动重启 ZeroTier${NC}"
            run_cmd "killall zerotier-one" "停止 ZeroTier 服务" || log "${YELLOW}警告: 无法停止 ZeroTier 服务${NC}"
            run_cmd "zerotier-one -d" "启动 ZeroTier 服务" || handle_error "SERVICE_ERROR" "无法启动 ZeroTier 服务" "尝试手动启动服务或检查系统日志" "killall zerotier-one 2>/dev/null; sleep 2; zerotier-one -d"
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
            run_cmd "apt-get remove -y zerotier-one" "卸载 ZeroTier" || handle_error "UNINSTALL_ERROR" "无法卸载 ZeroTier" "请尝试手动卸载或检查系统日志" "apt-get remove -y --purge zerotier-one"
            run_cmd "apt-get autoremove -y" "自动移除依赖" || log "${YELLOW}警告: 无法自动移除依赖${NC}"
            ;;

        centos|rhel|fedora)
            if [ "$OS" == "fedora" ]; then
                run_cmd "dnf remove -y zerotier-one" "卸载 ZeroTier" || handle_error "UNINSTALL_ERROR" "无法卸载 ZeroTier" "请尝试手动卸载或检查系统日志" "dnf remove -y --allmatches zerotier-one"
            else
                run_cmd "yum remove -y zerotier-one" "卸载 ZeroTier" || handle_error "UNINSTALL_ERROR" "无法卸载 ZeroTier" "请尝试手动卸载或检查系统日志" "yum remove -y --allmatches zerotier-one"
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

# 函数: 检查是否已创建 Moon 节点
is_moon_node_created() {
    # 多重检测机制，提高检测准确性

    # 1. 检查 moons.d 目录中的 .moon 文件
    if [ -d "/var/lib/zerotier-one/moons.d" ]; then
        if [ "$(ls -A /var/lib/zerotier-one/moons.d/*.moon 2>/dev/null)" ]; then
            return 0  # 已创建 Moon 节点
        fi
    fi

    # 2. 检查客户端分发包目录
    if [ -d "${SCRIPT_DIR}" ]; then
        if [ "$(find "${SCRIPT_DIR}" -name "zerotier_moon_*.zip" -o -name "zerotier_moon_*" -type d 2>/dev/null)" ]; then
            return 0  # 已创建 Moon 节点
        fi
    fi

    # 3. 检查 ZeroTier 配置中的 Moon 记录
    if command -v zerotier-cli &>/dev/null; then
        if zerotier-cli listpeers | grep -q "MOON"; then
            return 0  # 已连接到 Moon 节点
        fi
    fi

    # 4. 检查标记文件
    if [ -f "/var/lib/zerotier-one/.moon_configured" ]; then
        return 0  # 已创建 Moon 节点
    fi

    return 1  # 未创建 Moon 节点
}

# 函数: 备份 Moon 节点配置
backup_moon_config() {
    log "${BLUE}备份现有 Moon 节点配置...${NC}"

    # 创建备份目录
    BACKUP_DIR="${SCRIPT_DIR}/moon_backup_$(date '+%Y%m%d_%H%M%S')"
    mkdir -p "$BACKUP_DIR"

    # 备份 moons.d 目录
    if [ -d "/var/lib/zerotier-one/moons.d" ]; then
        log "${BLUE}备份 moons.d 目录...${NC}"
        run_cmd "cp -r /var/lib/zerotier-one/moons.d/* \"$BACKUP_DIR/\" 2>/dev/null" "备份 Moon 文件" || log "${YELLOW}警告: 无法备份 Moon 文件${NC}"
    fi

    # 备份客户端分发包
    log "${BLUE}备份客户端分发包...${NC}"
    if [ "$(find "${SCRIPT_DIR}" -name "zerotier_moon_*.zip" 2>/dev/null)" ]; then
        run_cmd "cp ${SCRIPT_DIR}/zerotier_moon_*.zip \"$BACKUP_DIR/\" 2>/dev/null" "备份客户端分发包" || log "${YELLOW}警告: 无法备份客户端分发包${NC}"
    fi

    # 备份客户端分发目录
    if [ "$(find "${SCRIPT_DIR}" -name "zerotier_moon_*" -type d 2>/dev/null)" ]; then
        for dir in $(find "${SCRIPT_DIR}" -name "zerotier_moon_*" -type d); do
            dir_name=$(basename "$dir")
            run_cmd "cp -r \"$dir\" \"$BACKUP_DIR/$dir_name\" 2>/dev/null" "备份客户端分发目录" || log "${YELLOW}警告: 无法备份客户端分发目录${NC}"
        done
    fi

    # 检查备份是否成功
    if [ "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        log "${GREEN}Moon 节点配置已备份到: $BACKUP_DIR${NC}"
    else
        log "${YELLOW}警告: 备份目录为空，可能没有找到需要备份的文件${NC}"
        rmdir "$BACKUP_DIR" 2>/dev/null
    fi
}

# 函数: 查看 Moon 节点状态
view_moon_status() {
    log "${BLUE}查看 ZeroTier Moon 节点状态...${NC}"

    # 检查是否已创建 Moon 节点
    if ! is_moon_node_created; then
        log "${YELLOW}未检测到 Moon 节点配置${NC}"
        return 1
    fi

    # 获取 Moon 文件信息
    log "${BLUE}Moon 节点文件:${NC}"
    if [ -d "/var/lib/zerotier-one/moons.d" ]; then
        for moon_file in /var/lib/zerotier-one/moons.d/*.moon; do
            if [ -f "$moon_file" ]; then
                moon_filename=$(basename "$moon_file")
                moon_id=${moon_filename%.moon}
                log "${GREEN}- $moon_filename (ID: $moon_id)${NC}"
            fi
        done
    else
        log "${YELLOW}未找到 Moon 节点文件目录${NC}"
    fi

    # 获取 Moon 节点连接信息
    log "${BLUE}Moon 节点连接状态:${NC}"
    if command -v zerotier-cli &>/dev/null; then
        # 检查本地 Moon 连接
        local_moons=$(zerotier-cli listpeers | grep -i "MOON" || echo "")
        if [ -n "$local_moons" ]; then
            log "${GREEN}已连接的 Moon 节点:${NC}"
            echo "$local_moons" | while read -r line; do
                log "${GREEN}- $line${NC}"
            done
        else
            log "${YELLOW}未检测到已连接的 Moon 节点${NC}"
        fi

        # 获取连接到此 Moon 节点的客户端
        log "${BLUE}连接到此 Moon 节点的客户端:${NC}"
        peers=$(zerotier-cli listpeers | grep -v "MOON" | grep -v "LEAF" || echo "")
        if [ -n "$peers" ]; then
            echo "$peers" | while read -r line; do
                log "${GREEN}- $line${NC}"
            done
        else
            log "${YELLOW}未检测到连接的客户端${NC}"
        fi
    else
        log "${RED}错误: zerotier-cli 命令不可用${NC}"
    fi

    # 获取客户端分发包信息
    log "${BLUE}客户端分发包:${NC}"
    client_packages=$(find "${SCRIPT_DIR}" -name "zerotier_moon_*.zip" -o -name "zerotier_moon_*" -type d 2>/dev/null)
    if [ -n "$client_packages" ]; then
        echo "$client_packages" | while read -r package; do
            log "${GREEN}- $package${NC}"
        done
    else
        log "${YELLOW}未找到客户端分发包${NC}"
    fi

    # 显示连接说明
    log "${BLUE}连接说明:${NC}"
    log "${YELLOW}其他设备可以使用以下命令连接到此 Moon 节点:${NC}"
    for moon_file in /var/lib/zerotier-one/moons.d/*.moon; do
        if [ -f "$moon_file" ]; then
            moon_id=${moon_file##*/}
            moon_id=${moon_id%.moon}
            log "${YELLOW}zerotier-cli orbit $moon_id $moon_id${NC}"
        fi
    done

    return 0
}

# 函数: 更新 Moon 节点配置
update_moon_config() {
    log "${BLUE}更新 ZeroTier Moon 节点配置...${NC}"

    # 检查是否已创建 Moon 节点
    if ! is_moon_node_created; then
        log "${YELLOW}未检测到 Moon 节点配置，请先配置 Moon 节点${NC}"
        return 1
    fi

    # 显示更新选项
    echo -e "${BLUE}请选择要更新的内容:${NC}"
    echo "1) 更新 Moon 节点 IP 地址"
    echo "2) 重新生成客户端分发包"
    echo "3) 监控 Moon 节点性能"
    echo "4) 持续监控 Moon 节点"
    echo "5) 分析 ZeroTier 日志"
    echo "6) 返回"

    read -p "请选择 [1-6]: " update_choice

    case $update_choice in
        1)
            # 更新 Moon 节点 IP 地址
            log "${BLUE}更新 Moon 节点 IP 地址...${NC}"

            # 备份现有配置
            backup_moon_config

            # 获取当前 IP 地址
            CURRENT_IP=$(curl -s https://api.ipify.org)
            if [[ ! "$CURRENT_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                log "${YELLOW}警告: 无法自动获取公网 IP${NC}"
                CURRENT_IP="未知"
            fi

            # 询问新 IP 地址
            read -p "请输入新的公网 IP 地址 [当前: $CURRENT_IP]: " NEW_IP
            if [ -z "$NEW_IP" ]; then
                NEW_IP=$CURRENT_IP
            fi

            if ! validate_ip "$NEW_IP"; then
                handle_error "CONFIG_ERROR" "无效的 IP 地址格式" "请输入有效的 IPv4 地址，格式为 x.x.x.x，其中 x 为 0-255 之间的数字" "prompt_ip_address NEW_IP"
                if ! validate_ip "$NEW_IP"; then
                    log "${RED}IP 地址仍然无效，退出操作${NC}"
                    return 1
                fi
            fi

            # 获取所有 Moon ID
            MOON_IDS=()
            MOON_FILES=()
            for moon_file in /var/lib/zerotier-one/moons.d/*.moon; do
                if [ -f "$moon_file" ]; then
                    moon_id=${moon_file##*/}
                    moon_id=${moon_id%.moon}
                    MOON_IDS+=("$moon_id")
                    MOON_FILES+=("$moon_file")
                fi
            done

            if [ ${#MOON_IDS[@]} -eq 0 ]; then
                log "${RED}错误: 无法获取 Moon ID${NC}"
                return 1
            fi

            # 如果有多个 Moon 节点，让用户选择
            MOON_ID=""
            MOON_FILE=""
            if [ ${#MOON_IDS[@]} -gt 1 ]; then
                log "${BLUE}检测到多个 Moon 节点:${NC}"
                for i in "${!MOON_IDS[@]}"; do
                    echo "$((i+1))) ${MOON_IDS[$i]}"
                done

                read -p "请选择要更新的 Moon 节点 [1-${#MOON_IDS[@]}]: " moon_choice

                # 验证输入
                if ! [[ "$moon_choice" =~ ^[0-9]+$ ]] || [ "$moon_choice" -lt 1 ] || [ "$moon_choice" -gt ${#MOON_IDS[@]} ]; then
                    log "${RED}错误: 无效的选择${NC}"
                    return 1
                fi

                # 获取选择的 Moon ID 和文件
                MOON_ID="${MOON_IDS[$((moon_choice-1))]}"
                MOON_FILE="${MOON_FILES[$((moon_choice-1))]}"
            else
                # 只有一个 Moon 节点
                MOON_ID="${MOON_IDS[0]}"
                MOON_FILE="${MOON_FILES[0]}"
            fi

            log "${BLUE}选择的 Moon 节点: $MOON_ID${NC}"

            # 创建工作目录
            WORK_DIR="${SCRIPT_DIR}/moon_update"
            if [ -d "$WORK_DIR" ]; then
                rm -rf "$WORK_DIR"
            fi
            mkdir -p "$WORK_DIR"

            # 提取现有配置
            if [ -f "/var/lib/zerotier-one/moons.d/${MOON_ID}.moon" ]; then
                # 使用 zerotier-idtool 从现有 Moon 文件中提取配置
                log "${BLUE}提取现有 Moon 配置...${NC}"
                run_cmd "zerotier-idtool dumpjson /var/lib/zerotier-one/moons.d/${MOON_ID}.moon > \"$WORK_DIR/moon.conf\"" "提取 Moon 配置" || return 1

                # 更新 IP 地址 - 同时更新所有相关端点字段
                log "${BLUE}更新 IP 地址...${NC}"
                run_cmd "jq --arg ip \"$NEW_IP:9993\" '.stableEndpoints = [\$ip] | .roots[0].stableEndpoints = [\$ip]' \"$WORK_DIR/moon.conf\" > \"$WORK_DIR/moon_updated.conf\"" "更新端点信息" || return 1
                run_cmd "mv \"$WORK_DIR/moon_updated.conf\" \"$WORK_DIR/moon.conf\"" "更新配置文件" || return 1

                # 生成新的 Moon 文件
                log "${BLUE}生成新的 Moon 文件...${NC}"
                run_cmd "cd \"$WORK_DIR\" && zerotier-idtool genmoon \"$WORK_DIR/moon.conf\"" "生成 Moon 文件" || return 1

                # 查找生成的文件
                MOON_FILE=$(find "$WORK_DIR" -name "*${MOON_ID}.moon" -type f)
                if [ -z "$MOON_FILE" ]; then
                    log "${RED}错误: 新的 Moon 文件未生成${NC}"
                    return 1
                fi

                # 部署到服务器
                log "${BLUE}部署新的 Moon 文件到服务器...${NC}"
                run_cmd "cp \"$MOON_FILE\" /var/lib/zerotier-one/moons.d/" "更新 Moon 文件" || return 1

                # 重新生成客户端分发包
                regenerate_client_packages "$MOON_ID" "$MOON_FILE" "$NEW_IP"

                # 重启 ZeroTier 服务
                log "${BLUE}重启 ZeroTier 服务以应用更改...${NC}"
                restart_service

                # 等待服务重启完成
                log "${BLUE}等待服务重启完成...${NC}"
                sleep 5

                # 验证 Moon 节点连接
                log "${BLUE}验证 Moon 节点连接...${NC}"
                if zerotier-cli listpeers | grep -q "MOON ${MOON_ID}"; then
                    log "${GREEN}Moon 节点验证成功！${NC}"
                else
                    log "${YELLOW}警告: 无法验证 Moon 节点连接，请检查配置${NC}"
                    log "${YELLOW}您可以使用 'zerotier-cli listpeers | grep MOON' 命令手动验证${NC}"
                fi

                log "${GREEN}Moon 节点 IP 地址已更新为: $NEW_IP${NC}"
            else
                log "${RED}错误: 找不到 Moon 文件${NC}"
                return 1
            fi
            ;;

        2)
            # 重新生成客户端分发包
            log "${BLUE}重新生成客户端分发包...${NC}"

            # 获取 Moon ID 和文件
            MOON_ID=""
            MOON_FILE=""
            for moon_file in /var/lib/zerotier-one/moons.d/*.moon; do
                if [ -f "$moon_file" ]; then
                    MOON_ID=${moon_file##*/}
                    MOON_ID=${MOON_ID%.moon}
                    MOON_FILE=$moon_file
                    break
                fi
            done

            if [ -z "$MOON_ID" ] || [ -z "$MOON_FILE" ]; then
                log "${RED}错误: 无法获取 Moon ID 或文件${NC}"
                return 1
            fi

            # 获取当前 IP 地址
            CURRENT_IP=$(curl -s https://api.ipify.org)
            if ! validate_ip "$CURRENT_IP"; then
                log "${YELLOW}警告: 无法自动获取公网 IP${NC}"
                read -p "请输入此服务器的公网 IP 地址: " CURRENT_IP
                if ! validate_ip "$CURRENT_IP"; then
                    handle_error "CONFIG_ERROR" "无效的 IP 地址格式" "请输入有效的 IPv4 地址，格式为 x.x.x.x，其中 x 为 0-255 之间的数字" "prompt_ip_address CURRENT_IP"
                    if ! validate_ip "$CURRENT_IP"; then
                        log "${RED}IP 地址仍然无效，退出操作${NC}"
                        return 1
                    fi
                fi
            fi

            # 重新生成客户端分发包
            regenerate_client_packages "$MOON_ID" "$MOON_FILE" "$CURRENT_IP"

            log "${GREEN}客户端分发包已重新生成${NC}"
            ;;

        3)
            # 监控 Moon 节点性能
            log "${BLUE}监控 Moon 节点性能...${NC}"
            monitor_moon_node
            ;;

        4)
            # 持续监控 Moon 节点
            log "${BLUE}启动持续监控 Moon 节点...${NC}"
            continuous_monitoring
            ;;

        5)
            # 分析 ZeroTier 日志
            log "${BLUE}分析 ZeroTier 日志...${NC}"
            analyze_logs
            ;;

        6)
            log "${GREEN}返回主菜单${NC}"
            return 0
            ;;

        *)
            log "${RED}无效选择${NC}"
            return 1
            ;;
    esac

    return 0
}

# 函数: 生成增强的README.md内容
generate_enhanced_readme() {
    local MOON_ID="$1"
    local NODE_ID="$2"
    local PUBLIC_IP="$3"
    local MOON_FILENAME="$4"

    cat << EOF
# ZeroTier Moon 节点配置

## 什么是 Moon 节点？

Moon 节点是 ZeroTier 网络中的自定义根服务器，可以：
- 提供更稳定的连接和更低的延迟
- 改善 NAT 穿透能力
- 在复杂网络环境中提供更可靠的连接路径
- 增强私有网络的安全性和可控性

## 配置信息

- **Moon ID**: $MOON_ID
- **节点 ID**: $NODE_ID
- **服务器 IP**: $PUBLIC_IP

## 安装方法

### Windows 用户

1. 确保已安装并运行 ZeroTier
2. 双击运行 \`install_moon_windows.bat\` 脚本
3. 脚本将自动复制配置文件并重启 ZeroTier 服务

### macOS 用户

1. 确保已安装并运行 ZeroTier
2. 打开终端，进入此文件夹
3. 运行命令: \`./install_moon.sh\`

### Linux 用户

1. 确保已安装并运行 ZeroTier
2. 打开终端，进入此文件夹
3. 运行命令: \`./install_moon.sh\`

### 手动安装

如果自动脚本不起作用，您可以手动安装：

1. 找到 ZeroTier 的 moons.d 目录:
   - Windows: \`C:\ProgramData\ZeroTier\One\moons.d\`
   - macOS: \`/Library/Application Support/ZeroTier/One/moons.d\`
   - Linux: \`/var/lib/zerotier-one/moons.d\`

2. 将 \`$MOON_FILENAME\` 文件复制到该目录
3. 重启 ZeroTier 服务

### 命令行安装

如果您熟悉命令行，也可以使用以下命令连接到 Moon 节点：

\`\`\`
zerotier-cli orbit $MOON_ID $MOON_ID
\`\`\`

## 验证安装

安装完成后，可以使用以下命令验证 Moon 节点是否正常工作：

\`\`\`
zerotier-cli listpeers | grep MOON
\`\`\`

在输出中应该能看到与您的 Moon 节点的连接。

## 故障排除

### 常见问题及解决方案

#### 1. 连接超时问题

**症状**: 无法连接到 Moon 节点，或连接经常断开

**解决方案**:
- 确认 Moon 服务器的 IP 地址是否正确
- 检查 Moon 服务器的防火墙是否允许 UDP 端口 9993
- 尝试使用 \`ping\` 或 \`traceroute\` 检查与 Moon 服务器的连接
- 如果您在企业网络环境中，咨询网络管理员是否有限制策略

#### 2. NAT 穿透问题

**症状**: 连接状态显示 "RELAY" 而不是直接连接

**解决方案**:
- 如果您在严格的 NAT 环境中，可能需要在路由器上配置端口转发
- 尝试连接多个 Moon 节点以提高连接成功率
- 确保您的网络允许 UDP 穿透，某些企业网络可能会阻止此类流量

#### 3. 安装后无法找到 Moon 节点

**症状**: 使用 \`zerotier-cli listpeers | grep MOON\` 命令没有输出

**解决方案**:
- 确认安装脚本执行成功，没有报错
- 检查 Moon 文件是否正确复制到 moons.d 目录
- 尝试手动执行 \`zerotier-cli orbit $MOON_ID $MOON_ID\` 命令
- 重启 ZeroTier 服务后再次检查

#### 4. 性能问题

**症状**: 通过 Moon 节点的连接速度慢或延迟高

**解决方案**:
- 检查 Moon 服务器的网络带宽和负载
- 考虑在地理位置更接近的位置部署额外的 Moon 节点
- 确认您的网络连接质量良好

#### 5. 平台特定问题

##### Windows 特有问题
- 确保以管理员身份运行安装脚本
- 检查 Windows 防火墙是否允许 ZeroTier 通信
- 如果安装失败，尝试手动复制 Moon 文件到 \`C:\\ProgramData\\ZeroTier\\One\\moons.d\\\`

##### macOS 特有问题
- 确保已授予 ZeroTier 必要的系统权限
- 如果遇到权限问题，检查文件权限并使用 \`sudo\` 运行命令

##### Linux 特有问题
- 检查系统日志获取详细错误信息: \`journalctl -u zerotier-one\`
- 确保 moons.d 目录存在且有正确的权限

### 高级故障排除

如果基本故障排除步骤无法解决问题，请尝试以下高级方法：

1. **检查详细日志**:
   - Linux: \`journalctl -u zerotier-one\` 或 \`/var/log/syslog\`
   - macOS: \`sudo tail -f /var/log/system.log | grep ZeroTier\`
   - Windows: 事件查看器 > 应用程序和服务日志

2. **重置 Moon 连接**:
   \`\`\`
   zerotier-cli deorbit $MOON_ID
   zerotier-cli orbit $MOON_ID $MOON_ID
   \`\`\`

3. **验证网络配置**:
   - 使用 \`zerotier-cli info\` 检查节点状态
   - 使用 \`zerotier-cli listnetworks\` 检查网络配置

4. **检查端口可访问性**:
   - 使用在线端口检查工具验证 UDP 端口 9993 是否开放
   - 或使用命令: \`nc -zuv $PUBLIC_IP 9993\`

如果您仍然遇到问题，可以访问 [ZeroTier 社区论坛](https://discuss.zerotier.com/) 寻求帮助。
EOF
}

# 函数: 重新生成客户端分发包
regenerate_client_packages() {
    local MOON_ID="$1"
    local MOON_FILE="$2"
    local PUBLIC_IP="$3"
    local NODE_ID=$(zerotier-cli info | awk '{print $3}')

    # 创建工作目录
    local WORK_DIR="${SCRIPT_DIR}/moon_packages"
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
    mkdir -p "$WORK_DIR"

    # 复制 Moon 文件到工作目录
    cp "$MOON_FILE" "$WORK_DIR/"
    local MOON_FILENAME=$(basename "$MOON_FILE")

    log "${BLUE}创建客户端分发包...${NC}"

    # 为不同平台创建安装脚本
    # Windows 批处理脚本
    cat > "$WORK_DIR/install_moon_windows.bat" << EOF
@echo off
setlocal enabledelayedexpansion

echo ===================================
echo ZeroTier Moon Node Installation
echo ===================================
echo.

:: Check administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Error: Please run this script as administrator
    echo Right-click on the script and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

echo Step 1: Checking if ZeroTier is installed...
if not exist "%ProgramData%\ZeroTier\One" (
    echo Error: ZeroTier installation not detected
    echo Please install ZeroTier first, then run this script
    echo.
    pause
    exit /b 1
)

echo Step 2: Creating moons.d directory...
if not exist "%ProgramData%\ZeroTier\One\moons.d" (
    mkdir "%ProgramData%\ZeroTier\One\moons.d"
    if !errorlevel! neq 0 (
        echo Error: Cannot create moons.d directory
        echo.
        pause
        exit /b 1
    )
)

echo Step 3: Copying Moon file...
copy /Y "%~dp0${MOON_FILENAME}" "%ProgramData%\ZeroTier\One\moons.d\"
if %errorlevel% neq 0 (
    echo Error: Cannot copy Moon file
    echo Please make sure file "${MOON_FILENAME}" exists in the script directory
    echo.
    pause
    exit /b 1
)

echo Step 4: Restarting ZeroTier service...

:: Get the actual service name dynamically
for /f "delims=" %%i in ('powershell -Command "Get-Service | Where-Object { $_.DisplayName -like '*ZeroTier*' } | Select-Object -First 1 -ExpandProperty Name"') do set ZT_SERVICE=%%i

echo Stopping ZeroTier service [%ZT_SERVICE%]...
net stop %ZT_SERVICE%
if %errorlevel% neq 0 (
    echo Warning: Cannot stop ZeroTier service, it may not be running
)

echo Starting ZeroTier service...
net start %ZT_SERVICE%
if %errorlevel% neq 0 (
    echo Error: Cannot start ZeroTier service
    echo Please start the ZeroTier service manually or restart your computer
    echo.
    pause
    exit /b 1
)

echo.
echo ===================================
echo Installation Complete!
echo ===================================
echo.
echo Moon node configuration has been successfully installed
echo You can verify the installation by:
echo 1. Opening a command prompt
echo 2. Running the command: zerotier-cli listpeers ^| findstr MOON
echo.
echo If you see output containing MOON, the connection is successful
echo.
pause
EOF

    # Linux/macOS 脚本
    cat > "$WORK_DIR/install_moon.sh" << EOF
#!/bin/bash
echo "正在安装 ZeroTier Moon 节点配置..."

# 检测操作系统类型
if [ "$(uname)" == "Darwin" ]; then
    # macOS
    ZEROTIER_DIR="/Library/Application Support/ZeroTier/One/moons.d"
    mkdir -p "\$ZEROTIER_DIR"
    cp "$MOON_FILENAME" "\$ZEROTIER_DIR/"
    echo "重启 ZeroTier 服务..."
    launchctl unload /Library/LaunchDaemons/com.zerotier.one.plist
    launchctl load /Library/LaunchDaemons/com.zerotier.one.plist
else
    # Linux
    ZEROTIER_DIR="/var/lib/zerotier-one/moons.d"
    sudo mkdir -p "\$ZEROTIER_DIR"
    sudo cp "$MOON_FILENAME" "\$ZEROTIER_DIR/"
    echo "重启 ZeroTier 服务..."
    if command -v systemctl &>/dev/null; then
        sudo systemctl restart zerotier-one
    elif command -v service &>/dev/null; then
        sudo service zerotier-one restart
    else
        sudo killall zerotier-one
        sudo zerotier-one -d
    fi
fi

echo "Moon 节点配置安装完成！"
echo "您可以使用以下命令验证连接:"
echo "zerotier-cli listpeers | grep MOON"
EOF

    chmod +x "$WORK_DIR/install_moon.sh"

    # 创建增强的说明文档
    generate_enhanced_readme "$MOON_ID" "$NODE_ID" "$PUBLIC_IP" "$MOON_FILENAME" > "$WORK_DIR/README.md"
- 提供更稳定的连接和更低的延迟
- 改善 NAT 穿透能力
- 在复杂网络环境中提供更可靠的连接路径
- 增强私有网络的安全性和可控性

## 配置信息

- **Moon ID**: $MOON_ID
- **节点 ID**: $NODE_ID
- **服务器 IP**: $PUBLIC_IP

## 安装方法

### Windows 用户

1. 确保已安装并运行 ZeroTier
2. 双击运行 \`install_moon_windows.bat\` 脚本
3. 脚本将自动复制配置文件并重启 ZeroTier 服务

### macOS 用户

1. 确保已安装并运行 ZeroTier
2. 打开终端，进入此文件夹
3. 运行命令: \`./install_moon.sh\`

### Linux 用户

1. 确保已安装并运行 ZeroTier
2. 打开终端，进入此文件夹
3. 运行命令: \`./install_moon.sh\`

### 手动安装

如果自动脚本不起作用，您可以手动安装：

1. 找到 ZeroTier 的 moons.d 目录:
   - Windows: \`C:\ProgramData\ZeroTier\One\moons.d\`
   - macOS: \`/Library/Application Support/ZeroTier/One/moons.d\`
   - Linux: \`/var/lib/zerotier-one/moons.d\`

2. 将 \`$MOON_FILENAME\` 文件复制到该目录
3. 重启 ZeroTier 服务

### 命令行安装

如果您熟悉命令行，也可以使用以下命令连接到 Moon 节点：

\`\`\`
zerotier-cli orbit $MOON_ID $MOON_ID
\`\`\`

## 验证安装

安装完成后，可以使用以下命令验证 Moon 节点是否正常工作：

\`\`\`
zerotier-cli listpeers | grep MOON
\`\`\`

在输出中应该能看到与您的 Moon 节点的连接。

## 故障排除

如果遇到问题，请尝试：

1. 确认 ZeroTier 已正确安装并运行
2. 验证 Moon 文件已正确复制到 moons.d 目录
3. 重启计算机和网络设备
4. 检查防火墙是否允许 ZeroTier 通信（UDP 9993端口）
5. 确保您的网络允许 UDP 穿透，或配置端口转发
EOF

    # 创建一个 ZIP 压缩包
    log "${BLUE}打包客户端文件...${NC}"
    if command -v zip &>/dev/null; then
        run_cmd "cd \"$WORK_DIR\" && zip -r \"${SCRIPT_DIR}/zerotier_moon_${MOON_ID}.zip\" \"$MOON_FILENAME\" install_moon.sh install_moon_windows.bat README.md" "创建客户端分发包" || {
            log "${YELLOW}警告: 无法创建 ZIP 压缩包${NC}"
            # 创建一个目录作为替代
            DIST_DIR="${SCRIPT_DIR}/zerotier_moon_${MOON_ID}"
            mkdir -p "$DIST_DIR"
            cp "$WORK_DIR/$MOON_FILENAME" "$WORK_DIR/install_moon.sh" "$WORK_DIR/install_moon_windows.bat" "$WORK_DIR/README.md" "$DIST_DIR/"
            log "${GREEN}客户端配置文件已创建在: $DIST_DIR${NC}"
            return 0
        }
        log "${GREEN}客户端配置包已创建: ${SCRIPT_DIR}/zerotier_moon_${MOON_ID}.zip${NC}"
    else
        log "${YELLOW}警告: 未安装 zip 命令，无法创建压缩包${NC}"
        # 创建一个目录作为替代
        DIST_DIR="${SCRIPT_DIR}/zerotier_moon_${MOON_ID}"
        mkdir -p "$DIST_DIR"
        cp "$WORK_DIR/$MOON_FILENAME" "$WORK_DIR/install_moon.sh" "$WORK_DIR/install_moon_windows.bat" "$WORK_DIR/README.md" "$DIST_DIR/"
        log "${GREEN}客户端配置文件已创建在: $DIST_DIR${NC}"
    fi

    # 清理工作目录
    rm -rf "$WORK_DIR"
}

# 函数: 检查 ZeroTier 服务状态
check_zerotier_status() {
    log "${BLUE}检查 ZeroTier 服务状态...${NC}"

    # 检查服务是否运行
    local service_running=false
    if command -v systemctl &>/dev/null && systemctl is-active --quiet zerotier-one; then
        service_running=true
    elif command -v service &>/dev/null && service zerotier-one status >/dev/null 2>&1; then
        service_running=true
    elif pgrep -x "zerotier-one" >/dev/null; then
        service_running=true
    fi

    # 检查网络接口
    local interface_exists=false
    if ip link show | grep -q "zt"; then
        interface_exists=true
    fi

    # 检查是否可以获取节点信息
    local can_get_info=false
    if zerotier-cli info >/dev/null 2>&1; then
        can_get_info=true
    fi

    # 返回综合状态
    if $service_running && $interface_exists && $can_get_info; then
        log "${GREEN}ZeroTier 服务运行正常${NC}"
        return 0
    else
        log "${YELLOW}ZeroTier 服务状态异常:${NC}"
        if ! $service_running; then log "${YELLOW}- 服务未运行${NC}"; fi
        if ! $interface_exists; then log "${YELLOW}- 网络接口未创建${NC}"; fi
        if ! $can_get_info; then log "${YELLOW}- 无法获取节点信息${NC}"; fi
        return 1
    fi
}

# 函数: 增强错误处理
handle_error() {
    local error_code=$1
    local error_message=$2
    local recovery_suggestion=$3
    local recovery_command=$4

    log "${RED}错误 ($error_code): $error_message${NC}"
    if [ -n "$recovery_suggestion" ]; then
        log "${YELLOW}建议: $recovery_suggestion${NC}"
    fi

    # 询问用户是否尝试恢复
    if [ -n "$recovery_command" ]; then
        read -p "是否尝试自动修复此问题? [y/N]: " fix_choice
        if [[ "$fix_choice" == [yY] ]]; then
            log "${BLUE}尝试修复...${NC}"
            eval "$recovery_command"
            local status=$?
            if [ $status -eq 0 ]; then
                log "${GREEN}修复成功!${NC}"
                return 0
            else
                log "${RED}修复失败，请尝试手动解决问题${NC}"
                return 1
            fi
        fi
    fi

    # 根据错误类型执行不同的恢复操作
    case $error_code in
        "CONFIG_ERROR")
            log "${YELLOW}尝试恢复配置...${NC}"
            # 恢复配置的代码
            ;;
        "SERVICE_ERROR")
            log "${YELLOW}尝试重启服务...${NC}"
            restart_service
            ;;
        "NETWORK_ERROR")
            log "${YELLOW}检查网络连接...${NC}"
            if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
                log "${GREEN}网络连接正常${NC}"
            else
                log "${RED}网络连接异常，请检查网络设置${NC}"
            fi
            ;;
        "PERMISSION_ERROR")
            log "${YELLOW}检查权限...${NC}"
            if [ "$(id -u)" -ne 0 ]; then
                log "${RED}此操作需要 root 权限，请使用 sudo 或切换到 root 用户${NC}"
            fi
            ;;
        "DEPENDENCY_ERROR")
            log "${YELLOW}检查依赖...${NC}"
            check_commands
            ;;
        "PORT_ERROR")
            log "${YELLOW}检查端口...${NC}"
            if command -v netstat &>/dev/null; then
                netstat -tuln | grep 9993 || log "${RED}端口 9993 未开放${NC}"
            elif command -v ss &>/dev/null; then
                ss -tuln | grep 9993 || log "${RED}端口 9993 未开放${NC}"
            fi
            ;;
        # 其他错误类型...
    esac

    return 1
}

# 函数: 监控 Moon 节点性能
monitor_moon_node() {
    log "${BLUE}监控 Moon 节点性能...${NC}"

    # 获取 Moon ID
    local MOON_ID=""
    for moon_file in /var/lib/zerotier-one/moons.d/*.moon; do
        if [ -f "$moon_file" ]; then
            MOON_ID=${moon_file##*/}
            MOON_ID=${MOON_ID%.moon}
            break
        fi
    done

    if [ -z "$MOON_ID" ]; then
        log "${YELLOW}未找到 Moon 节点${NC}"
        return 1
    fi

    # 显示连接的对等节点数量
    local peer_count=$(zerotier-cli listpeers | grep -v "MOON" | wc -l)
    log "${GREEN}当前连接的对等节点数量: $peer_count${NC}"

    # 显示 Moon 节点的延迟信息
    log "${GREEN}Moon 节点连接状态:${NC}"
    zerotier-cli listpeers | grep "MOON"

    # 检查系统资源使用情况
    log "${GREEN}系统资源使用情况:${NC}"
    log "CPU 使用率: $(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')%"
    log "内存使用率: $(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2}')"
    log "ZeroTier 进程内存使用: $(ps -o rss= -p $(pgrep zerotier-one) | awk '{printf "%.2f MB", $1/1024}')"

    # 检查网络流量
    if command -v vnstat &>/dev/null; then
        log "${GREEN}网络流量统计:${NC}"
        vnstat -i $(ip -o link show | grep zt | awk -F': ' '{print $2}' | head -n 1) -h 1
    fi
}

# 函数: 持续监控 Moon 节点
continuous_monitoring() {
    log "${BLUE}启动持续监控...${NC}"

    # 设置监控参数
    local interval=60  # 监控间隔（秒）
    local duration=3600  # 默认监控持续时间（秒）
    local count=$((duration / interval))

    # 询问监控持续时间
    read -p "请输入监控持续时间（分钟）[默认: 60]: " duration_input
    if [[ "$duration_input" =~ ^[0-9]+$ ]]; then
        duration=$((duration_input * 60))
        count=$((duration / interval))
    fi

    # 询问监控间隔
    read -p "请输入监控间隔（秒）[默认: 60]: " interval_input
    if [[ "$interval_input" =~ ^[0-9]+$ ]] && [ "$interval_input" -gt 0 ]; then
        interval=$interval_input
        count=$((duration / interval))
    fi

    # 创建监控日志目录
    local log_dir="${SCRIPT_DIR}/moon_monitoring"
    mkdir -p "$log_dir"

    log "${GREEN}监控数据将保存到: $log_dir${NC}"
    log "${GREEN}监控间隔: ${interval}秒, 持续时间: $((duration/60))分钟${NC}"
    log "${YELLOW}按 Ctrl+C 停止监控${NC}"

    # 捕获 Ctrl+C
    trap "log '${YELLOW}监控已停止${NC}'; trap - INT; return 0" INT

    # 创建监控摘要文件
    local summary_file="${log_dir}/monitoring_summary.txt"
    {
        echo "===== ZeroTier Moon 节点监控摘要 ====="
        echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "监控间隔: ${interval}秒"
        echo "计划持续时间: $((duration/60))分钟"
        echo "计划采样次数: $count"
        echo "====================================="
        echo ""
    } > "$summary_file"

    # 开始监控循环
    local i=1
    local start_time=$(date +%s)

    while [ $i -le $count ]; do
        local timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
        local log_file="${log_dir}/moon_stats_${timestamp}.log"

        # 收集数据
        {
            echo "===== ZeroTier Moon 监控报告 ====="
            echo "时间: $(date)"
            echo "采样编号: $i / $count"
            echo ""

            echo "== Moon 节点信息 =="
            local moon_id=""
            for moon_file in /var/lib/zerotier-one/moons.d/*.moon; do
                if [ -f "$moon_file" ]; then
                    moon_id=${moon_file##*/}
                    moon_id=${moon_id%.moon}
                    echo "Moon ID: $moon_id"
                    break
                fi
            done

            echo ""
            echo "== 连接状态 =="
            zerotier-cli listpeers | grep "MOON" || echo "未检测到 Moon 连接"

            echo ""
            echo "== 对等节点数量 =="
            local peer_count=$(zerotier-cli listpeers | grep -v "MOON" | wc -l)
            echo "总数: $peer_count"

            echo ""
            echo "== 系统资源 =="
            local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
            local mem_usage=$(free -m | awk 'NR==2{printf "%.2f", $3*100/$2}')
            local zt_mem=$(ps -o rss= -p $(pgrep zerotier-one 2>/dev/null) | awk '{sum+=$1} END {printf "%.2f", sum/1024}')

            echo "CPU: ${cpu_usage}%"
            echo "内存: ${mem_usage}%"
            echo "ZeroTier 内存: ${zt_mem:-0} MB"

            echo ""
            echo "== 网络流量 =="
            if command -v vnstat &>/dev/null; then
                local zt_interface=$(ip -o link show | grep zt | awk -F': ' '{print $2}' | head -n 1)
                if [ -n "$zt_interface" ]; then
                    vnstat -i "$zt_interface" --oneline | sed 's/;/\n/g'
                else
                    echo "未找到 ZeroTier 网络接口"
                fi
            else
                echo "未安装 vnstat，无法获取网络流量统计"
            fi

            echo ""
            echo "== 连接延迟 =="
            zerotier-cli listpeers | grep -v "MOON" | awk '{print $3, $4}' | head -n 10

        } > "$log_file"

        # 更新摘要文件
        {
            echo "采样 $i ($(date '+%Y-%m-%d %H:%M:%S')):"
            echo "- 对等节点数量: $peer_count"
            echo "- CPU 使用率: ${cpu_usage}%"
            echo "- 内存使用率: ${mem_usage}%"
            echo "- ZeroTier 内存: ${zt_mem:-0} MB"
            echo ""
        } >> "$summary_file"

        log "${GREEN}已保存监控数据 ($i/$count): $log_file${NC}"

        # 检查是否已达到持续时间
        local current_time=$(date +%s)
        if [ $((current_time - start_time)) -ge $duration ]; then
            break
        fi

        # 等待下一个间隔
        sleep $interval
        i=$((i+1))
    done

    # 更新摘要文件结束信息
    {
        echo "====================================="
        echo "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "实际采样次数: $((i-1))"
        echo "监控摘要文件: $summary_file"
        echo "====================================="
    } >> "$summary_file"

    # 恢复 INT 信号处理
    trap - INT

    log "${GREEN}监控完成，共收集了 $((i-1)) 个采样${NC}"
    log "${GREEN}监控摘要文件: $summary_file${NC}"

    # 询问是否查看摘要
    read -p "是否查看监控摘要? [y/N]: " view_summary
    if [[ "$view_summary" == [yY] ]]; then
        if command -v less &>/dev/null; then
            less "$summary_file"
        else
            cat "$summary_file"
        fi
    fi

    return 0
}

# 函数: 分析 ZeroTier 日志
analyze_logs() {
    log "${BLUE}分析 ZeroTier 日志...${NC}"

    # 确定日志文件位置
    local log_files=()
    local log_file=""

    # 检查常见的日志文件位置
    if [ -f "/var/log/syslog" ]; then
        log_files+=("/var/log/syslog")
    fi

    if [ -f "/var/log/messages" ]; then
        log_files+=("/var/log/messages")
    fi

    # 检查 journalctl 是否可用
    local use_journalctl=false
    if command -v journalctl &>/dev/null && systemctl is-active --quiet zerotier-one; then
        use_journalctl=true
    fi

    # 如果没有找到日志文件且 journalctl 不可用，则退出
    if [ ${#log_files[@]} -eq 0 ] && [ "$use_journalctl" = false ]; then
        log "${YELLOW}无法找到系统日志文件，且 journalctl 不可用${NC}"
        log "${YELLOW}请手动检查系统日志以获取 ZeroTier 相关信息${NC}"
        return 1
    fi

    # 创建临时文件存储分析结果
    local temp_dir="${SCRIPT_DIR}/zerotier_logs_analysis"
    mkdir -p "$temp_dir"
    local analysis_file="${temp_dir}/zerotier_log_analysis_$(date '+%Y%m%d_%H%M%S').txt"

    {
        echo "===== ZeroTier 日志分析报告 ====="
        echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "====================================="
        echo ""
    } > "$analysis_file"

    # 分析函数
    analyze_log_content() {
        local content="$1"
        local source="$2"

        {
            echo "## 日志来源: $source"
            echo ""

            # 提取错误信息
            echo "### 错误事件 (最近 20 条)"
            echo ""
            echo "$(echo "$content" | grep -i "error" | grep -i "zerotier" | tail -n 20)"
            echo ""

            # 提取警告信息
            echo "### 警告事件 (最近 20 条)"
            echo ""
            echo "$(echo "$content" | grep -i "warn" | grep -i "zerotier" | tail -n 20)"
            echo ""

            # 提取连接事件
            echo "### 连接事件 (最近 20 条)"
            echo ""
            echo "$(echo "$content" | grep -i "peer" | grep -i "zerotier" | tail -n 20)"
            echo ""

            # 提取 Moon 相关事件
            echo "### Moon 节点事件 (最近 20 条)"
            echo ""
            echo "$(echo "$content" | grep -i "moon" | grep -i "zerotier" | tail -n 20)"
            echo ""

            # 提取启动和关闭事件
            echo "### 启动和关闭事件 (最近 10 条)"
            echo ""
            echo "$(echo "$content" | grep -i "start\|stop\|restart" | grep -i "zerotier" | tail -n 10)"
            echo ""

            # 提取网络加入和离开事件
            echo "### 网络加入和离开事件 (最近 10 条)"
            echo ""
            echo "$(echo "$content" | grep -i "join\|leave" | grep -i "zerotier" | tail -n 10)"
            echo ""
        } >> "$analysis_file"
    }

    # 使用 journalctl 分析
    if [ "$use_journalctl" = true ]; then
        log "${BLUE}使用 journalctl 分析 ZeroTier 日志...${NC}"
        local journal_content=$(journalctl -u zerotier-one --no-pager -n 1000)
        analyze_log_content "$journal_content" "journalctl (zerotier-one 服务)"
    fi

    # 分析找到的日志文件
    for log_file in "${log_files[@]}"; do
        log "${BLUE}分析日志文件: $log_file...${NC}"
        local file_content=$(grep -i "zerotier" "$log_file" | tail -n 1000)
        analyze_log_content "$file_content" "$log_file"
    done

    # 分析 ZeroTier 自身日志目录
    if [ -d "/var/lib/zerotier-one/log" ]; then
        log "${BLUE}分析 ZeroTier 日志目录...${NC}"
        for zt_log in /var/lib/zerotier-one/log/*.log; do
            if [ -f "$zt_log" ]; then
                local zt_log_content=$(cat "$zt_log" | tail -n 500)
                analyze_log_content "$zt_log_content" "$zt_log"
            fi
        done
    fi

    # 添加统计信息
    {
        echo "## 统计信息"
        echo ""

        # 统计错误和警告数量
        local error_count=0
        local warn_count=0
        local moon_count=0
        local peer_count=0

        for log_file in "${log_files[@]}"; do
            if [ -f "$log_file" ]; then
                error_count=$((error_count + $(grep -i "error" "$log_file" | grep -i "zerotier" | wc -l)))
                warn_count=$((warn_count + $(grep -i "warn" "$log_file" | grep -i "zerotier" | wc -l)))
                moon_count=$((moon_count + $(grep -i "moon" "$log_file" | grep -i "zerotier" | wc -l)))
                peer_count=$((peer_count + $(grep -i "peer" "$log_file" | grep -i "zerotier" | wc -l)))
            fi
        done

        if [ "$use_journalctl" = true ]; then
            error_count=$((error_count + $(journalctl -u zerotier-one --no-pager | grep -i "error" | wc -l)))
            warn_count=$((warn_count + $(journalctl -u zerotier-one --no-pager | grep -i "warn" | wc -l)))
            moon_count=$((moon_count + $(journalctl -u zerotier-one --no-pager | grep -i "moon" | wc -l)))
            peer_count=$((peer_count + $(journalctl -u zerotier-one --no-pager | grep -i "peer" | wc -l)))
        fi

        echo "- 错误事件总数: $error_count"
        echo "- 警告事件总数: $warn_count"
        echo "- Moon 相关事件总数: $moon_count"
        echo "- 对等节点事件总数: $peer_count"
        echo ""

        # 添加当前 ZeroTier 状态
        echo "## 当前 ZeroTier 状态"
        echo ""
        echo "### 节点信息"
        echo "$(zerotier-cli info 2>/dev/null || echo "无法获取节点信息")"
        echo ""

        echo "### 网络列表"
        echo "$(zerotier-cli listnetworks 2>/dev/null || echo "无法获取网络列表")"
        echo ""

        echo "### Moon 节点"
        echo "$(zerotier-cli listpeers | grep "MOON" 2>/dev/null || echo "未检测到 Moon 节点连接")"
        echo ""

        echo "====================================="
        echo "分析完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "分析报告保存在: $analysis_file"
        echo "====================================="
    } >> "$analysis_file"

    log "${GREEN}日志分析完成${NC}"
    log "${GREEN}分析报告保存在: $analysis_file${NC}"

    # 询问是否查看分析报告
    read -p "是否查看分析报告? [y/N]: " view_report
    if [[ "$view_report" == [yY] ]]; then
        if command -v less &>/dev/null; then
            less "$analysis_file"
        else
            cat "$analysis_file"
        fi
    fi

    return 0
}

# 函数: 检查 ZeroTier 更新
check_for_updates() {
    log "${BLUE}检查 ZeroTier 更新...${NC}"

    # 获取当前版本
    local current_version=$(zerotier-cli -v 2>/dev/null | awk '{print $4}')
    if [ -z "$current_version" ]; then
        current_version=$(zerotier-cli -v 2>/dev/null)
        if [ -z "$current_version" ]; then
            log "${YELLOW}警告: 无法获取当前 ZeroTier 版本${NC}"
            current_version="未知"
        fi
    fi

    log "${GREEN}当前版本: $current_version${NC}"

    # 获取最新版本
    log "${BLUE}正在检查最新版本...${NC}"
    local latest_version=""

    if command -v curl &>/dev/null; then
        latest_version=$(curl -s https://api.github.com/repos/zerotier/ZeroTierOne/releases/latest | grep -oP '"tag_name": "\K[^"]+' 2>/dev/null)
    elif command -v wget &>/dev/null; then
        latest_version=$(wget -qO- https://api.github.com/repos/zerotier/ZeroTierOne/releases/latest | grep -oP '"tag_name": "\K[^"]+' 2>/dev/null)
    fi

    if [ -z "$latest_version" ]; then
        log "${YELLOW}警告: 无法获取最新版本信息${NC}"
        log "${YELLOW}请访问 https://github.com/zerotier/ZeroTierOne/releases 查看最新版本${NC}"
        return 1
    fi

    log "${GREEN}最新版本: $latest_version${NC}"

    # 比较版本
    if [ "$current_version" = "未知" ]; then
        log "${YELLOW}无法比较版本，因为无法获取当前版本${NC}"
        read -p "是否仍然尝试更新 ZeroTier? [y/N]: " update_choice
        if [[ "$update_choice" != [yY] ]]; then
            log "${GREEN}已取消更新${NC}"
            return 0
        fi
    elif [ "$current_version" = "$latest_version" ]; then
        log "${GREEN}ZeroTier 已经是最新版本${NC}"
        return 0
    else
        log "${YELLOW}发现新版本: $latest_version${NC}"
        read -p "是否更新到最新版本? [y/N]: " update_choice
        if [[ "$update_choice" != [yY] ]]; then
            log "${GREEN}已取消更新${NC}"
            return 0
        fi
    fi

    # 执行更新
    log "${BLUE}开始更新 ZeroTier...${NC}"

    # 备份配置
    log "${BLUE}备份当前配置...${NC}"
    if is_moon_node_created; then
        backup_moon_config
    fi

    # 根据操作系统执行更新
    case $OS in
        ubuntu|debian)
            log "${BLUE}使用 apt 更新 ZeroTier...${NC}"
            run_cmd "apt-get update" "更新软件包列表" || log "${YELLOW}警告: 无法更新软件包列表${NC}"
            run_cmd "apt-get install -y zerotier-one" "更新 ZeroTier" || {
                log "${RED}错误: 无法使用 apt 更新 ZeroTier${NC}"
                log "${YELLOW}尝试使用一键安装脚本更新...${NC}"
                run_cmd "curl -s https://install.zerotier.com | bash" "使用一键安装脚本更新" || {
                    log "${RED}错误: 更新失败${NC}"
                    return 1
                }
            }
            ;;

        centos|rhel|fedora)
            if [ "$OS" = "fedora" ]; then
                log "${BLUE}使用 dnf 更新 ZeroTier...${NC}"
                run_cmd "dnf update -y zerotier-one" "更新 ZeroTier" || {
                    log "${RED}错误: 无法使用 dnf 更新 ZeroTier${NC}"
                    log "${YELLOW}尝试使用一键安装脚本更新...${NC}"
                    run_cmd "curl -s https://install.zerotier.com | bash" "使用一键安装脚本更新" || {
                        log "${RED}错误: 更新失败${NC}"
                        return 1
                    }
                }
            else
                log "${BLUE}使用 yum 更新 ZeroTier...${NC}"
                run_cmd "yum update -y zerotier-one" "更新 ZeroTier" || {
                    log "${RED}错误: 无法使用 yum 更新 ZeroTier${NC}"
                    log "${YELLOW}尝试使用一键安装脚本更新...${NC}"
                    run_cmd "curl -s https://install.zerotier.com | bash" "使用一键安装脚本更新" || {
                        log "${RED}错误: 更新失败${NC}"
                        return 1
                    }
                }
            fi
            ;;

        macos)
            log "${YELLOW}macOS 系统需要手动更新 ZeroTier${NC}"
            log "${YELLOW}请访问 https://www.zerotier.com/download/ 下载最新版本${NC}"
            return 0
            ;;

        *)
            log "${YELLOW}未知操作系统，尝试使用一键安装脚本更新...${NC}"
            run_cmd "curl -s https://install.zerotier.com | bash" "使用一键安装脚本更新" || {
                log "${RED}错误: 更新失败${NC}"
                return 1
            }
            ;;
    esac

    # 重启服务
    log "${BLUE}重启 ZeroTier 服务...${NC}"
    restart_service

    # 验证更新
    log "${BLUE}验证更新...${NC}"
    local new_version=$(zerotier-cli -v 2>/dev/null | awk '{print $4}')
    if [ -z "$new_version" ]; then
        new_version=$(zerotier-cli -v 2>/dev/null)
        if [ -z "$new_version" ]; then
            log "${YELLOW}警告: 无法获取更新后的 ZeroTier 版本${NC}"
            new_version="未知"
        fi
    fi

    log "${GREEN}更新后版本: $new_version${NC}"

    if [ "$new_version" = "$latest_version" ] || [ "$new_version" = "未知" ]; then
        log "${GREEN}ZeroTier 更新完成${NC}"
    else
        log "${YELLOW}警告: 更新可能未完全成功，请手动验证${NC}"
    fi

    # 如果是 Moon 节点，验证 Moon 节点连接
    if is_moon_node_created; then
        log "${BLUE}验证 Moon 节点连接...${NC}"
        local moon_id=""
        for moon_file in /var/lib/zerotier-one/moons.d/*.moon; do
            if [ -f "$moon_file" ]; then
                moon_id=${moon_file##*/}
                moon_id=${moon_id%.moon}
                break
            fi
        done

        if [ -n "$moon_id" ]; then
            if zerotier-cli listpeers | grep -q "MOON ${moon_id}"; then
                log "${GREEN}Moon 节点验证成功！${NC}"
            else
                log "${YELLOW}警告: 无法验证 Moon 节点连接，请检查配置${NC}"
                log "${YELLOW}您可以使用 'zerotier-cli listpeers | grep MOON' 命令手动验证${NC}"
            fi
        fi
    fi

    return 0
}

# 函数: 配置向导
configuration_wizard() {
    log "${BLUE}ZeroTier 配置向导${NC}"

    # 步骤 1: 基本信息收集
    log "${BLUE}步骤 1: 基本信息${NC}"

    # 获取公网 IP
    local PUBLIC_IP=$(curl -s https://api.ipify.org)
    if ! validate_ip "$PUBLIC_IP"; then
        log "${YELLOW}警告: 无法自动获取公网 IP${NC}"
        read -p "请输入此服务器的公网 IP 地址: " PUBLIC_IP
        if ! validate_ip "$PUBLIC_IP"; then
            handle_error "CONFIG_ERROR" "无效的 IP 地址格式" "请输入有效的 IPv4 地址，格式为 x.x.x.x，其中 x 为 0-255 之间的数字" "prompt_ip_address PUBLIC_IP"
            if ! validate_ip "$PUBLIC_IP"; then
                log "${RED}IP 地址仍然无效，退出操作${NC}"
                return 1
            fi
        fi
    fi

    log "${GREEN}服务器公网 IP: $PUBLIC_IP${NC}"

    # 获取节点 ID
    local NODE_ID=$(zerotier-cli info | awk '{print $3}')
    log "${GREEN}ZeroTier 节点 ID: $NODE_ID${NC}"

    # 步骤 2: 选择配置类型
    log "${BLUE}步骤 2: 选择配置类型${NC}"
    echo "1) 标准节点 - 仅加入网络"
    echo "2) 中继（Moon）节点 - 提供更稳定的连接"
    echo "3) 代理服务器 - 允许通过此服务器访问互联网"
    echo "4) 返回主菜单"

    read -p "请选择配置类型 [1-4]: " config_type

    # 根据选择执行不同的配置
    case $config_type in
        1)
            # 标准节点配置
            log "${BLUE}配置标准节点...${NC}"
            join_network
            ;;
        2)
            # 中继节点配置
            log "${BLUE}配置中继（Moon）节点...${NC}"
            if is_moon_node_created; then
                log "${YELLOW}检测到已存在 Moon 节点配置${NC}"
                read -p "是否要重新配置 Moon 节点? [y/N]: " reconfigure
                if [[ "$reconfigure" == [yY] ]]; then
                    configure_moon_node
                else
                    log "${GREEN}保留现有 Moon 节点配置${NC}"
                fi
            else
                configure_moon_node
            fi
            ;;
        3)
            # 代理服务器配置
            log "${BLUE}配置代理服务器...${NC}"
            PROXY_SERVER=true
            configure_proxy_server
            show_proxy_instructions
            ;;
        4)
            log "${GREEN}返回主菜单${NC}"
            return 0
            ;;
        *)
            log "${RED}无效选择${NC}"
            return 1
            ;;
    esac

    # 步骤 3: 验证配置
    log "${BLUE}步骤 3: 验证配置${NC}"
    check_zerotier_status

    # 步骤 4: 完成
    log "${GREEN}配置向导完成${NC}"
    log "${GREEN}您可以使用主菜单中的选项进一步管理 ZeroTier${NC}"

    return 0
}

# 函数: 状态仪表板
show_dashboard() {
    log "${BLUE}ZeroTier 状态仪表板${NC}"

    # 清屏
    clear

    # 显示标题
    echo "========================================"
    echo "       ZeroTier 状态仪表板"
    echo "========================================"
    echo ""

    # 显示基本信息
    echo "--- 基本信息 ---"
    zerotier-cli info
    echo ""

    # 显示网络信息
    echo "--- 网络信息 ---"
    zerotier-cli listnetworks
    echo ""

    # 显示 Moon 节点信息
    echo "--- Moon 节点信息 ---"
    if is_moon_node_created; then
        echo "状态: 已配置"
        zerotier-cli listpeers | grep "MOON"
    else
        echo "状态: 未配置"
    fi
    echo ""

    # 显示系统资源
    echo "--- 系统资源 ---"
    echo "CPU 使用率: $(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')%"
    echo "内存使用率: $(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2}')"
    echo "ZeroTier 进程内存: $(ps -o rss= -p $(pgrep zerotier-one) | awk '{printf "%.2f MB", $1/1024}')"
    echo ""

    # 显示连接的对等节点数量
    echo "--- 连接统计 ---"
    echo "对等节点总数: $(zerotier-cli listpeers | wc -l)"
    echo "直接连接数: $(zerotier-cli listpeers | grep -v RELAY | wc -l)"
    echo "中继连接数: $(zerotier-cli listpeers | grep RELAY | wc -l)"
    echo ""

    # 显示最近的日志
    echo "--- 最近日志 ---"
    if [ -f "/var/log/syslog" ]; then
        echo "$(grep -i "zerotier" /var/log/syslog | tail -n 5)"
    elif [ -f "/var/log/messages" ]; then
        echo "$(grep -i "zerotier" /var/log/messages | tail -n 5)"
    elif command -v journalctl &>/dev/null; then
        echo "$(journalctl -u zerotier-one --no-pager | tail -n 5)"
    else
        echo "无法获取日志信息"
    fi
    echo ""

    # 显示防火墙状态
    echo "--- 防火墙状态 ---"
    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        echo "UFW 状态: $(ufw status | grep 9993 || echo "端口 9993 可能未开放")"
    elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        echo "firewalld 状态: $(firewall-cmd --list-ports | grep 9993 || echo "端口 9993 可能未开放")"
    elif command -v iptables &>/dev/null; then
        echo "iptables 状态: $(iptables -L INPUT | grep 9993 || echo "端口 9993 可能未开放")"
    else
        echo "无法获取防火墙状态"
    fi
    echo ""

    echo "========================================"
    echo "按任意键返回主菜单"
    read -n 1

    return 0
}

# 函数: 配置防火墙
configure_firewall() {
    log "${BLUE}配置防火墙规则...${NC}"

    # 检测操作系统类型
    if [ "$OS" == "macos" ]; then
        log "${YELLOW}macOS 系统需要手动配置防火墙，请确保 UDP 端口 9993 已开放${NC}"
        return 0
    fi

    # 检测并配置不同类型的防火墙
    if command -v ufw &>/dev/null; then
        # Ubuntu/Debian with UFW
        log "${BLUE}检测到 UFW 防火墙，正在配置...${NC}"
        if ufw status | grep -q "active"; then
            run_cmd "ufw allow 9993/udp" "配置 UFW 防火墙" || {
                log "${YELLOW}警告: 无法配置 UFW 防火墙${NC}"
                log "${YELLOW}请手动运行: sudo ufw allow 9993/udp${NC}"
                return 1
            }
            log "${GREEN}UFW 防火墙已配置，UDP 端口 9993 已开放${NC}"
        else
            log "${YELLOW}UFW 防火墙未启用，跳过配置${NC}"
        fi
    elif command -v firewall-cmd &>/dev/null; then
        # CentOS/RHEL/Fedora with firewalld
        log "${BLUE}检测到 firewalld 防火墙，正在配置...${NC}"
        if systemctl is-active --quiet firewalld; then
            run_cmd "firewall-cmd --permanent --add-port=9993/udp" "配置 firewalld" || {
                log "${YELLOW}警告: 无法配置 firewalld${NC}"
                log "${YELLOW}请手动运行: sudo firewall-cmd --permanent --add-port=9993/udp${NC}"
                return 1
            }
            run_cmd "firewall-cmd --reload" "重载防火墙规则" || {
                log "${YELLOW}警告: 无法重载防火墙规则${NC}"
                log "${YELLOW}请手动运行: sudo firewall-cmd --reload${NC}"
                return 1
            }
            log "${GREEN}firewalld 防火墙已配置，UDP 端口 9993 已开放${NC}"
        else
            log "${YELLOW}firewalld 防火墙未启用，跳过配置${NC}"
        fi
    elif command -v iptables &>/dev/null; then
        # Generic Linux with iptables
        log "${BLUE}使用 iptables 配置防火墙...${NC}"
        run_cmd "iptables -C INPUT -p udp --dport 9993 -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport 9993 -j ACCEPT" "配置 iptables" || {
            log "${YELLOW}警告: 无法配置 iptables${NC}"
            log "${YELLOW}请手动运行: sudo iptables -A INPUT -p udp --dport 9993 -j ACCEPT${NC}"
            return 1
        }

        # 保存 iptables 规则
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
            log "${GREEN}iptables 规则已保存，将在系统重启后自动加载${NC}"
        else
            log "${YELLOW}警告: iptables-save 不可用，防火墙规则在重启后可能失效${NC}"
            log "${YELLOW}建议安装 iptables-persistent 包以保存规则${NC}"
        fi

        log "${GREEN}iptables 防火墙已配置，UDP 端口 9993 已开放${NC}"
    else
        log "${YELLOW}未检测到支持的防火墙系统，请手动确保 UDP 端口 9993 已开放${NC}"
        return 1
    fi

    log "${GREEN}防火墙配置完成${NC}"
    return 0
}

# 函数: 移除 Moon 节点
remove_moon_node() {
    log "${BLUE}移除 ZeroTier Moon 节点...${NC}"

    # 检查是否已创建 Moon 节点
    if ! is_moon_node_created; then
        log "${YELLOW}未检测到 Moon 节点配置${NC}"
        return 1
    fi

    # 检查是否为 macOS
    if [ "$OS" == "macos" ]; then
        log "${YELLOW}警告: 在 macOS 上移除 Moon 节点需要手动操作${NC}"
        log "${YELLOW}请参考 ZeroTier 文档进行手动配置${NC}"
        return 1
    fi

    # 检查系统权限
    if [ "$(id -u)" -ne 0 ]; then
        log "${RED}错误: 移除 Moon 节点需要 root 权限${NC}"
        return 1
    fi


    # 获取 Moon ID 用于日志记录
    MOON_IDS=""
    if [ -d "/var/lib/zerotier-one/moons.d" ]; then
        for moon_file in /var/lib/zerotier-one/moons.d/*.moon; do
            if [ -f "$moon_file" ]; then
                moon_id=${moon_file##*/}
                moon_id=${moon_id%.moon}
                MOON_IDS="${MOON_IDS} ${moon_id}"
            fi
        done
    fi

    # 移除所有 .moon 文件
    log "${BLUE}移除 Moon 文件...${NC}"
    if [ -d "/var/lib/zerotier-one/moons.d" ]; then
        run_cmd "rm -f /var/lib/zerotier-one/moons.d/*.moon" "移除 Moon 文件" || {
            log "${RED}错误: 无法移除 Moon 文件${NC}"
            return 1
        }
    else
        log "${YELLOW}警告: Moon 节点目录不存在${NC}"
    fi

    # 移除标记文件
    if [ -f "/var/lib/zerotier-one/.moon_configured" ]; then
        run_cmd "rm -f /var/lib/zerotier-one/.moon_configured" "移除标记文件" || log "${YELLOW}警告: 无法移除标记文件${NC}"
    fi

    # 清理临时文件
    log "${BLUE}清理临时文件...${NC}"
    run_cmd "rm -f /tmp/moon.json /tmp/moon.conf /tmp/*.moon" "清理临时文件" || log "${YELLOW}警告: 无法清理临时文件${NC}"

    # 清理工作目录
    for dir in "${SCRIPT_DIR}/moon_setup" "${SCRIPT_DIR}/moon_update" "${SCRIPT_DIR}/moon_packages"; do
        if [ -d "$dir" ]; then
            log "${BLUE}清理工作目录: $dir${NC}"
            run_cmd "rm -rf \"$dir\"" "清理工作目录" || log "${YELLOW}警告: 无法清理工作目录 $dir${NC}"
        fi
    done

    # 清理客户端分发包
    log "${BLUE}清理客户端分发包...${NC}"
    run_cmd "rm -rf ${SCRIPT_DIR}/zerotier_moon_*.zip ${SCRIPT_DIR}/zerotier_moon_*" "清理所有客户端分发包" || log "${YELLOW}警告: 无法清理客户端分发包${NC}"

    # 重启 ZeroTier 服务
    log "${BLUE}重启 ZeroTier 服务以应用更改...${NC}"
    restart_service

    # 确保 Moon 节点已完全移除
    log "${GREEN}Moon 节点已成功移除${NC}"

    if [ -n "$MOON_IDS" ]; then
        log "${GREEN}已移除的 Moon 节点 ID:${MOON_IDS}${NC}"
    fi
    log "${GREEN}所有相关配置文件已清理干净${NC}"
    log "${YELLOW}如果您有其他设备连接到此 Moon 节点，请在这些设备上运行以下命令以断开连接:${NC}"
    for moon_id in $MOON_IDS; do
        log "${YELLOW}zerotier-cli deorbit $moon_id${NC}"
    done

    return 0
}

# 函数: 配置 Moon 节点
function configure_moon_node() {
    log "${BLUE}正在配置 ZeroTier Moon 节点...${NC}"

    # 设置错误处理标志
    local CONFIGURATION_FAILED=false
    local ORIGINAL_CONFIG_BACKED_UP=false
    local BACKUP_DIR=""

    # 捕获错误并进行清理的函数
    cleanup_on_error() {
        if [ "$CONFIGURATION_FAILED" = true ]; then
            log "${RED}Moon 节点配置过程中发生错误，正在清理...${NC}"

            # 如果有备份，尝试恢复
            if [ "$ORIGINAL_CONFIG_BACKED_UP" = true ] && [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
                log "${YELLOW}尝试恢复原始配置...${NC}"

                # 恢复 moons.d 目录
                if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR"/*.moon 2>/dev/null)" ]; then
                    run_cmd "mkdir -p /var/lib/zerotier-one/moons.d" "创建 moons.d 目录" || true
                    run_cmd "cp -f \"$BACKUP_DIR/\"*.moon /var/lib/zerotier-one/moons.d/ 2>/dev/null" "恢复 Moon 文件" || true
                fi

                # 恢复标记文件
                if [ -f "$BACKUP_DIR/.moon_configured" ]; then
                    run_cmd "cp -f \"$BACKUP_DIR/.moon_configured\" /var/lib/zerotier-one/ 2>/dev/null" "恢复标记文件" || true
                fi

                # 重启服务
                log "${YELLOW}重启 ZeroTier 服务...${NC}"
                if command -v systemctl &>/dev/null; then
                    systemctl restart zerotier-one
                elif command -v service &>/dev/null; then
                    service zerotier-one restart
                else
                    killall zerotier-one 2>/dev/null || true
                    sleep 1
                    zerotier-one -d
                fi

                log "${YELLOW}已尝试恢复原始配置${NC}"
            else
                log "${YELLOW}没有可恢复的备份或备份为空${NC}"
            fi

            # 清理工作目录
            if [ -d "$WORK_DIR" ]; then
                log "${YELLOW}清理工作目录...${NC}"
                rm -rf "$WORK_DIR" 2>/dev/null || true
            fi

            log "${RED}Moon 节点配置失败${NC}"
            return 1
        fi
    }

    # 设置退出陷阱
    trap cleanup_on_error EXIT

    # 检查是否已经配置了 Moon 节点
    if is_moon_node_created; then
        log "${YELLOW}检测到已存在 Moon 节点配置${NC}"
        read -p "是否要重新配置 Moon 节点? [y/N]: " reconfigure
        if [[ "$reconfigure" != [yY] ]]; then
            log "${GREEN}保留现有 Moon 节点配置${NC}"
            trap - EXIT  # 移除陷阱
            return 0
        fi
        log "${BLUE}将重新配置 Moon 节点...${NC}"
        # 备份现有配置
        backup_moon_config
        ORIGINAL_CONFIG_BACKED_UP=true
        BACKUP_DIR="${SCRIPT_DIR}/moon_backup_$(date '+%Y%m%d_%H%M%S')"
    fi

    # 基本检查
    if ! zerotier-cli info &>/dev/null; then
        log "${RED}错误: ZeroTier 未运行${NC}"
        log "${YELLOW}尝试启动 ZeroTier 服务...${NC}"
        restart_service
        sleep 3
        if ! zerotier-cli info &>/dev/null; then
            log "${RED}错误: 无法启动 ZeroTier 服务${NC}"
            CONFIGURATION_FAILED=true
            return 1
        fi
    fi

    # 检查系统权限
    if [ "$(id -u)" -ne 0 ]; then
        log "${RED}错误: 配置 Moon 节点需要 root 权限${NC}"
        CONFIGURATION_FAILED=true
        return 1
    fi

    # 获取节点信息
    log "${BLUE}获取节点信息...${NC}"
    NODE_ID=$(zerotier-cli info | awk '{print $3}')
    PUBLIC_IP=$(curl -s https://api.ipify.org)

    if [[ -z "$NODE_ID" ]]; then
        log "${RED}错误: 无法获取 ZeroTier 节点 ID${NC}"
        CONFIGURATION_FAILED=true
        return 1
    fi

    if ! validate_ip "$PUBLIC_IP"; then
        log "${YELLOW}警告: 无法自动获取公网 IP${NC}"
        read -p "请手动输入此服务器的公网 IP 地址: " PUBLIC_IP
        if ! validate_ip "$PUBLIC_IP"; then
            handle_error "CONFIG_ERROR" "无效的 IP 地址格式" "请输入有效的 IPv4 地址，格式为 x.x.x.x，其中 x 为 0-255 之间的数字" "prompt_ip_address PUBLIC_IP"
            if ! validate_ip "$PUBLIC_IP"; then
                log "${RED}IP 地址仍然无效，退出操作${NC}"
                CONFIGURATION_FAILED=true
                return 1
            fi
        fi
    fi

    log "${BLUE}节点信息: ID=$NODE_ID, IP=$PUBLIC_IP${NC}"

    # 检查端口可访问性
    log "${BLUE}检查 UDP 端口 9993 可访问性...${NC}"
    PORT_CHECK_RESULT="未知"

    # 尝试使用不同的方法检查端口
    if command -v nc &>/dev/null; then
        # 使用 netcat 检查端口
        if timeout 5 nc -zu -w 5 $PUBLIC_IP 9993 >/dev/null 2>&1; then
            PORT_CHECK_RESULT="可能开放"
        else
            PORT_CHECK_RESULT="可能关闭"
        fi
    elif command -v curl &>/dev/null; then
        # 尝试使用外部服务检查端口
        if curl -s --max-time 10 "https://portcheck.transmissionbt.com/9993" | grep -q "open"; then
            PORT_CHECK_RESULT="开放"
        else
            PORT_CHECK_RESULT="关闭"
        fi
    fi

    if [ "$PORT_CHECK_RESULT" = "开放" ]; then
        log "${GREEN}UDP 端口 9993 检测结果: 开放 (可从互联网访问)${NC}"
    elif [ "$PORT_CHECK_RESULT" = "可能开放" ]; then
        log "${YELLOW}UDP 端口 9993 检测结果: 可能开放 (本地检测通过)${NC}"
        log "${YELLOW}建议: 确保您的防火墙或路由器允许 UDP 端口 9993 的入站流量${NC}"
    else
        log "${YELLOW}UDP 端口 9993 检测结果: ${PORT_CHECK_RESULT}${NC}"
        log "${YELLOW}警告: 端口 9993 可能无法从互联网访问，这可能影响 Moon 节点功能${NC}"
        log "${YELLOW}建议: 请确保您的防火墙或路由器允许 UDP 端口 9993 的入站流量${NC}"

        # 询问是否配置防火墙
        read -p "是否自动配置防火墙以开放 UDP 端口 9993? [Y/n]: " configure_fw
        if [[ "$configure_fw" != [nN] ]]; then
            configure_firewall
        else
            log "${YELLOW}跳过防火墙配置${NC}"
        fi

        # 询问是否继续
        read -p "是否继续配置 Moon 节点? [Y/n]: " continue_setup
        if [[ "$continue_setup" == [nN] ]]; then
            log "${YELLOW}已取消 Moon 节点配置${NC}"
            return 1
        fi
        log "${BLUE}继续配置 Moon 节点...${NC}"
    fi

    # 创建工作目录
    WORK_DIR="${SCRIPT_DIR}/moon_setup"
    if [ -d "$WORK_DIR" ]; then
        log "${BLUE}清理旧的工作目录...${NC}"
        rm -rf "$WORK_DIR"
    fi
    mkdir -p "$WORK_DIR"

    # 创建并修改 Moon 配置
    log "${BLUE}创建 Moon 配置...${NC}"

    # 检查 ZeroTier 身份文件
    if [ ! -f "/var/lib/zerotier-one/identity.public" ]; then
        log "${RED}错误: ZeroTier 身份文件不存在${NC}"
        log "${YELLOW}尝试重新初始化 ZeroTier...${NC}"
        restart_service
        sleep 3
        if [ ! -f "/var/lib/zerotier-one/identity.public" ]; then
            log "${RED}错误: 无法找到 ZeroTier 身份文件${NC}"
            return 1
        fi
    fi

    # 使用绝对路径，避免目录切换问题
    run_cmd "zerotier-idtool initmoon /var/lib/zerotier-one/identity.public > $WORK_DIR/moon.conf" "创建初始 Moon 配置" || {
        CONFIGURATION_FAILED=true
        return 1
    }

    # 安装 jq 如果需要
    if ! command -v jq &>/dev/null; then
        log "${YELLOW}正在安装 jq...${NC}"
        if command -v apt-get &>/dev/null; then
            run_cmd "apt-get update -y && apt-get install -y jq" "安装 jq" || {
                log "${RED}错误: 无法安装 jq${NC}"
                CONFIGURATION_FAILED=true
                return 1
            }
        elif command -v yum &>/dev/null; then
            run_cmd "yum install -y jq" "安装 jq" || {
                log "${RED}错误: 无法安装 jq${NC}"
                CONFIGURATION_FAILED=true
                return 1
            }
        else
            log "${RED}错误: 无法自动安装 jq，请手动安装后重试${NC}"
            CONFIGURATION_FAILED=true
            return 1
        fi
    fi

    # 添加端点信息 - 使用正确的格式 (IP:端口)
    log "${BLUE}配置 Moon 端点...${NC}"
    run_cmd "jq --arg ip \"$PUBLIC_IP:9993\" '.stableEndpoints = [\$ip] | .roots[0].stableEndpoints = [\$ip]' \"$WORK_DIR/moon.conf\" > \"$WORK_DIR/moon_updated.conf\"" "添加端点信息" || {
        CONFIGURATION_FAILED=true
        return 1
    }
    run_cmd "mv \"$WORK_DIR/moon_updated.conf\" \"$WORK_DIR/moon.conf\"" "更新配置文件" || {
        CONFIGURATION_FAILED=true
        return 1
    }

    # 提取 Moon ID
    MOON_ID=$(jq -r '.id' "$WORK_DIR/moon.conf")
    if [ -z "$MOON_ID" ]; then
        log "${RED}错误: 无法提取 Moon ID${NC}"
        CONFIGURATION_FAILED=true
        return 1
    fi
    log "${BLUE}Moon ID: $MOON_ID${NC}"

    # 生成 Moon 文件
    log "${BLUE}生成 Moon 文件...${NC}"
    run_cmd "cd \"$WORK_DIR\" && zerotier-idtool genmoon \"$WORK_DIR/moon.conf\"" "生成 Moon 文件" || {
        CONFIGURATION_FAILED=true
        return 1
    }

    # 查找生成的文件
    MOON_FILE=$(find "$WORK_DIR" -name "*${MOON_ID}.moon" -type f)
    if [ -z "$MOON_FILE" ]; then
        log "${RED}错误: Moon 文件未生成${NC}"
        CONFIGURATION_FAILED=true
        return 1
    fi

    # 部署到服务器
    log "${BLUE}部署 Moon 文件到服务器...${NC}"

    # 创建临时目录用于原子操作
    local TEMP_MOON_DIR="/tmp/zerotier_moon_deploy_$$"
    run_cmd "mkdir -p \"$TEMP_MOON_DIR\"" "创建临时部署目录" || {
        CONFIGURATION_FAILED=true
        return 1
    }

    # 复制 Moon 文件到临时目录
    run_cmd "cp \"$MOON_FILE\" \"$TEMP_MOON_DIR/\"" "复制 Moon 文件到临时目录" || {
        rm -rf "$TEMP_MOON_DIR"
        CONFIGURATION_FAILED=true
        return 1
    }

    # 创建标记文件到临时目录
    run_cmd "touch \"$TEMP_MOON_DIR/.moon_configured\"" "创建标记文件" || {
        log "${YELLOW}警告: 无法创建标记文件${NC}"
        rm -rf "$TEMP_MOON_DIR"
        CONFIGURATION_FAILED=true
        return 1
    }

    # 确保目标目录存在
    run_cmd "mkdir -p /var/lib/zerotier-one/moons.d" "创建 moons.d 目录" || {
        rm -rf "$TEMP_MOON_DIR"
        CONFIGURATION_FAILED=true
        return 1
    }

    # 原子操作：将临时目录中的文件移动到目标位置
    run_cmd "cp -f \"$TEMP_MOON_DIR/\"*.moon /var/lib/zerotier-one/moons.d/" "部署 Moon 文件" || {
        rm -rf "$TEMP_MOON_DIR"
        CONFIGURATION_FAILED=true
        return 1
    }

    run_cmd "cp -f \"$TEMP_MOON_DIR/.moon_configured\" /var/lib/zerotier-one/" "部署标记文件" || {
        log "${YELLOW}警告: 无法部署标记文件${NC}"
    }

    # 清理临时目录
    rm -rf "$TEMP_MOON_DIR"

    # 立即重启 ZeroTier 服务以应用 Moon 配置
    log "${BLUE}重启 ZeroTier 服务以应用 Moon 配置...${NC}"
    local RESTART_SUCCESS=false

    if command -v systemctl &>/dev/null; then
        if systemctl restart zerotier-one; then
            RESTART_SUCCESS=true
        fi
    elif command -v service &>/dev/null; then
        if service zerotier-one restart; then
            RESTART_SUCCESS=true
        fi
    else
        killall zerotier-one 2>/dev/null || true
        sleep 1
        if zerotier-one -d; then
            RESTART_SUCCESS=true
        fi
    fi

    if [ "$RESTART_SUCCESS" = false ]; then
        log "${RED}错误: 无法重启 ZeroTier 服务${NC}"
        CONFIGURATION_FAILED=true
        return 1
    fi

    # 等待服务完全启动
    log "${BLUE}等待 ZeroTier 服务启动...${NC}"
    sleep 5

    # 验证 Moon 节点配置是否成功
    log "${BLUE}验证 Moon 节点配置...${NC}"
    local VERIFICATION_ATTEMPTS=0
    local MOON_VERIFIED=false

    while [ $VERIFICATION_ATTEMPTS -lt 3 ]; do
        # 检查 Moon 文件是否存在
        if [ -f "/var/lib/zerotier-one/moons.d/${MOON_ID}.moon" ]; then
            # 检查 ZeroTier 是否识别到 Moon
            if zerotier-cli listpeers | grep -q "MOON"; then
                log "${GREEN}Moon 节点配置验证成功！${NC}"
                MOON_VERIFIED=true
                break
            fi
        fi

        VERIFICATION_ATTEMPTS=$((VERIFICATION_ATTEMPTS + 1))
        log "${YELLOW}Moon 节点验证尝试 $VERIFICATION_ATTEMPTS/3...${NC}"
        sleep 5
    done

    if [ "$MOON_VERIFIED" = false ]; then
        log "${YELLOW}警告: Moon 节点配置可能未完全生效，但将继续创建客户端分发包${NC}"
        log "${YELLOW}建议: 完成后手动检查 Moon 节点状态: zerotier-cli listpeers | grep MOON${NC}"
    fi

    # 创建客户端分发包
    log "${BLUE}创建客户端分发包...${NC}"

    # 提取 Moon 文件名
    local MOON_FILENAME=$(basename "$MOON_FILE")

    # 为不同平台创建安装脚本
    # Windows 批处理脚本
    cat > "$WORK_DIR/install_moon_windows.bat" << EOF
@echo off
setlocal enabledelayedexpansion

echo ===================================
echo ZeroTier Moon Node Installation
echo ===================================
echo.

:: Check administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Error: Please run this script as administrator
    echo Right-click on the script and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

echo Step 1: Checking if ZeroTier is installed...
if not exist "%ProgramData%\ZeroTier\One" (
    echo Error: ZeroTier installation not detected
    echo Please install ZeroTier first, then run this script
    echo.
    pause
    exit /b 1
)

echo Step 2: Creating moons.d directory...
if not exist "%ProgramData%\ZeroTier\One\moons.d" (
    mkdir "%ProgramData%\ZeroTier\One\moons.d"
    if !errorlevel! neq 0 (
        echo Error: Cannot create moons.d directory
        echo.
        pause
        exit /b 1
    )
)

echo Step 3: Copying Moon file...
copy /Y "%~dp0${MOON_FILENAME}" "%ProgramData%\ZeroTier\One\moons.d\"
if %errorlevel% neq 0 (
    echo Error: Cannot copy Moon file
    echo Please make sure file "${MOON_FILENAME}" exists in the script directory
    echo.
    pause
    exit /b 1
)

echo Step 4: Restarting ZeroTier service...

:: Get the actual service name dynamically
for /f "delims=" %%i in ('powershell -Command "Get-Service | Where-Object { $_.DisplayName -like '*ZeroTier*' } | Select-Object -First 1 -ExpandProperty Name"') do set ZT_SERVICE=%%i

echo Stopping ZeroTier service [%ZT_SERVICE%]...
net stop %ZT_SERVICE%
if %errorlevel% neq 0 (
    echo Warning: Cannot stop ZeroTier service, it may not be running
)

echo Starting ZeroTier service...
net start %ZT_SERVICE%
if %errorlevel% neq 0 (
    echo Error: Cannot start ZeroTier service
    echo Please start the ZeroTier service manually or restart your computer
    echo.
    pause
    exit /b 1
)

echo.
echo ===================================
echo Installation Complete!
echo ===================================
echo.
echo Moon node configuration has been successfully installed
echo You can verify the installation by:
echo 1. Opening a command prompt
echo 2. Running the command: zerotier-cli listpeers ^| findstr MOON
echo.
echo If you see output containing MOON, the connection is successful
echo.
pause
EOF

    # Linux/macOS 脚本
    cat > "$WORK_DIR/install_moon.sh" << EOF
#!/bin/bash
echo "正在安装 ZeroTier Moon 节点配置..."

# 检测操作系统类型
if [ "$(uname)" == "Darwin" ]; then
    # macOS
    ZEROTIER_DIR="/Library/Application Support/ZeroTier/One/moons.d"
    mkdir -p "\$ZEROTIER_DIR"
    cp "$MOON_FILENAME" "\$ZEROTIER_DIR/"
    echo "重启 ZeroTier 服务..."
    launchctl unload /Library/LaunchDaemons/com.zerotier.one.plist
    launchctl load /Library/LaunchDaemons/com.zerotier.one.plist
else
    # Linux
    ZEROTIER_DIR="/var/lib/zerotier-one/moons.d"
    sudo mkdir -p "\$ZEROTIER_DIR"
    sudo cp "$MOON_FILENAME" "\$ZEROTIER_DIR/"
    echo "重启 ZeroTier 服务..."
    if command -v systemctl &>/dev/null; then
        sudo systemctl restart zerotier-one
    elif command -v service &>/dev/null; then
        sudo service zerotier-one restart
    else
        sudo killall zerotier-one
        sudo zerotier-one -d
    fi
fi

echo "Moon 节点配置安装完成！"
echo "您可以使用以下命令验证连接:"
echo "zerotier-cli listpeers | grep MOON"
EOF

    chmod +x "$WORK_DIR/install_moon.sh"

    # 创建增强的说明文档
    generate_enhanced_readme "$MOON_ID" "$NODE_ID" "$PUBLIC_IP" "$MOON_FILENAME" > "$WORK_DIR/README.md"

    # 创建一个 ZIP 压缩包
    log "${BLUE}打包客户端文件...${NC}"
    if command -v zip &>/dev/null; then
        run_cmd "cd \"$WORK_DIR\" && zip -r \"${SCRIPT_DIR}/zerotier_moon_${MOON_ID}.zip\" \"$MOON_FILENAME\" install_moon.sh install_moon_windows.bat README.md" "创建客户端分发包" || {
            log "${YELLOW}警告: 无法创建 ZIP 压缩包${NC}"
            # 创建一个目录作为替代
            DIST_DIR="${SCRIPT_DIR}/zerotier_moon_${MOON_ID}"
            mkdir -p "$DIST_DIR"
            cp "$WORK_DIR/$MOON_FILENAME" "$WORK_DIR/install_moon.sh" "$WORK_DIR/install_moon_windows.bat" "$WORK_DIR/README.md" "$DIST_DIR/"
            log "${GREEN}客户端配置文件已创建在: $DIST_DIR${NC}"
        }
    else
        log "${YELLOW}警告: 未安装 zip 命令，无法创建压缩包${NC}"
        # 创建一个目录作为替代
        DIST_DIR="${SCRIPT_DIR}/zerotier_moon_${MOON_ID}"
        mkdir -p "$DIST_DIR"
        cp "$WORK_DIR/$MOON_FILENAME" "$WORK_DIR/install_moon.sh" "$WORK_DIR/install_moon_windows.bat" "$WORK_DIR/README.md" "$DIST_DIR/"
        log "${GREEN}客户端配置文件已创建在: $DIST_DIR${NC}"
    fi

    # 服务已在部署后重启，无需再次重启

    # 显示成功信息和下一步指导
    log "${GREEN}Moon 节点配置成功！${NC}"

    if [ -f "${SCRIPT_DIR}/zerotier_moon_${MOON_ID}.zip" ]; then
        log "${GREEN}客户端配置包已创建: ${SCRIPT_DIR}/zerotier_moon_${MOON_ID}.zip${NC}"
    else
        log "${GREEN}客户端配置文件已创建在: ${DIST_DIR}${NC}"
    fi

    log "${YELLOW}将配置包分发给客户端，并按照 README.md 中的说明安装${NC}"

    # 保留工作目录，以便后续使用
    log "${BLUE}工作目录已保留在: ${WORK_DIR}${NC}"

    # 移除错误处理陷阱
    trap - EXIT

    return 0
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
    log "${BLUE}版本: 1.1${NC}"

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

    # 首次执行脚本时，默认不配置代理服务器
    # 根据优化要求，首次执行不询问用户，直接进入普通安装流程
    PROXY_SERVER=false

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
