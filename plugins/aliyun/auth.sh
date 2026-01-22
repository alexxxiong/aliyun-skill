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
