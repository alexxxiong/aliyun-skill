#!/bin/bash
# ai.sh - AI 服务操作
# 使用方法: source ai.sh && ai_list

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../auth.sh"
source "$SCRIPT_DIR/../output.sh"
source "$SCRIPT_DIR/../init.sh"

# 列出 AI 服务状态
ai_list() {
    print_title "🤖 阿里云 AI 服务"

    echo ""
    echo "支持的 AI 服务："
    echo ""
    echo "  通义千问 (Qwen)"
    echo "    - 模型服务: DashScope"
    echo "    - API: https://dashscope.aliyuncs.com"
    echo ""
    echo "  百炼 (Bailian)"
    echo "    - 模型开发平台"
    echo "    - 控制台: https://bailian.console.aliyun.com"
    echo ""
    echo "  PAI (机器学习平台)"
    echo "    - 模型训练和部署"
    echo "    - 控制台: https://pai.console.aliyun.com"
    echo ""

    print_info "AI 服务需要单独开通，请访问阿里云控制台"
}

# 查看 DashScope 配额
ai_quota() {
    print_title "📊 DashScope API 配额"

    # 检查是否配置了 DashScope API Key
    if [[ -z "$DASHSCOPE_API_KEY" ]]; then
        print_warning "未配置 DASHSCOPE_API_KEY 环境变量"
        echo ""
        echo "配置方法："
        echo "  export DASHSCOPE_API_KEY='your-api-key'"
        echo ""
        echo "获取 API Key："
        echo "  https://dashscope.console.aliyun.com/apiKey"
        return 1
    fi

    print_info "DashScope API Key 已配置"
    echo ""
    echo "使用示例："
    echo "  curl https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation \\"
    echo "    -H 'Authorization: Bearer \$DASHSCOPE_API_KEY' \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"model\": \"qwen-turbo\", \"input\": {\"prompt\": \"Hello\"}}'"
}

# 主入口
ai_main() {
    local action="$1"
    shift

    load_config
    load_credentials "$ALIYUN_PROFILE"

    case "$action" in
        list|ls|"")
            ai_list "$@" ;;
        quota)
            ai_quota "$@" ;;
        *)
            echo "AI 命令用法:"
            echo "  /aliyun ai list      # 列出 AI 服务"
            echo "  /aliyun ai quota     # 查看 DashScope 配额"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ai_main "$@"
fi
