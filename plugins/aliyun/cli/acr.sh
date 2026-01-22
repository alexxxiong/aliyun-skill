#!/bin/bash
# acr.sh - ACR 容器镜像服务操作
# 使用方法: source acr.sh && acr_list

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="${SCRIPT_DIR}/.."

# 仅在未加载时加载依赖
[[ -z "$ALIYUN_PLUGIN_DIR" ]] && source "$PLUGIN_DIR/auth.sh"
[[ -z "$(type -t print_title)" ]] && source "$PLUGIN_DIR/output.sh"
[[ -z "$(type -t load_config)" ]] && source "$PLUGIN_DIR/init.sh"

get_region() {
    echo "${ALIBABA_CLOUD_REGION_ID:-${ALIYUN_DEFAULT_REGION:-cn-hangzhou}}"
}

# 列出命名空间
acr_list_namespaces() {
    local region=$(get_region)

    print_title "📦 ACR 命名空间列表"

    local result=$(aliyun cr GetNamespaceList \
        --RegionId "$region" \
        2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "查询失败: $result"
        return 1
    fi

    local namespaces=$(echo "$result" | jq '.data.namespaces // []')
    local count=$(echo "$namespaces" | jq 'length')

    if (( count == 0 )); then
        print_info "当前区域 ($region) 没有 ACR 命名空间"
        return 0
    fi

    echo ""
    printf "%-30s %-15s %-20s\n" "命名空间" "状态" "创建时间"
    print_separator "─" 70

    echo "$namespaces" | jq -r '.[] | "\(.namespace)\t\(.namespaceStatus)\t\(.gmtCreate // "N/A")"' | \
        while IFS=$'\t' read -r ns status created; do
            printf "%-30s %-15s %-20s\n" "$ns" "$status" "$created"
        done

    echo ""
    print_info "共 $count 个命名空间 (区域: $region)"
}

# 列出仓库
acr_list_repos() {
    local namespace="$1"
    local region=$(get_region)

    if [[ -z "$namespace" ]]; then
        acr_list_namespaces
        return
    fi

    print_title "📦 ACR 仓库列表: $namespace"

    local result=$(aliyun cr GetRepoList \
        --RegionId "$region" \
        --Namespace "$namespace" \
        2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "查询失败: $result"
        return 1
    fi

    local repos=$(echo "$result" | jq '.data.repos // []')
    local count=$(echo "$repos" | jq 'length')

    if (( count == 0 )); then
        print_info "命名空间 $namespace 没有仓库"
        return 0
    fi

    echo ""
    printf "%-30s %-15s %-20s\n" "仓库名" "类型" "摘要"
    print_separator "─" 70

    echo "$repos" | jq -r '.[] | "\(.repoName)\t\(.repoType)\t\(.summary // "-")"' | \
        while IFS=$'\t' read -r name type summary; do
            printf "%-30s %-15s %-20s\n" "$name" "$type" "${summary:0:18}"
        done

    echo ""
    print_info "共 $count 个仓库"
}

# 主入口
acr_main() {
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
            acr_list_repos "$@" ;;
        namespaces|ns)
            acr_list_namespaces "$@" ;;
        *)
            echo "ACR 命令用法:"
            echo "  /aliyun acr list [namespace]  # 列出命名空间或仓库"
            echo "  /aliyun acr namespaces        # 列出所有命名空间"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    acr_main "$@"
fi
