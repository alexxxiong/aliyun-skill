#!/bin/bash
# init.sh - 首次配置引导
# 使用方法: ./init.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 仅在未加载时加载依赖
[[ -z "$ALIYUN_PLUGIN_DIR" ]] && source "$SCRIPT_DIR/auth.sh"

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
