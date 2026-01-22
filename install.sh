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
