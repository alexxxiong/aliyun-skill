#!/bin/bash
# output.sh - 输出格式化
# 使用方法: source output.sh

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 状态图标
status_icon() {
    case "$1" in
        Running|Available|Active|InUse|ENABLE)
            echo -e "${GREEN}●${NC}" ;;
        Stopped|Unavailable|Inactive|Creating)
            echo -e "${YELLOW}●${NC}" ;;
        Error|Failed|Deleted|DISABLE)
            echo -e "${RED}●${NC}" ;;
        *)
            echo -e "${BLUE}●${NC}" ;;
    esac
}

# 格式化状态文本
format_status() {
    local status="$1"
    case "$status" in
        Running|Available|Active)
            echo -e "${GREEN}$status${NC}" ;;
        Stopped|Unavailable|Inactive)
            echo -e "${YELLOW}$status${NC}" ;;
        Error|Failed)
            echo -e "${RED}$status${NC}" ;;
        *)
            echo "$status" ;;
    esac
}

# 计算数据量并选择格式
auto_format() {
    local data="$1"
    local format="${2:-auto}"
    local count=$(echo "$data" | jq 'if type == "array" then length else 1 end' 2>/dev/null || echo "1")

    if [[ "$format" == "json" ]]; then
        echo "$data" | jq '.'
        return
    fi

    if [[ "$format" == "table" ]]; then
        format_table "$data"
        return
    fi

    # auto 模式
    if (( count <= 3 )); then
        format_detail "$data"
    elif (( count <= 20 )); then
        format_table "$data"
    else
        format_summary "$data" "$count"
    fi
}

# 详细卡片视图
format_detail() {
    local data="$1"
    # 由各资源脚本实现具体格式
    echo "$data" | jq '.'
}

# 表格视图
format_table() {
    local data="$1"
    # 由各资源脚本实现具体格式
    echo "$data" | jq -r '.'
}

# 摘要视图
format_summary() {
    local data="$1"
    local count="$2"

    echo ""
    echo -e "${BOLD}📊 共 $count 条记录${NC}"
    echo ""
    echo "💡 使用 --limit N 限制显示数量"
    echo "   使用 --filter 'key=value' 筛选"
    echo "   使用 --json 查看完整数据"
    echo ""
}

# 打印分隔线
print_separator() {
    local char="${1:--}"
    local width="${2:-60}"
    printf '%*s\n' "$width" '' | tr ' ' "$char"
}

# 打印标题
print_title() {
    local title="$1"
    echo ""
    echo -e "${BOLD}${CYAN}$title${NC}"
    print_separator "─"
}

# 打印键值对
print_kv() {
    local key="$1"
    local value="$2"
    local width="${3:-15}"
    printf "  %-${width}s %s\n" "$key:" "$value"
}

# 打印成功消息
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# 打印警告消息
print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# 打印错误消息
print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 打印信息消息
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# 确认提示
confirm_action() {
    local message="$1"
    local default="${2:-n}"

    echo ""
    echo -e "${YELLOW}⚠️  $message${NC}"
    echo ""

    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="(Y/n)"
    else
        prompt="(y/N)"
    fi

    read -p "确认执行？$prompt " -n 1 -r
    echo ""

    if [[ "$default" == "y" ]]; then
        [[ ! $REPLY =~ ^[Nn]$ ]]
    else
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}

# 打印操作详情框
print_action_box() {
    local action="$1"
    local resource="$2"
    local detail="$3"

    echo ""
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  ⚠️  $action 确认"
    echo "├─────────────────────────────────────────────────────────┤"
    echo "│"
    echo "│  操作: $action"
    echo "│  资源: $resource"
    [[ -n "$detail" ]] && echo "│  详情: $detail"
    echo "│"
    echo "│  (y) 确认  (n) 取消  (d) 查看详情"
    echo "│"
    echo "└─────────────────────────────────────────────────────────┘"
}
