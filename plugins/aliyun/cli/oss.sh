#!/bin/bash
# oss.sh - OSS 对象存储操作
# 使用方法: source oss.sh && oss_list

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../auth.sh"
source "$SCRIPT_DIR/../output.sh"
source "$SCRIPT_DIR/../init.sh"

# 获取区域
get_region() {
    echo "${ALIBABA_CLOUD_REGION_ID:-${ALIYUN_DEFAULT_REGION:-cn-hangzhou}}"
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
