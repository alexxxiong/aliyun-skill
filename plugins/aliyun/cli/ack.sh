#!/bin/bash
# ack.sh - ACK 容器服务 K8s 操作
# 使用方法: source ack.sh && ack_list

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../auth.sh"
source "$SCRIPT_DIR/../output.sh"
source "$SCRIPT_DIR/../init.sh"

get_region() {
    echo "${ALIBABA_CLOUD_REGION_ID:-${ALIYUN_DEFAULT_REGION:-cn-hangzhou}}"
}

# 列出集群
ack_list() {
    local region=$(get_region)

    print_title "☸️  ACK 集群列表"

    local result=$(aliyun cs DescribeClustersV1 \
        --region "$region" \
        2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "查询失败: $result"
        return 1
    fi

    local clusters=$(echo "$result" | jq '.clusters // []')
    local count=$(echo "$clusters" | jq 'length')

    if (( count == 0 )); then
        print_info "当前区域 ($region) 没有 ACK 集群"
        return 0
    fi

    echo ""
    printf "%-36s %-20s %-15s %-10s\n" "集群ID" "名称" "版本" "状态"
    print_separator "─" 85

    echo "$clusters" | jq -r '.[] | "\(.cluster_id)\t\(.name)\t\(.current_version // "N/A")\t\(.state)"' | \
        while IFS=$'\t' read -r id name version state; do
            printf "%-36s %-20s %-15s %-10s\n" "$id" "${name:0:18}" "$version" "$state"
        done

    echo ""
    print_info "共 $count 个集群 (区域: $region)"
}

# 查看集群详情
ack_status() {
    local cluster_id="$1"

    if [[ -z "$cluster_id" ]]; then
        print_error "请指定集群 ID"
        echo "用法: /aliyun ack status <cluster-id>"
        return 1
    fi

    print_title "📊 ACK 集群详情: $cluster_id"

    local result=$(aliyun cs DescribeClusterDetail \
        --ClusterId "$cluster_id" \
        2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "查询失败: $result"
        return 1
    fi

    echo "$result" | jq -r '"
集群 ID:      \(.cluster_id)
集群名称:     \(.name)
状态:         \(.state)
K8s 版本:     \(.current_version // "N/A")
集群类型:     \(.cluster_type)
节点数:       \(.size)
VPC ID:       \(.vpc_id)
区域:         \(.region_id)
创建时间:     \(.created)
"'
}

# 主入口
ack_main() {
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
            ack_list "$@" ;;
        status|show|describe)
            ack_status "$@" ;;
        *)
            echo "ACK 命令用法:"
            echo "  /aliyun ack list          # 列出所有集群"
            echo "  /aliyun ack status <id>   # 查看集群详情"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ack_main "$@"
fi
