# /aliyun - 阿里云资源管理

智能阿里云资源管理工具，支持 ECS、OSS、DNS、RDS 等服务的查询和操作。

## 参数说明

```
/aliyun [资源类型] [操作] [参数...] [选项]

资源类型:
  ecs     ECS 云服务器
  oss     对象存储
  dns     云解析 DNS
  rds     云数据库
  slb     负载均衡
  acr     容器镜像服务
  ack     容器服务 K8s
  ai      AI 服务
  config  配置管理
  diag    权限诊断

通用选项:
  --region <id>     指定区域
  --profile <name>  指定凭证 profile
  --json            输出 JSON 格式
  --table           输出表格格式
  --help            显示帮助
```

## 执行流程

### Step 1: 初始化检查

首先检查是否需要首次配置：

```bash
PLUGIN_DIR="$HOME/.claude/plugins/aliyun"
CONFIG_FILE="$PLUGIN_DIR/config.yaml"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[INFO] 首次使用，启动配置引导..."
    "$PLUGIN_DIR/init.sh"
    exit 0
fi
```

### Step 2: 加载凭证

```bash
source "$PLUGIN_DIR/auth.sh"
source "$PLUGIN_DIR/init.sh"

load_config
load_credentials "$ALIYUN_PROFILE"

if [[ "$CREDENTIAL_STATUS" != "authorized" ]]; then
    echo "[ERROR] 凭证无效或未配置"
    echo "[INFO] 运行 /aliyun config 重新配置"
    exit 1
fi
```

### Step 3: 解析命令并执行

```bash
# 解析参数
RESOURCE="$1"
shift

case "$RESOURCE" in
    ecs)
        source "$PLUGIN_DIR/cli/ecs.sh"
        ecs_main "$@"
        ;;
    oss)
        source "$PLUGIN_DIR/cli/oss.sh"
        oss_main "$@"
        ;;
    dns)
        source "$PLUGIN_DIR/cli/dns.sh"
        dns_main "$@"
        ;;
    rds)
        source "$PLUGIN_DIR/cli/rds.sh"
        rds_main "$@"
        ;;
    config)
        "$PLUGIN_DIR/init.sh"
        ;;
    diag)
        # 诊断当前凭证权限
        echo "当前凭证信息："
        aliyun sts GetCallerIdentity
        ;;
    --help|-h|help|"")
        show_help
        ;;
    *)
        echo "[ERROR] 未知资源类型: $RESOURCE"
        echo "[INFO] 运行 /aliyun --help 查看帮助"
        ;;
esac
```

## 使用示例

```bash
# 配置
/aliyun config              # 首次配置或重新配置

# ECS
/aliyun ecs list            # 列出所有 ECS 实例
/aliyun ecs status i-bp1xxx # 查看实例状态

# OSS
/aliyun oss ls              # 列出所有 Bucket
/aliyun oss ls my-bucket/   # 列出文件
/aliyun oss cp file.txt oss://bucket/path/  # 上传（需确认）

# DNS
/aliyun dns list            # 列出所有域名
/aliyun dns list example.com # 列出解析记录
/aliyun dns add example.com A www 1.2.3.4   # 添加记录

# RDS
/aliyun rds list            # 列出数据库实例
/aliyun rds status rm-bp1xxx # 查看实例详情

# 诊断
/aliyun diag                # 诊断当前权限
```

## 权限说明

| 资源 | 读操作 | 写操作 |
|-----|-------|-------|
| ECS | ✅ 自动 | ❌ 禁止 |
| RDS | ✅ 自动 | ❌ 禁止 |
| OSS | ✅ 自动 | ⚠️ 需确认 |
| DNS | ✅ 自动 | ✅ 直接 |
| SLB | ✅ 自动 | ✅ 直接 |

权限可在 `~/.claude/plugins/aliyun/config.yaml` 中调整。

## 智能提示

当对话中提到以下内容时，我会主动提示 /aliyun 命令：

- ECS 实例 ID (i-bp*)
- OSS 路径 (oss://*)
- RDS 实例 ID (rm-bp*)
- 域名解析相关操作
- 云资源查询需求
