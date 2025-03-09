#!/bin/bash

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
BOLD='\033[1m'
NC='\033[0m'

# 镜像源列表（使用关联数组）
declare -A MIRRORS=(
    ["http://archive.ubuntu.com/ubuntu"]="Ubuntu官方"
    ["http://mirrors.aliyun.com/ubuntu"]="阿里云"
    ["http://mirrors.163.com/ubuntu"]="网易"
    ["https://mirrors.tuna.tsinghua.edu.cn/ubuntu"]="清华大学"
    ["https://mirrors.ustc.edu.cn/ubuntu"]="中国科学技术大学"
    ["https://repo.huaweicloud.com/ubuntu"]="华为云"
    ["https://mirrors.cloud.tencent.com/ubuntu"]="腾讯云"
    ["http://mirrors.zju.edu.cn/ubuntu"]="浙江大学"
    ["https://mirrors.sjtug.sjtu.edu.cn/ubuntu"]="上海交大"
    ["https://mirrors.bfsu.edu.cn/ubuntu"]="北外"
    ["https://mirrors.tuna.tsinghua.edu.cn/debian"]="清华大学"
    ["https://mirrors.aliyun.com/debian"]="阿里云"
    ["https://mirrors.ustc.edu.cn/debian"]="中国科学技术大学"
    ["https://deb.debian.org/debian"]="Debian官方"
    ["https://mirrors.kernel.org/debian"]="Kernel.org"
    ["https://ports.ubuntu.com/ubuntu-ports"]="Ubuntu Ports官方"
    ["https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports"]="清华大学"
)

# 配置文件路径
CONFIG_FILE="/etc/apt/sources.list"
UBUNTU_VER=$(lsb_release -rs | cut -d. -f1)
[ "$UBUNTU_VER" -ge 24 ] && CONFIG_FILE="/etc/apt/sources.list.d/ubuntu.sources"
BACKUP_DIR="/etc/apt/backup_$(date +%s)"
LOG_FILE="/tmp/apt-optimizer-$(date +%s).log"

# 系统信息收集
get_system_info() {
    OS_NAME=$(lsb_release -is)
    OS_VERSION=$(lsb_release -rs)
    ARCH=$(dpkg --print-architecture)

    echo -e "${BOLD}系统信息：${NC}"
    echo -e "  ${BLUE}操作系统：${NC}$OS_NAME $OS_VERSION"
    echo -e "  ${BLUE}处理器架构：${NC}$ARCH"

    echo -e "\n${BOLD}当前生效源：${NC}"
    if [ "$UBUNTU_VER" -ge 24 ]; then
        CURRENT_SOURCES=$(grep -E '^URIs:' "$CONFIG_FILE" | awk '{print $2}')
    else
        CURRENT_SOURCES=$(awk '/^deb / {print $2}' "$CONFIG_FILE")
    fi

    if [ -z "$CURRENT_SOURCES" ]; then
        echo -e "${YELLOW}⚠ 未找到有效用户源${NC}"
    else
        for source in $CURRENT_SOURCES; do
            echo "${MIRRORS[$source]} ($source)"
        done
    fi
}

# 依赖检查
check_deps() {
    command -v curl >/dev/null || {
        echo -e "${RED}缺少依赖: curl${NC}"
        sudo apt install -y curl 2>>"$LOG_FILE" || exit 1
    }
}

# 初始化日志
init_log() {
    echo "APT Optimizer Log - $(date)" > "$LOG_FILE"
    chmod 600 "$LOG_FILE"
}


# 进度条函数
progress_bar() {
    local current=$1
    local total=$2
    local bar_length=50
    local filled=$((current * bar_length / total))
    local empty=$((bar_length - filled))

    printf "\r[${GREEN}%-${filled}s${YELLOW}%-${empty}s${NC}] %3d%%" \
        "$(printf "%-${filled}s" | tr ' ' '#')" \
        "$(printf "%-${empty}s" | tr ' ' '-')" \
        $((current * 100 / total))
}

# 测试函数
test_source() {
    local url="$1/dists/$(lsb_release -cs)/main/binary-$ARCH/Packages.gz"
    local output=$(curl -sL --connect-timeout 3 -m 10 -w "%{http_code} %{time_total}" -o /dev/null "$url")
    local status=${output:0:3}
    local time=${output:4}

    if [[ $status -eq 200 ]]; then
        results+=("$1 $time")
        if echo "$CURRENT_SOURCES" | grep -q "$1"; then
            echo -e "${GREEN}✓当前生效源 ${BOLD}${MIRRORS[$1]}${NC} 耗时: ${time}s"
        else
            echo -e "${GREEN}✓ ${BOLD}${MIRRORS[$1]}${NC} 耗时: ${time}s"
        fi
    else
        results+=("$1 999.999")
        echo -e "${RED}✗ ${BOLD}${MIRRORS[$1]}${NC} 失败"
    fi
}

# 显示测试结果
show_results() {
    echo -e "\n${BOLD}测试结果排名：${NC}"
    echo -e " ${BLUE}排名 ${YELLOW}响应时间 ${GREEN}镜像源${NC}"
    echo -e "-------------------------------------------"

    local i=1
    for result in "${sorted[@]}"; do
        local source=$(echo "$result" | awk '{print $1}')
        local time=$(echo "$result" | awk '{print $2}')
        local provider=${MIRRORS[$source]}

        if (( $(echo "$time < 1.0" | bc -l) )); then
            color=$GREEN
        elif (( $(echo "$time < 3.0" | bc -l) )); then
            color=$YELLOW
        else
            color=$RED
        fi

        printf " ${color}%-4d ${YELLOW}%-8s ${GREEN}%-20s (${source})${NC}\n" $i "${time}s" "$provider"
        ((i++))
    done

    echo -e "${BLUE}===================================="${NC}
    for source in $CURRENT_SOURCES; do
        local rank=1
        for result in "${sorted[@]}"; do
            local test_source=$(echo "$result" | awk '{print $1}')
            if [ "$test_source" = "$source" ]; then
                echo -e "${GREEN}✓ 当前源排名 $rank ${MIRRORS[$source]} ($source)${NC}"
                break
            fi
            ((rank++))
        done
    done
    echo -e "${BLUE}===================================="${NC}
}

# 手动操作指南
manual_guide() {
    echo -e "\n${YELLOW}操作完成后的注意事项：${NC}"
    echo ""
    echo "手动恢复备份文件："
    echo "sudo cp $BACKUP_DIR/$(basename "$CONFIG_FILE") $CONFIG_FILE"
    echo ""
    echo "使用官方默认源："
    echo "sudo sed -i 's/mirror.*/archive.ubuntu.com/g' $CONFIG_FILE"
    echo ""
    echo "编辑源文件：sudo nano $CONFIG_FILE"
    echo ""
    echo -e "#配置模板："
    echo -e "${BLUE}===================================="${NC}
    if [ "$UBUNTU_VER" -ge 24 ]; then
        echo "Types: deb"
        echo "URIs: https://mirrors.tuna.tsinghua.edu.cn/ubuntu"
        echo "Suites: $(lsb_release -cs) $(lsb_release -cs)-updates $(lsb_release -cs)-security"
        echo "Components: main restricted universe multiverse"
        echo "Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg"
    else
        echo "deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $(lsb_release -cs) main restricted universe multiverse"
        echo "deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $(lsb_release -cs)-updates main restricted universe multiverse"
        echo "deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $(lsb_release -cs)-security main restricted universe multiverse"
    fi
    echo -e "${BLUE}===================================="${NC}
    echo -e "\n验证更新：sudo apt update"
    echo -e "系统升级：sudo apt upgrade"
}

# 主程序入口
main() {
    check_deps
    init_log
    get_system_info

    # 测试前准备
    ARCH=$(dpkg --print-architecture)
    declare -a test_sources
    for source in "${!MIRRORS[@]}"; do
        test_sources+=("$source")
    done

    echo -e "\n${BOLD}开始测试镜像源连接性（用户源$(echo "$CURRENT_SOURCES" | wc -w) 替换源${#test_sources[@]}）：${NC}"
    declare -a results
    local total=${#test_sources[@]}
    local current=0

    # 先测试用户源
    echo ""
    echo -e "${BLUE}===================================="${NC}
    for source in $CURRENT_SOURCES; do
        test_source "$source"
    done
    echo -e "${BLUE}===================================="${NC}
    echo ""

    # 再测试其他源
    for src in "${test_sources[@]}"; do
        if ! echo "$CURRENT_SOURCES" | grep -q "$src"; then
            test_source "$src"
            progress_bar $((++current)) $total
            echo
        fi
    done
    echo -e "\n"

    # 排序结果
    IFS=$'\n' sorted=($(sort -nk2 <<< "${results[*]}"))
    unset IFS

    show_results

    # 提示即将替换的源
    best_source_1=$(echo "${sorted[0]}" | awk '{print $1}')
    best_provider_1=${MIRRORS[$best_source_1]}
    echo -e "\n即将替换为： $best_provider_1"

    # 用户交互
    read -p $'\n是否替换为最佳镜像源？(输入排名数字或y/n): ' answer
    if [[ "$answer" =~ ^[Yy] ]]; then
        chosen_index=0
    elif [[ "$answer" =~ ^[0-9]+$ ]] && [ $answer -ge 1 ] && [ $answer -le ${#sorted[@]} ]; then
        chosen_index=$((answer - 1))
    else
        echo -e "\n${YELLOW}保持当前配置${NC}"
        return
    fi

    best_source=$(echo "${sorted[$chosen_index]}" | awk '{print $1}')
    best_provider=${MIRRORS[$best_source]}
    echo -e "\n${GREEN}即将替换为： $best_provider ${NC}"

    # 备份与替换
    sudo mkdir -p "$BACKUP_DIR"
    sudo cp "$CONFIG_FILE" "$BACKUP_DIR/"
    if [ "$UBUNTU_VER" -ge 24 ]; then
        sudo tee "$CONFIG_FILE" >/dev/null <<EOF
Types: deb
URIs: $best_source
Suites: $(lsb_release -cs) $(lsb_release -cs)-updates $(lsb_release -cs)-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
    else
        sudo sed -i "s|^deb.*|deb $best_source $(lsb_release -cs) main restricted universe multiverse|" "$CONFIG_FILE"
    fi

    # 更新验证
    echo -e "\n${GREEN}正在更新软件列表...${NC}"
    if sudo apt update; then
        echo -e "\n${BOLD}当前镜像源：${NC}"
        echo "$best_provider ($best_source)"

        echo -e "\n${GREEN}替换成功！ $best_provider${NC}"
    else
        echo -e "\n${RED}更新失败，请检查日志：${NC}"
        tail -n 10 /tmp/apt-update.log
        echo -e "${YELLOW}正在恢复备份...${NC}"
        sudo cp "$BACKUP_DIR/$(basename "$CONFIG_FILE")" "$CONFIG_FILE"
        exit 1
    fi

    manual_guide
}

main