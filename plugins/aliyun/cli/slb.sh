#!/bin/bash
# slb.sh - SLB 负载均衡操作
# 使用方法: source slb.sh && slb_list

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../auth.sh"
source "$SCRIPT_DIR/../output.sh"
source "$SCRIPT_DIR/../init.sh"

get_region() {
    echo "${ALIBABA_CLOUD_REGION_ID:-${ALIYUN_DEFAULT_REGION:-cn-hangzhou}}"
}

# 列出负载均衡实例
slb_list() {
    local region=$(get_region)

    print_title "⚖️  SLB 负载均衡列表"

    local result=$(aliyun slb DescribeLoadBalancers \
        --RegionId "$region" \
        2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "查询失败: $result"
        return 1
    fi

    local instances=$(echo "$result" | jq '.LoadBalancers.LoadBalancer // []')
    local count=$(echo "$instances" | jq 'length')

    if (( count == 0 )); then
        print_info "当前区域 ($region) 没有 SLB 实例"
        return 0
    fi

    echo ""
    printf "%-20s %-20s %-15s %-15s %-10s\n" "实例ID" "名称" "地址" "类型" "状态"
    print_separator "─" 85

    echo "$instances" | jq -r '.[] | "\(.LoadBalancerId)\t\(.LoadBalancerName // "-")\t\(.Address)\t\(.AddressType)\t\(.LoadBalancerStatus)"' | \
        while IFS=$'\t' read -r id name addr type status; do
            printf "%-20s %-20s %-15s %-15s %-10s\n" "$id" "${name:0:18}" "$addr" "$type" "$status"
        done

    echo ""
    print_info "共 $count 个实例 (区域: $region)"
}

# 查看实例详情
slb_status() {
    local lb_id="$1"
    local region=$(get_region)

    if [[ -z "$lb_id" ]]; then
        print_error "请指定实例 ID"
        echo "用法: /aliyun slb status <lb-id>"
        return 1
    fi

    print_title "📊 SLB 实例详情: $lb_id"

    local result=$(aliyun slb DescribeLoadBalancerAttribute \
        --LoadBalancerId "$lb_id" \
        --RegionId "$region" \
        2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "查询失败: $result"
        return 1
    fi

    echo "$result" | jq -r '"
实例 ID:      \(.LoadBalancerId)
实例名称:     \(.LoadBalancerName // "-")
状态:         \(.LoadBalancerStatus)
地址:         \(.Address)
地址类型:     \(.AddressType)
VPC ID:       \(.VpcId // "N/A")
网络类型:     \(.NetworkType)
带宽:         \(.Bandwidth) Mbps
创建时间:     \(.CreateTime)
"'
}

# 主入口
slb_main() {
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
            slb_list "$@" ;;
        status|show|describe)
            slb_status "$@" ;;
        *)
            echo "SLB 命令用法:"
            echo "  /aliyun slb list          # 列出所有实例"
            echo "  /aliyun slb status <id>   # 查看实例详情"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    slb_main "$@"
fi
