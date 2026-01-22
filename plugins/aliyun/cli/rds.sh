#!/bin/bash
# rds.sh - RDS 数据库操作
# 使用方法: source rds.sh && rds_list

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../auth.sh"
source "$SCRIPT_DIR/../output.sh"
source "$SCRIPT_DIR/../init.sh"

get_region() {
    echo "${ALIBABA_CLOUD_REGION_ID:-${ALIYUN_DEFAULT_REGION:-cn-hangzhou}}"
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
