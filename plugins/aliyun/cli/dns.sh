#!/bin/bash
# dns.sh - DNS 域名解析操作
# 使用方法: source dns.sh && dns_list

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="${SCRIPT_DIR}/.."

# 仅在未加载时加载依赖
[[ -z "$ALIYUN_PLUGIN_DIR" ]] && source "$PLUGIN_DIR/auth.sh"
[[ -z "$(type -t print_title)" ]] && source "$PLUGIN_DIR/output.sh"
[[ -z "$(type -t load_config)" ]] && source "$PLUGIN_DIR/init.sh"

# 列出域名
dns_list_domains() {
    print_title "🌐 域名列表"

    local result=$(aliyun alidns DescribeDomains 2>&1)

    if echo "$result" | grep -q "Error"; then
        print_error "查询失败: $result"
        return 1
    fi

    local domains=$(echo "$result" | jq '.Domains.Domain')
    local count=$(echo "$domains" | jq 'length')

    if (( count == 0 )); then
        print_info "没有找到域名"
        return 0
    fi

    echo ""
    printf "%-30s %-15s %s\n" "域名" "记录数" "DNS服务器"
    print_separator "─" 70

    echo "$domains" | jq -r '.[] | "\(.DomainName)\t\(.RecordCount) 条记录\t\(.DnsServers.DnsServer[0] // "N/A")"' | \
        while IFS=$'\t' read -r name count dns; do
            printf "%-30s %-15s %s\n" "$name" "$count" "$dns"
        done

    echo ""
    print_info "共 $count 个域名"
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
    printf "%-25s %-20s %-8s %-30s %-8s %-10s\n" "记录ID" "主机记录" "类型" "记录值" "TTL" "状态"
    print_separator "─" 110

    echo "$records" | jq -r '.[] | "\(.RecordId)\t\(.RR)\t\(.Type)\t\(.Value)\t\(.TTL)\t\(.Status)"' | \
        while IFS=$'\t' read -r id rr type value ttl status; do
            local status_text
            if [[ "$status" == "ENABLE" ]]; then
                status_text="${GREEN}启用${NC}"
            else
                status_text="${YELLOW}暂停${NC}"
            fi
            printf "%-25s %-20s %-8s %-30s %-8s %b\n" "$id" "$rr" "$type" "${value:0:28}" "$ttl" "$status_text"
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
