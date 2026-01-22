#!/bin/bash
# ecs.sh - ECS 云服务器操作
# 使用方法: source ecs.sh && ecs_list

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="${SCRIPT_DIR}/.."

# 仅在未加载时加载依赖
[[ -z "$ALIYUN_PLUGIN_DIR" ]] && source "$PLUGIN_DIR/auth.sh"
[[ -z "$(type -t print_title)" ]] && source "$PLUGIN_DIR/output.sh"
[[ -z "$(type -t load_config)" ]] && source "$PLUGIN_DIR/init.sh"

# 获取区域
get_region() {
    echo "${ALIBABA_CLOUD_REGION_ID:-${ALIYUN_DEFAULT_REGION:-cn-hangzhou}}"
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
        --InstanceIds "[\"$instance_id\"]" \
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

    # 计算时间范围 (最近1小时)
    local end_time=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local start_time=$(date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%SZ')

    local result=$(aliyun ecs DescribeInstanceMonitorData \
        --RegionId "$region" \
        --InstanceId "$instance_id" \
        --StartTime "$start_time" \
        --EndTime "$end_time" \
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

    if [[ "$CREDENTIAL_STATUS" == "missing" || "$CREDENTIAL_STATUS" == "invalid" ]]; then
        print_error "凭证无效或未配置，请运行 /aliyun config"
        return 1
    fi

    if [[ "$CREDENTIAL_STATUS" == "cli_not_configured" ]]; then
        print_warning "aliyun CLI 未配置，请先运行: aliyun configure"
        print_info "配置时使用以下信息："
        echo "  Access Key ID: $ALIBABA_CLOUD_ACCESS_KEY_ID"
        echo "  Region: ${ALIBABA_CLOUD_REGION_ID:-cn-hangzhou}"
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
