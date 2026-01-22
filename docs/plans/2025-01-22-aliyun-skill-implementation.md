# Aliyun Skill 实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 实现阿里云资源管理 Skill，支持 ECS/OSS/DNS/RDS 等资源的查询和操作

**Architecture:** 主 skill 文件 + 辅助 shell 脚本 + Python SDK 脚本，通过 install.sh 一键安装到 ~/.claude/

**Tech Stack:** Bash, Python 3, aliyun CLI, jq, yq

---

## Task 1: 项目基础设施

**Files:**
- Create: `install.sh`
- Create: `uninstall.sh`
- Create: `plugins/aliyun/.gitkeep`
- Create: `plugins/aliyun/cli/.gitkeep`
- Create: `plugins/aliyun/sdk/.gitkeep`
- Create: `commands/.gitkeep`

**Step 1: 创建目录结构**

```bash
cd /Users/alexxiong/Documents/03-Infrastructure/Tools/claude-skills/aliyun-skill
mkdir -p commands plugins/aliyun/cli plugins/aliyun/sdk
touch commands/.gitkeep plugins/aliyun/.gitkeep plugins/aliyun/cli/.gitkeep plugins/aliyun/sdk/.gitkeep
```

**Step 2: 创建 install.sh**

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
PLUGIN_DIR="$CLAUDE_DIR/plugins/aliyun"

echo "======================================"
echo "  Aliyun Skill 安装程序"
echo "======================================"
echo ""

# 检查依赖
check_dependencies() {
    local missing=()

    if ! command -v aliyun &>/dev/null; then
        missing+=("aliyun-cli")
    fi

    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi

    if ! command -v yq &>/dev/null; then
        missing+=("yq")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "⚠️  缺少依赖，建议安装："
        for dep in "${missing[@]}"; do
            case "$dep" in
                aliyun-cli) echo "   brew install aliyun-cli  # 或参考 https://help.aliyun.com/document_detail/139508.html" ;;
                jq) echo "   brew install jq" ;;
                yq) echo "   brew install yq" ;;
            esac
        done
        echo ""
        read -p "是否继续安装？(y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "安装已取消"
            exit 1
        fi
    else
        echo "✅ 依赖检查通过"
    fi
}

# 安装文件
install_files() {
    echo ""
    echo "📦 安装文件..."

    # 创建目录
    mkdir -p "$CLAUDE_DIR/commands"
    mkdir -p "$PLUGIN_DIR/cli"
    mkdir -p "$PLUGIN_DIR/sdk"

    # 复制 skill 文件
    if [[ -f "$SCRIPT_DIR/commands/aliyun.md" ]]; then
        cp "$SCRIPT_DIR/commands/aliyun.md" "$CLAUDE_DIR/commands/"
        echo "   ✓ commands/aliyun.md"
    fi

    # 复制插件文件
    for f in "$SCRIPT_DIR/plugins/aliyun/"*.sh; do
        [[ -f "$f" ]] && cp "$f" "$PLUGIN_DIR/" && echo "   ✓ plugins/aliyun/$(basename "$f")"
    done

    # 复制 CLI 脚本
    for f in "$SCRIPT_DIR/plugins/aliyun/cli/"*.sh; do
        [[ -f "$f" ]] && cp "$f" "$PLUGIN_DIR/cli/" && echo "   ✓ plugins/aliyun/cli/$(basename "$f")"
    done

    # 复制 SDK 脚本
    for f in "$SCRIPT_DIR/plugins/aliyun/sdk/"*; do
        [[ -f "$f" ]] && cp "$f" "$PLUGIN_DIR/sdk/" && echo "   ✓ plugins/aliyun/sdk/$(basename "$f")"
    done

    # 设置执行权限
    chmod +x "$PLUGIN_DIR/"*.sh 2>/dev/null || true
    chmod +x "$PLUGIN_DIR/cli/"*.sh 2>/dev/null || true
}

# 主流程
main() {
    check_dependencies
    install_files

    echo ""
    echo "======================================"
    echo "  ✅ 安装完成！"
    echo "======================================"
    echo ""
    echo "使用方法："
    echo "  /aliyun config    # 首次配置"
    echo "  /aliyun ecs list  # 列出 ECS 实例"
    echo "  /aliyun --help    # 查看帮助"
    echo ""
}

main "$@"
```

**Step 3: 创建 uninstall.sh**

```bash
#!/bin/bash
set -e

CLAUDE_DIR="$HOME/.claude"

echo "======================================"
echo "  Aliyun Skill 卸载程序"
echo "======================================"
echo ""

read -p "确定要卸载 aliyun-skill 吗？(y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "卸载已取消"
    exit 0
fi

echo "🗑️  删除文件..."

# 删除 skill 文件
rm -f "$CLAUDE_DIR/commands/aliyun.md" && echo "   ✓ commands/aliyun.md"

# 删除插件目录
rm -rf "$CLAUDE_DIR/plugins/aliyun" && echo "   ✓ plugins/aliyun/"

echo ""
echo "✅ 卸载完成！"
echo ""
echo "注意：配置文件 ~/.claude/plugins/aliyun/config.yaml 已删除"
echo "      如需保留配置，请在卸载前备份"
```

**Step 4: 设置执行权限并提交**

```bash
chmod +x install.sh uninstall.sh
git init
git add .
git commit -m "feat: 初始化项目结构和安装脚本"
```

---

## Task 2: 凭证管理模块 auth.sh

**Files:**
- Create: `plugins/aliyun/auth.sh`

**Step 1: 创建 auth.sh**

```bash
#!/bin/bash
# auth.sh - 阿里云凭证加载与验证
# 使用方法: source auth.sh && load_credentials

ALIYUN_PLUGIN_DIR="$HOME/.claude/plugins/aliyun"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 全局变量
export ALIBABA_CLOUD_ACCESS_KEY_ID=""
export ALIBABA_CLOUD_ACCESS_KEY_SECRET=""
export ALIBABA_CLOUD_REGION_ID=""
export CREDENTIAL_SOURCE=""
export CREDENTIAL_STATUS=""

# 从项目配置加载
load_from_project() {
    local project_config=".aliyun.yaml"

    if [[ -f "$project_config" ]]; then
        local profile=$(yq -r '.profile // empty' "$project_config" 2>/dev/null)
        local region=$(yq -r '.region // empty' "$project_config" 2>/dev/null)

        if [[ -n "$profile" ]]; then
            echo "project:$profile"
            [[ -n "$region" ]] && export ALIBABA_CLOUD_REGION_ID="$region"
            return 0
        fi
    fi
    return 1
}

# 从 aliyun CLI 配置加载
load_from_cli_config() {
    local profile="${1:-default}"
    local config_file="$HOME/.aliyun/config.json"

    if [[ -f "$config_file" ]]; then
        local access_key_id=$(jq -r --arg p "$profile" '.profiles[] | select(.name == $p) | .access_key_id // empty' "$config_file" 2>/dev/null)
        local access_key_secret=$(jq -r --arg p "$profile" '.profiles[] | select(.name == $p) | .access_key_secret // empty' "$config_file" 2>/dev/null)
        local region_id=$(jq -r --arg p "$profile" '.profiles[] | select(.name == $p) | .region_id // empty' "$config_file" 2>/dev/null)

        if [[ -n "$access_key_id" && -n "$access_key_secret" ]]; then
            export ALIBABA_CLOUD_ACCESS_KEY_ID="$access_key_id"
            export ALIBABA_CLOUD_ACCESS_KEY_SECRET="$access_key_secret"
            [[ -n "$region_id" ]] && export ALIBABA_CLOUD_REGION_ID="$region_id"
            return 0
        fi
    fi
    return 1
}

# 从环境变量加载
load_from_env() {
    if [[ -n "$ALIBABA_CLOUD_ACCESS_KEY_ID" && -n "$ALIBABA_CLOUD_ACCESS_KEY_SECRET" ]]; then
        return 0
    fi
    return 1
}

# 列出可用的 profiles
list_profiles() {
    local config_file="$HOME/.aliyun/config.json"

    if [[ -f "$config_file" ]]; then
        jq -r '.profiles[].name' "$config_file" 2>/dev/null
    fi
}

# 验证凭证有效性
validate_credentials() {
    if [[ -z "$ALIBABA_CLOUD_ACCESS_KEY_ID" || -z "$ALIBABA_CLOUD_ACCESS_KEY_SECRET" ]]; then
        export CREDENTIAL_STATUS="missing"
        return 1
    fi

    # 尝试调用 STS GetCallerIdentity 验证
    local result=$(aliyun sts GetCallerIdentity 2>&1)

    if echo "$result" | grep -q "AccountId"; then
        export CREDENTIAL_STATUS="authorized"
        return 0
    elif echo "$result" | grep -q "InvalidAccessKeyId"; then
        export CREDENTIAL_STATUS="invalid"
        return 1
    else
        # 其他错误也视为有效（可能是权限问题但凭证本身有效）
        export CREDENTIAL_STATUS="authorized"
        return 0
    fi
}

# 主加载函数
load_credentials() {
    local specified_profile="$1"

    # 1. 检查项目配置
    local project_result=$(load_from_project)
    if [[ -n "$project_result" ]]; then
        local profile="${project_result#project:}"
        if load_from_cli_config "$profile"; then
            export CREDENTIAL_SOURCE="project:$profile"
            validate_credentials
            return $?
        fi
    fi

    # 2. 使用指定的 profile 或 default
    local profile="${specified_profile:-default}"
    if load_from_cli_config "$profile"; then
        export CREDENTIAL_SOURCE="cli:$profile"
        validate_credentials
        return $?
    fi

    # 3. 尝试环境变量
    if load_from_env; then
        export CREDENTIAL_SOURCE="env"
        validate_credentials
        return $?
    fi

    export CREDENTIAL_STATUS="missing"
    return 1
}

# 显示凭证状态
show_credential_status() {
    echo ""
    echo "凭证状态检查："

    # 检查项目配置
    if [[ -f ".aliyun.yaml" ]]; then
        local profile=$(yq -r '.profile // empty' ".aliyun.yaml" 2>/dev/null)
        echo -e "  项目配置: ${GREEN}发现${NC} (profile: $profile)"
    else
        echo -e "  项目配置: ${YELLOW}未找到${NC}"
    fi

    # 检查 CLI 配置
    if [[ -f "$HOME/.aliyun/config.json" ]]; then
        local profiles=$(list_profiles | tr '\n' ', ' | sed 's/,$//')
        echo -e "  CLI 配置: ${GREEN}发现${NC} (profiles: $profiles)"
    else
        echo -e "  CLI 配置: ${YELLOW}未找到${NC}"
    fi

    # 检查环境变量
    if [[ -n "$ALIBABA_CLOUD_ACCESS_KEY_ID" ]]; then
        echo -e "  环境变量: ${GREEN}已设置${NC}"
    else
        echo -e "  环境变量: ${YELLOW}未设置${NC}"
    fi

    echo ""
}

# 获取当前身份信息
get_caller_identity() {
    aliyun sts GetCallerIdentity --output cols=AccountId,Arn,UserId 2>/dev/null
}
```

**Step 2: 提交**

```bash
git add plugins/aliyun/auth.sh
git commit -m "feat: 添加凭证管理模块 auth.sh"
```

---

## Task 3: 首次引导模块 init.sh

**Files:**
- Create: `plugins/aliyun/init.sh`

**Step 1: 创建 init.sh**

```bash
#!/bin/bash
# init.sh - 首次配置引导
# 使用方法: ./init.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/auth.sh"

CONFIG_FILE="$ALIYUN_PLUGIN_DIR/config.yaml"

# 检查是否需要初始化
need_init() {
    [[ ! -f "$CONFIG_FILE" ]]
}

# 选择菜单
select_option() {
    local prompt="$1"
    shift
    local options=("$@")

    echo "$prompt"
    for i in "${!options[@]}"; do
        echo "  ($((i+1))) ${options[$i]}"
    done

    local choice
    while true; do
        read -p "请选择 [1-${#options[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            return $((choice - 1))
        fi
        echo "无效选择，请重新输入"
    done
}

# 主引导流程
run_init() {
    echo ""
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│             🚀 阿里云资源管理 - 首次配置                   │"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    # Step 1: 显示凭证状态
    show_credential_status

    # Step 2: 选择 profile
    local profiles=($(list_profiles))
    local selected_profile="default"
    local credential_source="env"

    if [[ ${#profiles[@]} -gt 0 ]]; then
        profiles+=("使用环境变量")
        echo "请选择默认凭证来源："
        select_option "" "${profiles[@]}"
        local idx=$?

        if (( idx < ${#profiles[@]} - 1 )); then
            selected_profile="${profiles[$idx]}"
            credential_source="cli_profile"
        else
            credential_source="env"
        fi
    elif [[ -n "$ALIBABA_CLOUD_ACCESS_KEY_ID" ]]; then
        echo "将使用环境变量中的凭证"
        credential_source="env"
    else
        echo -e "${YELLOW}⚠️  未找到任何凭证配置${NC}"
        echo ""
        echo "请先配置阿里云凭证，可选方式："
        echo "  1. 运行 aliyun configure 配置 CLI"
        echo "  2. 设置环境变量 ALIBABA_CLOUD_ACCESS_KEY_ID 和 ALIBABA_CLOUD_ACCESS_KEY_SECRET"
        echo ""
        return 1
    fi

    echo ""

    # Step 3: 选择权限处理模式
    local mode="diagnostic"
    echo "请选择权限处理模式："
    select_option "" \
        "诊断模式 - 仅分析权限问题并给出建议" \
        "交互模式 - 可辅助执行授权操作（需要 RAM 权限）"

    case $? in
        0) mode="diagnostic" ;;
        1) mode="interactive" ;;
    esac

    echo ""

    # Step 4: 选择默认区域
    local regions=("cn-hangzhou" "cn-shanghai" "cn-beijing" "cn-shenzhen" "cn-hongkong" "其他")
    local selected_region="cn-hangzhou"

    echo "请选择默认区域："
    select_option "" "${regions[@]}"
    local region_idx=$?

    if (( region_idx < ${#regions[@]} - 1 )); then
        selected_region="${regions[$region_idx]}"
    else
        read -p "请输入区域 ID (如 ap-southeast-1): " selected_region
    fi

    echo ""

    # Step 5: 生成配置文件
    mkdir -p "$ALIYUN_PLUGIN_DIR"

    cat > "$CONFIG_FILE" << EOF
# Aliyun Skill 配置文件
# 自动生成于 $(date '+%Y-%m-%d %H:%M:%S')
# 可手动编辑此文件调整配置

# 权限处理模式: diagnostic | interactive
mode: $mode

# 凭证来源: cli_profile | env
credential_source: $credential_source

# 使用的 profile（仅 credential_source=cli_profile 时有效）
profile: $selected_profile

# 默认区域
default_region: $selected_region

# 输出格式: auto | table | json
output: auto

# 资源操作权限配置
resources:
  ecs: readonly        # 只读：list, status, describe
  ack: readonly        # 只读
  acr: readonly        # 只读
  rds: readonly        # 只读
  oss: confirm         # 写操作需确认
  dns: direct          # 直接操作
  slb: direct          # 直接操作
  ai: confirm          # 开通需确认
EOF

    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│                    ✅ 配置完成！                         │"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
    echo "配置已保存到: $CONFIG_FILE"
    echo ""
    echo "当前配置："
    echo "  凭证来源: $credential_source ($selected_profile)"
    echo "  处理模式: $mode"
    echo "  默认区域: $selected_region"
    echo ""
    echo "使用方法："
    echo "  /aliyun ecs list       # 列出 ECS 实例"
    echo "  /aliyun oss ls bucket/ # 列出 OSS 文件"
    echo "  /aliyun config         # 重新配置"
    echo ""
}

# 加载配置
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        export ALIYUN_MODE=$(yq -r '.mode // "diagnostic"' "$CONFIG_FILE")
        export ALIYUN_CREDENTIAL_SOURCE=$(yq -r '.credential_source // "env"' "$CONFIG_FILE")
        export ALIYUN_PROFILE=$(yq -r '.profile // "default"' "$CONFIG_FILE")
        export ALIYUN_DEFAULT_REGION=$(yq -r '.default_region // "cn-hangzhou"' "$CONFIG_FILE")
        export ALIYUN_OUTPUT=$(yq -r '.output // "auto"' "$CONFIG_FILE")
        return 0
    fi
    return 1
}

# 获取资源权限配置
get_resource_permission() {
    local resource="$1"
    if [[ -f "$CONFIG_FILE" ]]; then
        yq -r ".resources.$resource // \"readonly\"" "$CONFIG_FILE"
    else
        echo "readonly"
    fi
}

# 如果直接运行此脚本，执行初始化
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_init
fi
```

**Step 2: 提交**

```bash
chmod +x plugins/aliyun/init.sh
git add plugins/aliyun/init.sh
git commit -m "feat: 添加首次引导模块 init.sh"
```

---

## Task 4: 输出格式化模块 output.sh

**Files:**
- Create: `plugins/aliyun/output.sh`

**Step 1: 创建 output.sh**

```bash
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
```

**Step 2: 提交**

```bash
git add plugins/aliyun/output.sh
git commit -m "feat: 添加输出格式化模块 output.sh"
```

---

## Task 5: ECS CLI 脚本

**Files:**
- Create: `plugins/aliyun/cli/ecs.sh`

**Step 1: 创建 ecs.sh**

```bash
#!/bin/bash
# ecs.sh - ECS 云服务器操作
# 使用方法: source ecs.sh && ecs_list

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../auth.sh"
source "$SCRIPT_DIR/../output.sh"
source "$SCRIPT_DIR/../init.sh"

# 获取区域
get_region() {
    echo "${ALIBABA_CLOUD_REGION_ID:-$ALIYUN_DEFAULT_REGION}"
}

# 列出所有实例
ecs_list() {
    local region=$(get_region)
    local filter="$1"
    local limit="${2:-100}"
    local format="${3:-auto}"

    print_title "📦 ECS 实例列表"

    local result=$(aliyun ecs DescribeInstances \
        --RegionId "$region" \
        --PageSize "$limit" \
        2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "查询失败: $result"
        return 1
    fi

    local instances=$(echo "$result" | jq '.Instances.Instance')
    local count=$(echo "$instances" | jq 'length')

    if (( count == 0 )); then
        print_info "当前区域 ($region) 没有 ECS 实例"
        return 0
    fi

    # 根据数量选择输出格式
    if [[ "$format" == "json" ]]; then
        echo "$instances" | jq '.'
    elif (( count <= 3 )); then
        # 详细卡片视图
        echo "$instances" | jq -r '.[] | "
┌─ \(.InstanceId) ─────────────────────────────
│ 名称: \(.InstanceName)
│ 状态: \(.Status)
│ 规格: \(.InstanceType)
│ IP:   \(.VpcAttributes.PrivateIpAddress.IpAddress[0] // "N/A") (私) / \(.PublicIpAddress.IpAddress[0] // "N/A") (公)
│ 区域: \(.ZoneId)
│ 创建: \(.CreationTime)
└─────────────────────────────────────────────
"'
    else
        # 表格视图
        echo ""
        printf "%-22s %-20s %-10s %-15s\n" "实例ID" "名称" "状态" "私网IP"
        print_separator "─" 70
        echo "$instances" | jq -r '.[] | "\(.InstanceId)\t\(.InstanceName)\t\(.Status)\t\(.VpcAttributes.PrivateIpAddress.IpAddress[0] // "N/A")"' | \
            while IFS=$'\t' read -r id name status ip; do
                printf "%-22s %-20s %-10s %-15s\n" "$id" "${name:0:18}" "$status" "$ip"
            done
        echo ""
        print_info "共 $count 台实例 (区域: $region)"
    fi
}

# 查看实例状态
ecs_status() {
    local instance_id="$1"
    local region=$(get_region)

    if [[ -z "$instance_id" ]]; then
        print_error "请指定实例 ID"
        echo "用法: /aliyun ecs status <instance-id>"
        return 1
    fi

    print_title "📊 ECS 实例状态: $instance_id"

    local result=$(aliyun ecs DescribeInstances \
        --RegionId "$region" \
        --InstanceIds "['\"$instance_id\"']" \
        2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "查询失败: $result"
        return 1
    fi

    local instance=$(echo "$result" | jq '.Instances.Instance[0]')

    if [[ "$instance" == "null" ]]; then
        print_error "实例不存在: $instance_id"
        return 1
    fi

    echo "$instance" | jq -r '"
实例 ID:    \(.InstanceId)
实例名称:   \(.InstanceName)
状态:       \(.Status)
实例规格:   \(.InstanceType)
vCPU:       \(.Cpu) 核
内存:       \(.Memory) MB
操作系统:   \(.OSName)
私网 IP:    \(.VpcAttributes.PrivateIpAddress.IpAddress[0] // "N/A")
公网 IP:    \(.PublicIpAddress.IpAddress[0] // "N/A")
安全组:     \(.SecurityGroupIds.SecurityGroupId[0] // "N/A")
VPC:        \(.VpcAttributes.VpcId // "N/A")
可用区:     \(.ZoneId)
创建时间:   \(.CreationTime)
到期时间:   \(.ExpiredTime // "N/A")
"'
}

# 查看实例监控
ecs_monitor() {
    local instance_id="$1"
    local region=$(get_region)

    if [[ -z "$instance_id" ]]; then
        print_error "请指定实例 ID"
        return 1
    fi

    print_title "📈 ECS 实例监控: $instance_id"

    local result=$(aliyun ecs DescribeInstanceMonitorData \
        --RegionId "$region" \
        --InstanceId "$instance_id" \
        --StartTime "$(date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ')" \
        --EndTime "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "查询失败: $result"
        return 1
    fi

    echo "$result" | jq '.MonitorData.InstanceMonitorData[-1] // empty' | jq -r '
if . then "
CPU 使用率:     \(.CPU)%
内网入流量:     \(.IntranetRX) bytes
内网出流量:     \(.IntranetTX) bytes
公网入流量:     \(.InternetRX) bytes
公网出流量:     \(.InternetTX) bytes
系统盘读 IOPS:  \(.IOPSRead)
系统盘写 IOPS:  \(.IOPSWrite)
时间:           \(.TimeStamp)
" else "暂无监控数据" end'
}

# 主入口
ecs_main() {
    local action="$1"
    shift

    load_config
    load_credentials "$ALIYUN_PROFILE"

    if [[ "$CREDENTIAL_STATUS" != "authorized" ]]; then
        print_error "凭证无效或未配置，请运行 /aliyun config"
        return 1
    fi

    case "$action" in
        list|ls)
            ecs_list "$@" ;;
        status|show|describe)
            ecs_status "$@" ;;
        monitor|mon)
            ecs_monitor "$@" ;;
        *)
            echo "ECS 命令用法:"
            echo "  /aliyun ecs list              # 列出所有实例"
            echo "  /aliyun ecs status <id>       # 查看实例状态"
            echo "  /aliyun ecs monitor <id>      # 查看实例监控"
            ;;
    esac
}

# 如果直接运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ecs_main "$@"
fi
```

**Step 2: 提交**

```bash
chmod +x plugins/aliyun/cli/ecs.sh
git add plugins/aliyun/cli/ecs.sh
git commit -m "feat: 添加 ECS CLI 脚本"
```

---

## Task 6: OSS CLI 脚本

**Files:**
- Create: `plugins/aliyun/cli/oss.sh`

**Step 1: 创建 oss.sh**

```bash
#!/bin/bash
# oss.sh - OSS 对象存储操作
# 使用方法: source oss.sh && oss_list

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../auth.sh"
source "$SCRIPT_DIR/../output.sh"
source "$SCRIPT_DIR/../init.sh"

# 获取区域
get_region() {
    echo "${ALIBABA_CLOUD_REGION_ID:-$ALIYUN_DEFAULT_REGION}"
}

# 列出 Buckets
oss_list_buckets() {
    local format="${1:-auto}"

    print_title "📦 OSS Bucket 列表"

    local result=$(aliyun oss ls 2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "查询失败: $result"
        return 1
    fi

    echo "$result"
}

# 列出文件
oss_ls() {
    local path="$1"
    local limit="${2:-100}"

    if [[ -z "$path" ]]; then
        oss_list_buckets
        return
    fi

    # 确保路径格式正确
    if [[ ! "$path" =~ ^oss:// ]]; then
        path="oss://$path"
    fi

    print_title "📁 OSS 文件列表: $path"

    local result=$(aliyun oss ls "$path" --limited-num "$limit" 2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "查询失败: $result"
        return 1
    fi

    echo "$result"
}

# 上传文件（需确认）
oss_cp() {
    local src="$1"
    local dst="$2"

    if [[ -z "$src" || -z "$dst" ]]; then
        print_error "请指定源文件和目标路径"
        echo "用法: /aliyun oss cp <local-file> <oss://bucket/path>"
        return 1
    fi

    # 检查权限配置
    local permission=$(get_resource_permission "oss")

    if [[ "$permission" == "readonly" ]]; then
        print_error "OSS 写操作被禁止"
        echo "如需启用，请修改 ~/.claude/plugins/aliyun/config.yaml"
        return 1
    fi

    # 确保目标路径格式正确
    if [[ ! "$dst" =~ ^oss:// ]]; then
        dst="oss://$dst"
    fi

    # 需要确认
    if [[ "$permission" == "confirm" ]]; then
        print_action_box "上传文件" "$dst" "源: $src"
        read -p "" -n 1 -r
        echo ""

        case "$REPLY" in
            y|Y)
                ;;
            d|D)
                echo "源文件: $src"
                ls -la "$src" 2>/dev/null || echo "文件不存在"
                return 0
                ;;
            *)
                print_info "操作已取消"
                return 0
                ;;
        esac
    fi

    print_info "上传中..."
    local result=$(aliyun oss cp "$src" "$dst" 2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "上传失败: $result"
        return 1
    fi

    print_success "上传完成: $dst"
}

# 删除文件（需确认）
oss_rm() {
    local path="$1"

    if [[ -z "$path" ]]; then
        print_error "请指定要删除的文件路径"
        echo "用法: /aliyun oss rm <oss://bucket/path>"
        return 1
    fi

    # 检查权限配置
    local permission=$(get_resource_permission "oss")

    if [[ "$permission" == "readonly" ]]; then
        print_error "OSS 写操作被禁止"
        return 1
    fi

    # 确保路径格式正确
    if [[ ! "$path" =~ ^oss:// ]]; then
        path="oss://$path"
    fi

    # 需要确认
    if [[ "$permission" == "confirm" ]]; then
        print_action_box "删除文件" "$path" ""
        read -p "" -n 1 -r
        echo ""

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "操作已取消"
            return 0
        fi
    fi

    print_info "删除中..."
    local result=$(aliyun oss rm "$path" 2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "删除失败: $result"
        return 1
    fi

    print_success "删除完成: $path"
}

# 下载文件
oss_download() {
    local src="$1"
    local dst="$2"

    if [[ -z "$src" ]]; then
        print_error "请指定 OSS 文件路径"
        echo "用法: /aliyun oss download <oss://bucket/path> [local-path]"
        return 1
    fi

    # 确保源路径格式正确
    if [[ ! "$src" =~ ^oss:// ]]; then
        src="oss://$src"
    fi

    # 默认下载到当前目录
    if [[ -z "$dst" ]]; then
        dst="."
    fi

    print_info "下载中..."
    local result=$(aliyun oss cp "$src" "$dst" 2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "下载失败: $result"
        return 1
    fi

    print_success "下载完成: $dst"
}

# 主入口
oss_main() {
    local action="$1"
    shift

    load_config
    load_credentials "$ALIYUN_PROFILE"

    if [[ "$CREDENTIAL_STATUS" != "authorized" ]]; then
        print_error "凭证无效或未配置，请运行 /aliyun config"
        return 1
    fi

    case "$action" in
        ls|list)
            oss_ls "$@" ;;
        cp|upload)
            oss_cp "$@" ;;
        rm|delete)
            oss_rm "$@" ;;
        download|get)
            oss_download "$@" ;;
        *)
            echo "OSS 命令用法:"
            echo "  /aliyun oss ls [bucket/path]     # 列出 Bucket 或文件"
            echo "  /aliyun oss cp <src> <dst>       # 上传文件（需确认）"
            echo "  /aliyun oss rm <path>            # 删除文件（需确认）"
            echo "  /aliyun oss download <src> [dst] # 下载文件"
            ;;
    esac
}

# 如果直接运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    oss_main "$@"
fi
```

**Step 2: 提交**

```bash
chmod +x plugins/aliyun/cli/oss.sh
git add plugins/aliyun/cli/oss.sh
git commit -m "feat: 添加 OSS CLI 脚本"
```

---

## Task 7: DNS CLI 脚本

**Files:**
- Create: `plugins/aliyun/cli/dns.sh`

**Step 1: 创建 dns.sh**

```bash
#!/bin/bash
# dns.sh - DNS 域名解析操作
# 使用方法: source dns.sh && dns_list

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../auth.sh"
source "$SCRIPT_DIR/../output.sh"
source "$SCRIPT_DIR/../init.sh"

# 列出域名
dns_list_domains() {
    print_title "🌐 域名列表"

    local result=$(aliyun alidns DescribeDomains 2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "查询失败: $result"
        return 1
    fi

    echo "$result" | jq -r '.Domains.Domain[] | "\(.DomainName)\t\(.RecordCount) 条记录\t\(.DnsServers.DnsServer[0])"' | \
        while IFS=$'\t' read -r name count dns; do
            printf "%-30s %-15s %s\n" "$name" "$count" "$dns"
        done
}

# 列出解析记录
dns_list() {
    local domain="$1"
    local format="${2:-auto}"

    if [[ -z "$domain" ]]; then
        dns_list_domains
        return
    fi

    print_title "📋 DNS 解析记录: $domain"

    local result=$(aliyun alidns DescribeDomainRecords \
        --DomainName "$domain" \
        2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "查询失败: $result"
        return 1
    fi

    local records=$(echo "$result" | jq '.DomainRecords.Record')
    local count=$(echo "$records" | jq 'length')

    if (( count == 0 )); then
        print_info "域名 $domain 没有解析记录"
        return 0
    fi

    echo ""
    printf "%-20s %-8s %-30s %-8s %-10s\n" "主机记录" "类型" "记录值" "TTL" "状态"
    print_separator "─" 80

    echo "$records" | jq -r '.[] | "\(.RR)\t\(.Type)\t\(.Value)\t\(.TTL)\t\(.Status)"' | \
        while IFS=$'\t' read -r rr type value ttl status; do
            local status_text
            if [[ "$status" == "ENABLE" ]]; then
                status_text="${GREEN}启用${NC}"
            else
                status_text="${YELLOW}暂停${NC}"
            fi
            printf "%-20s %-8s %-30s %-8s %b\n" "$rr" "$type" "${value:0:28}" "$ttl" "$status_text"
        done

    echo ""
    print_info "共 $count 条记录"
}

# 添加解析记录
dns_add() {
    local domain="$1"
    local type="$2"
    local rr="$3"
    local value="$4"
    local ttl="${5:-600}"

    if [[ -z "$domain" || -z "$type" || -z "$rr" || -z "$value" ]]; then
        print_error "参数不完整"
        echo "用法: /aliyun dns add <domain> <type> <rr> <value> [ttl]"
        echo "示例: /aliyun dns add example.com A www 1.2.3.4 600"
        return 1
    fi

    print_info "添加解析记录..."

    local result=$(aliyun alidns AddDomainRecord \
        --DomainName "$domain" \
        --Type "$type" \
        --RR "$rr" \
        --Value "$value" \
        --TTL "$ttl" \
        2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "添加失败: $result"
        return 1
    fi

    local record_id=$(echo "$result" | jq -r '.RecordId')
    print_success "解析记录添加成功"
    echo "  域名:   $domain"
    echo "  记录:   $rr.$domain"
    echo "  类型:   $type"
    echo "  值:     $value"
    echo "  TTL:    $ttl"
    echo "  记录ID: $record_id"
}

# 删除解析记录
dns_delete() {
    local record_id="$1"

    if [[ -z "$record_id" ]]; then
        print_error "请指定记录 ID"
        echo "用法: /aliyun dns delete <record-id>"
        echo "提示: 使用 /aliyun dns list <domain> 查看记录 ID"
        return 1
    fi

    print_info "删除解析记录..."

    local result=$(aliyun alidns DeleteDomainRecord \
        --RecordId "$record_id" \
        2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "删除失败: $result"
        return 1
    fi

    print_success "解析记录已删除: $record_id"
}

# 修改解析记录
dns_update() {
    local record_id="$1"
    local type="$2"
    local rr="$3"
    local value="$4"
    local ttl="${5:-600}"

    if [[ -z "$record_id" || -z "$type" || -z "$rr" || -z "$value" ]]; then
        print_error "参数不完整"
        echo "用法: /aliyun dns update <record-id> <type> <rr> <value> [ttl]"
        return 1
    fi

    print_info "修改解析记录..."

    local result=$(aliyun alidns UpdateDomainRecord \
        --RecordId "$record_id" \
        --Type "$type" \
        --RR "$rr" \
        --Value "$value" \
        --TTL "$ttl" \
        2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "修改失败: $result"
        return 1
    fi

    print_success "解析记录已更新: $record_id"
}

# 主入口
dns_main() {
    local action="$1"
    shift

    load_config
    load_credentials "$ALIYUN_PROFILE"

    if [[ "$CREDENTIAL_STATUS" != "authorized" ]]; then
        print_error "凭证无效或未配置，请运行 /aliyun config"
        return 1
    fi

    case "$action" in
        list|ls)
            dns_list "$@" ;;
        add)
            dns_add "$@" ;;
        delete|rm)
            dns_delete "$@" ;;
        update|modify)
            dns_update "$@" ;;
        *)
            echo "DNS 命令用法:"
            echo "  /aliyun dns list [domain]                      # 列出域名或解析记录"
            echo "  /aliyun dns add <domain> <type> <rr> <value>   # 添加解析记录"
            echo "  /aliyun dns delete <record-id>                 # 删除解析记录"
            echo "  /aliyun dns update <record-id> <type> <rr> <value> # 修改解析记录"
            ;;
    esac
}

# 如果直接运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    dns_main "$@"
fi
```

**Step 2: 提交**

```bash
chmod +x plugins/aliyun/cli/dns.sh
git add plugins/aliyun/cli/dns.sh
git commit -m "feat: 添加 DNS CLI 脚本"
```

---

## Task 8: RDS CLI 脚本

**Files:**
- Create: `plugins/aliyun/cli/rds.sh`

**Step 1: 创建 rds.sh**

```bash
#!/bin/bash
# rds.sh - RDS 数据库操作
# 使用方法: source rds.sh && rds_list

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../auth.sh"
source "$SCRIPT_DIR/../output.sh"
source "$SCRIPT_DIR/../init.sh"

get_region() {
    echo "${ALIBABA_CLOUD_REGION_ID:-$ALIYUN_DEFAULT_REGION}"
}

# 列出数据库实例
rds_list() {
    local region=$(get_region)
    local format="${1:-auto}"

    print_title "🗄️  RDS 实例列表"

    local result=$(aliyun rds DescribeDBInstances \
        --RegionId "$region" \
        2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "查询失败: $result"
        return 1
    fi

    local instances=$(echo "$result" | jq '.Items.DBInstance')
    local count=$(echo "$instances" | jq 'length')

    if (( count == 0 )); then
        print_info "当前区域 ($region) 没有 RDS 实例"
        return 0
    fi

    echo ""
    printf "%-22s %-20s %-12s %-10s %-15s\n" "实例ID" "描述" "引擎" "状态" "连接地址"
    print_separator "─" 85

    echo "$instances" | jq -r '.[] | "\(.DBInstanceId)\t\(.DBInstanceDescription // "-")\t\(.Engine)/\(.EngineVersion)\t\(.DBInstanceStatus)\t\(.ConnectionString // "N/A")"' | \
        while IFS=$'\t' read -r id desc engine status conn; do
            printf "%-22s %-20s %-12s %-10s %-15s\n" "$id" "${desc:0:18}" "$engine" "$status" "${conn:0:13}"
        done

    echo ""
    print_info "共 $count 个实例 (区域: $region)"
}

# 查看实例详情
rds_status() {
    local instance_id="$1"
    local region=$(get_region)

    if [[ -z "$instance_id" ]]; then
        print_error "请指定实例 ID"
        echo "用法: /aliyun rds status <instance-id>"
        return 1
    fi

    print_title "📊 RDS 实例详情: $instance_id"

    local result=$(aliyun rds DescribeDBInstanceAttribute \
        --DBInstanceId "$instance_id" \
        2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "查询失败: $result"
        return 1
    fi

    local instance=$(echo "$result" | jq '.Items.DBInstanceAttribute[0]')

    if [[ "$instance" == "null" ]]; then
        print_error "实例不存在: $instance_id"
        return 1
    fi

    echo "$instance" | jq -r '"
实例 ID:      \(.DBInstanceId)
实例描述:     \(.DBInstanceDescription // "-")
状态:         \(.DBInstanceStatus)
引擎:         \(.Engine) \(.EngineVersion)
实例规格:     \(.DBInstanceClass)
存储空间:     \(.DBInstanceStorage) GB
存储类型:     \(.DBInstanceStorageType)
连接地址:     \(.ConnectionString // "N/A")
端口:         \(.Port)
VPC ID:       \(.VpcId // "N/A")
可用区:       \(.ZoneId)
创建时间:     \(.CreationTime)
到期时间:     \(.ExpireTime // "N/A")
付费类型:     \(.PayType)
"'
}

# 主入口
rds_main() {
    local action="$1"
    shift

    load_config
    load_credentials "$ALIYUN_PROFILE"

    if [[ "$CREDENTIAL_STATUS" != "authorized" ]]; then
        print_error "凭证无效或未配置，请运行 /aliyun config"
        return 1
    fi

    case "$action" in
        list|ls)
            rds_list "$@" ;;
        status|show|describe)
            rds_status "$@" ;;
        *)
            echo "RDS 命令用法:"
            echo "  /aliyun rds list          # 列出所有实例"
            echo "  /aliyun rds status <id>   # 查看实例详情"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    rds_main "$@"
fi
```

**Step 2: 提交**

```bash
chmod +x plugins/aliyun/cli/rds.sh
git add plugins/aliyun/cli/rds.sh
git commit -m "feat: 添加 RDS CLI 脚本"
```

---

## Task 9: 权限诊断 SDK 脚本

**Files:**
- Create: `plugins/aliyun/sdk/requirements.txt`
- Create: `plugins/aliyun/sdk/permission_helper.py`

**Step 1: 创建 requirements.txt**

```text
aliyun-python-sdk-core>=2.13.0
aliyun-python-sdk-ram>=3.0.0
aliyun-python-sdk-sts>=3.0.0
```

**Step 2: 创建 permission_helper.py**

```python
#!/usr/bin/env python3
# permission_helper.py - 权限诊断与策略管理

import json
import sys
import os
import re

# 服务权限映射
SERVICE_ACTIONS = {
    "ecs": {
        "read": ["ecs:Describe*", "ecs:List*"],
        "write": ["ecs:*"],
        "system_policy": "AliyunECSReadOnlyAccess"
    },
    "oss": {
        "read": ["oss:Get*", "oss:List*"],
        "write": ["oss:*"],
        "system_policy": "AliyunOSSFullAccess"
    },
    "dns": {
        "read": ["alidns:Describe*", "alidns:List*"],
        "write": ["alidns:*"],
        "system_policy": "AliyunDNSFullAccess"
    },
    "rds": {
        "read": ["rds:Describe*", "rds:List*"],
        "write": ["rds:*"],
        "system_policy": "AliyunRDSReadOnlyAccess"
    },
    "slb": {
        "read": ["slb:Describe*", "slb:List*"],
        "write": ["slb:*"],
        "system_policy": "AliyunSLBFullAccess"
    },
    "acr": {
        "read": ["cr:Get*", "cr:List*"],
        "write": ["cr:*"],
        "system_policy": "AliyunContainerRegistryReadOnlyAccess"
    },
    "ack": {
        "read": ["cs:Describe*", "cs:Get*", "cs:List*"],
        "write": ["cs:*"],
        "system_policy": "AliyunCSReadOnlyAccess"
    },
    "ram": {
        "read": ["ram:Get*", "ram:List*"],
        "write": ["ram:*"],
        "system_policy": "AliyunRAMFullAccess"
    }
}

# 官方文档链接
DOC_URLS = {
    "ecs": "https://help.aliyun.com/document_detail/25497.html",
    "oss": "https://help.aliyun.com/document_detail/31948.html",
    "dns": "https://help.aliyun.com/document_detail/29739.html",
    "rds": "https://help.aliyun.com/document_detail/26300.html",
    "slb": "https://help.aliyun.com/document_detail/27566.html",
    "acr": "https://help.aliyun.com/document_detail/60945.html",
    "ack": "https://help.aliyun.com/document_detail/87401.html",
    "ram": "https://help.aliyun.com/document_detail/28627.html"
}

def diagnose_error(error_code: str, error_msg: str) -> dict:
    """解析错误，返回诊断结果"""
    result = {
        "error_code": error_code,
        "missing_actions": [],
        "service": None,
        "doc_url": None
    }

    # 从错误信息中提取服务和操作
    # 常见格式: "You are not authorized to do action: ecs:DescribeInstances"
    action_match = re.search(r'action:\s*(\w+):(\w+)', error_msg, re.IGNORECASE)
    if action_match:
        service = action_match.group(1).lower()
        action = f"{service}:{action_match.group(2)}"
        result["service"] = service
        result["missing_actions"].append(action)
        result["doc_url"] = DOC_URLS.get(service)

    return result

def suggest_policy(service: str, actions: list = None, access_level: str = "read") -> dict:
    """生成建议的 RAM 策略"""
    if service not in SERVICE_ACTIONS:
        return {"error": f"Unknown service: {service}"}

    service_config = SERVICE_ACTIONS[service]

    if actions is None:
        actions = service_config.get(access_level, service_config["read"])

    policy = {
        "Version": "1",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": actions,
                "Resource": "*"
            }
        ]
    }

    return {
        "policy": policy,
        "system_policy": service_config.get("system_policy"),
        "doc_url": DOC_URLS.get(service)
    }

def get_doc_url(service: str) -> str:
    """获取服务文档链接"""
    return DOC_URLS.get(service, "https://help.aliyun.com/")

def main():
    if len(sys.argv) < 2:
        print("Usage: permission_helper.py <command> [args]")
        print("Commands:")
        print("  diagnose <error_code> <error_msg>  - Diagnose permission error")
        print("  suggest <service> [access_level]   - Suggest RAM policy")
        print("  doc <service>                      - Get documentation URL")
        sys.exit(1)

    command = sys.argv[1]

    if command == "diagnose":
        if len(sys.argv) < 4:
            print("Usage: permission_helper.py diagnose <error_code> <error_msg>")
            sys.exit(1)
        result = diagnose_error(sys.argv[2], sys.argv[3])
        print(json.dumps(result, indent=2, ensure_ascii=False))

    elif command == "suggest":
        if len(sys.argv) < 3:
            print("Usage: permission_helper.py suggest <service> [access_level]")
            sys.exit(1)
        service = sys.argv[2]
        access_level = sys.argv[3] if len(sys.argv) > 3 else "read"
        result = suggest_policy(service, access_level=access_level)
        print(json.dumps(result, indent=2, ensure_ascii=False))

    elif command == "doc":
        if len(sys.argv) < 3:
            print("Usage: permission_helper.py doc <service>")
            sys.exit(1)
        print(get_doc_url(sys.argv[2]))

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main()
```

**Step 3: 提交**

```bash
chmod +x plugins/aliyun/sdk/permission_helper.py
git add plugins/aliyun/sdk/
git commit -m "feat: 添加权限诊断 SDK 脚本"
```

---

## Task 10: 主 Skill 文件

**Files:**
- Create: `commands/aliyun.md`

**Step 1: 创建 aliyun.md**

```markdown
# /aliyun - 阿里云资源管理

智能阿里云资源管理工具，支持 ECS、OSS、DNS、RDS 等服务的查询和操作。

## 参数说明

```
/aliyun [资源类型] [操作] [参数...] [选项]

资源类型:
  ecs     ECS 云服务器
  oss     对象存储
  dns     云解析 DNS
  rds     云数据库
  slb     负载均衡
  acr     容器镜像服务
  ack     容器服务 K8s
  ai      AI 服务
  config  配置管理
  diag    权限诊断

通用选项:
  --region <id>     指定区域
  --profile <name>  指定凭证 profile
  --json            输出 JSON 格式
  --table           输出表格格式
  --help            显示帮助
```

## 执行流程

### Step 1: 初始化检查

首先检查是否需要首次配置：

```bash
PLUGIN_DIR="$HOME/.claude/plugins/aliyun"
CONFIG_FILE="$PLUGIN_DIR/config.yaml"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[INFO] 首次使用，启动配置引导..."
    "$PLUGIN_DIR/init.sh"
    exit 0
fi
```

### Step 2: 加载凭证

```bash
source "$PLUGIN_DIR/auth.sh"
source "$PLUGIN_DIR/init.sh"

load_config
load_credentials "$ALIYUN_PROFILE"

if [[ "$CREDENTIAL_STATUS" != "authorized" ]]; then
    echo "[ERROR] 凭证无效或未配置"
    echo "[INFO] 运行 /aliyun config 重新配置"
    exit 1
fi
```

### Step 3: 解析命令并执行

```bash
# 解析参数
RESOURCE="$1"
shift

case "$RESOURCE" in
    ecs)
        source "$PLUGIN_DIR/cli/ecs.sh"
        ecs_main "$@"
        ;;
    oss)
        source "$PLUGIN_DIR/cli/oss.sh"
        oss_main "$@"
        ;;
    dns)
        source "$PLUGIN_DIR/cli/dns.sh"
        dns_main "$@"
        ;;
    rds)
        source "$PLUGIN_DIR/cli/rds.sh"
        rds_main "$@"
        ;;
    config)
        "$PLUGIN_DIR/init.sh"
        ;;
    diag)
        # 诊断当前凭证权限
        echo "当前凭证信息："
        aliyun sts GetCallerIdentity
        ;;
    --help|-h|help|"")
        show_help
        ;;
    *)
        echo "[ERROR] 未知资源类型: $RESOURCE"
        echo "[INFO] 运行 /aliyun --help 查看帮助"
        ;;
esac
```

## 使用示例

```bash
# 配置
/aliyun config              # 首次配置或重新配置

# ECS
/aliyun ecs list            # 列出所有 ECS 实例
/aliyun ecs status i-bp1xxx # 查看实例状态

# OSS
/aliyun oss ls              # 列出所有 Bucket
/aliyun oss ls my-bucket/   # 列出文件
/aliyun oss cp file.txt oss://bucket/path/  # 上传（需确认）

# DNS
/aliyun dns list            # 列出所有域名
/aliyun dns list example.com # 列出解析记录
/aliyun dns add example.com A www 1.2.3.4   # 添加记录

# RDS
/aliyun rds list            # 列出数据库实例
/aliyun rds status rm-bp1xxx # 查看实例详情

# 诊断
/aliyun diag                # 诊断当前权限
```

## 权限说明

| 资源 | 读操作 | 写操作 |
|-----|-------|-------|
| ECS | ✅ 自动 | ❌ 禁止 |
| RDS | ✅ 自动 | ❌ 禁止 |
| OSS | ✅ 自动 | ⚠️ 需确认 |
| DNS | ✅ 自动 | ✅ 直接 |
| SLB | ✅ 自动 | ✅ 直接 |

权限可在 `~/.claude/plugins/aliyun/config.yaml` 中调整。

## 智能提示

当对话中提到以下内容时，我会主动提示 /aliyun 命令：

- ECS 实例 ID (i-bp*)
- OSS 路径 (oss://*)
- RDS 实例 ID (rm-bp*)
- 域名解析相关操作
- 云资源查询需求
```

**Step 2: 提交**

```bash
git add commands/aliyun.md
git commit -m "feat: 添加主 skill 文件 aliyun.md"
```

---

## Task 11: 补充 CLI 脚本 (ACK/ACR/SLB/AI)

**Files:**
- Create: `plugins/aliyun/cli/ack.sh`
- Create: `plugins/aliyun/cli/acr.sh`
- Create: `plugins/aliyun/cli/slb.sh`
- Create: `plugins/aliyun/cli/ai.sh`

这些脚本结构与 ecs.sh/rds.sh 类似，主要是只读查询功能。为保持计划简洁，此处省略详细代码，实现时参考 ecs.sh 模板。

**Step 1: 创建脚本骨架并提交**

```bash
# 创建基础脚本
for service in ack acr slb ai; do
    cat > "plugins/aliyun/cli/${service}.sh" << 'EOF'
#!/bin/bash
# ${service}.sh - 待实现
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../auth.sh"
source "$SCRIPT_DIR/../output.sh"
source "$SCRIPT_DIR/../init.sh"

echo "TODO: ${service} 功能待实现"
EOF
    chmod +x "plugins/aliyun/cli/${service}.sh"
done

git add plugins/aliyun/cli/
git commit -m "feat: 添加 ACK/ACR/SLB/AI CLI 脚本骨架"
```

---

## Task 12: README 和文档

**Files:**
- Create: `README.md`
- Create: `LICENSE`

**Step 1: 创建 README.md**

```markdown
# aliyun-skill

Claude Code 的阿里云资源管理 Skill。

## 功能特性

- 🖥️ **ECS** - 云服务器实例查询、状态监控
- 📦 **OSS** - 对象存储文件管理（上传/下载/删除）
- 🌐 **DNS** - 域名解析记录管理
- 🗄️ **RDS** - 数据库实例状态查询
- 🔒 **智能权限控制** - 读写操作分离，敏感操作需确认
- 🔍 **权限诊断** - 自动分析权限问题并给出建议

## 安装

### 前置依赖

- [aliyun CLI](https://help.aliyun.com/document_detail/139508.html) - 阿里云命令行工具
- [jq](https://stedolan.github.io/jq/) - JSON 处理工具
- [yq](https://github.com/mikefarah/yq) - YAML 处理工具

macOS 安装：
```bash
brew install aliyun-cli jq yq
```

### 安装 Skill

```bash
git clone https://github.com/your-username/aliyun-skill.git
cd aliyun-skill
./install.sh
```

### 配置凭证

支持三种凭证配置方式（按优先级）：

1. **项目级配置** - 在项目根目录创建 `.aliyun.yaml`
   ```yaml
   profile: my-project
   region: cn-hangzhou
   ```

2. **aliyun CLI 配置**
   ```bash
   aliyun configure
   ```

3. **环境变量**
   ```bash
   export ALIBABA_CLOUD_ACCESS_KEY_ID="your-access-key-id"
   export ALIBABA_CLOUD_ACCESS_KEY_SECRET="your-access-key-secret"
   ```

## 使用方法

### 首次配置

```bash
/aliyun config
```

### 常用命令

```bash
# ECS
/aliyun ecs list              # 列出所有实例
/aliyun ecs status i-bp1xxx   # 查看实例状态

# OSS
/aliyun oss ls                # 列出 Bucket
/aliyun oss ls my-bucket/     # 列出文件
/aliyun oss cp file.txt oss://bucket/path/  # 上传文件

# DNS
/aliyun dns list              # 列出域名
/aliyun dns list example.com  # 列出解析记录
/aliyun dns add example.com A www 1.2.3.4  # 添加记录

# RDS
/aliyun rds list              # 列出数据库实例
/aliyun rds status rm-bp1xxx  # 查看实例详情
```

### 权限配置

默认权限配置：

| 资源 | 读操作 | 写操作 |
|-----|-------|-------|
| ECS | ✅ 自动执行 | ❌ 禁止 |
| RDS | ✅ 自动执行 | ❌ 禁止 |
| OSS | ✅ 自动执行 | ⚠️ 需确认 |
| DNS | ✅ 自动执行 | ✅ 直接执行 |

可在 `~/.claude/plugins/aliyun/config.yaml` 中修改。

## 卸载

```bash
./uninstall.sh
```

## 许可证

MIT License
```

**Step 2: 创建 LICENSE**

```text
MIT License

Copyright (c) 2025

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**Step 3: 提交**

```bash
git add README.md LICENSE
git commit -m "docs: 添加 README 和 LICENSE"
```

---

## 验收清单

- [ ] install.sh 可正常安装到 ~/.claude/
- [ ] uninstall.sh 可正常卸载
- [ ] /aliyun config 首次引导正常
- [ ] /aliyun ecs list 可列出实例
- [ ] /aliyun oss ls 可列出 Bucket
- [ ] /aliyun dns list 可列出域名
- [ ] /aliyun rds list 可列出数据库
- [ ] OSS 写操作有确认提示
- [ ] 权限错误有诊断信息
