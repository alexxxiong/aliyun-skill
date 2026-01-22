#!/bin/bash
set -e

CLAUDE_DIR="$HOME/.claude"

echo "======================================"
echo "  Aliyun Skill 卸载程序"
echo "======================================"
echo ""

read -p "确定要卸载 aliyun-skill 吗？(y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "卸载已取消"
    exit 0
fi

echo "🗑️  删除文件..."

# 删除 skill 文件
rm -f "$CLAUDE_DIR/commands/aliyun.md" && echo "   ✓ commands/aliyun.md"

# 删除插件目录
rm -rf "$CLAUDE_DIR/plugins/aliyun" && echo "   ✓ plugins/aliyun/"

echo ""
echo "✅ 卸载完成！"
echo ""
echo "注意：配置文件 ~/.claude/plugins/aliyun/config.yaml 已删除"
echo "      如需保留配置，请在卸载前备份"
