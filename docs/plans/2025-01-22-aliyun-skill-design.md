# Aliyun Skill 设计文档

> 创建日期: 2025-01-22

## 概述

为 Claude Code 创建阿里云资源管理 Skill，支持查询和操作阿里云资源，具备智能权限控制和诊断能力。

## 需求总结

| 维度 | 选择 |
|-----|------|
| 资源权限 | ECS/ACK/ACR/RDS 只读，OSS/AI 写需确认，DNS/SLB 直接处理 |
| 凭证管理 | 项目配置 → CLI 配置 → 环境变量（三级降级） |
| 技术实现 | CLI 优先 + SDK 备选 |
| 触发方式 | `/aliyun` 命令 + 对话智能提示 |
| 权限处理 | 首次引导选模式，无 Key 用诊断模式，有 Key 用交互引导 |
| 输出格式 | 上下文感知自动调整 |

## 项目结构

```
aliyun-skill/
├── README.md                         # 项目说明、安装指南
├── LICENSE                           # 开源协议
├── install.sh                        # 一键安装脚本
├── uninstall.sh                      # 卸载脚本
│
├── docs/                             # 设计文档
│   └── plans/
│       └── 2025-01-22-aliyun-skill-design.md
│
├── commands/                         # skill 文件
│   └── aliyun.md                     # 主 skill
│
└── plugins/aliyun/                   # 插件文件
    ├── init.sh                       # 首次配置引导
    ├── auth.sh                       # 凭证检测与加载
    ├── output.sh                     # 输出格式化
    ├── cli/                          # CLI 封装脚本
    │   ├── ecs.sh
    │   ├── oss.sh
    │   ├── dns.sh
    │   ├── acr.sh
    │   ├── ack.sh
    │   ├── rds.sh
    │   ├── slb.sh
    │   └── ai.sh
    └── sdk/                          # SDK 脚本
        ├── requirements.txt
        └── permission_helper.py
```

## 凭证管理流程

```
┌─────────────────────────────────────────────────────────┐
│                    凭证加载优先级                         │
├─────────────────────────────────────────────────────────┤
│  1. 项目级 .aliyun.yaml (当前目录)                        │
│     └─ profile: my-project                              │
│                                                         │
│  2. aliyun CLI 配置 ~/.aliyun/config.json               │
│     └─ 读取指定 profile 或 default                       │
│                                                         │
│  3. 环境变量                                             │
│     └─ ALIBABA_CLOUD_ACCESS_KEY_ID                      │
│     └─ ALIBABA_CLOUD_ACCESS_KEY_SECRET                  │
│     └─ ALIBABA_CLOUD_REGION_ID (可选)                    │
└─────────────────────────────────────────────────────────┘
```

凭证状态返回值：
- `authorized` - 凭证有效
- `invalid` - 凭证无效或过期
- `missing` - 未找到凭证

## 首次引导流程

当用户第一次使用 `/aliyun` 且 `config.yaml` 不存在时触发：

1. 检测凭证状态（项目配置、CLI 配置、环境变量）
2. 选择默认 profile
3. 选择权限处理模式（诊断模式 / 交互模式）
4. 选择默认区域

生成配置文件 `~/.claude/plugins/aliyun/config.yaml`：

```yaml
# 自动生成
mode: interactive      # diagnostic | interactive
credential_source: cli_profile
profile: default
default_region: cn-hangzhou
output: auto

resources:
  ecs: readonly        # 只读
  ack: readonly
  acr: readonly
  rds: readonly
  oss: confirm         # 写操作需确认
  dns: direct          # 直接操作
  slb: direct
  ai: confirm
```

## 资源操作权限控制

| 资源类型 | 读操作 | 写操作 | 示例命令 |
|---------|-------|-------|---------|
| ECS | 自动执行 | 禁止 | 查实例、查状态 |
| ACK | 自动执行 | 禁止 | 查集群、查节点 |
| ACR | 自动执行 | 禁止 | 查镜像、查仓库 |
| RDS | 自动执行 | 禁止 | 查实例、查状态 |
| OSS | 自动执行 | 需确认 | 上传、删除、复制 |
| DNS | 自动执行 | 直接执行 | 添加、修改记录 |
| SLB | 自动执行 | 直接执行 | 配置、修改规则 |
| AI 服务 | 自动执行 | 需确认 | 开通服务 |

## 权限问题诊断

### 诊断模式（无 Key 或用户选择）

显示：
- 错误码和当前身份
- 需要的权限列表
- 建议的 RAM 策略 JSON
- 官方文档链接

### 交互模式（已授权 Key + 有 RAM 权限）

提供选项：
1. 创建新策略并附加到用户
2. 附加现有系统策略
3. 仅显示策略 JSON
4. 取消

## 输出格式

| 数据量 | 格式 |
|-------|------|
| ≤ 3 条 | 详细卡片视图 |
| 4-20 条 | 简洁表格视图 |
| > 20 条 | 摘要 + 分页提示 |

可通过 `--json` 或 `--table` 强制指定格式。

## 命令语法

```
/aliyun [资源类型] [操作] [参数...] [选项]

资源类型:
  ecs     ECS 云服务器
  oss     对象存储
  dns     云解析 DNS
  slb     负载均衡
  acr     容器镜像服务
  ack     容器服务 K8s
  rds     云数据库
  ai      AI 服务

通用选项:
  --region <id>     指定区域
  --profile <name>  指定凭证 profile
  --json            输出 JSON 格式
  --table           输出表格格式
  --filter <expr>   筛选条件
  --limit <n>       限制返回数量
  --help            显示帮助
```

### 常用命令示例

```bash
# ECS
/aliyun ecs list
/aliyun ecs status i-bp1xxx
/aliyun ecs list --filter 'tag:env=prod'

# OSS
/aliyun oss ls my-bucket/logs/
/aliyun oss cp local.txt oss://bucket/path/
/aliyun oss rm oss://bucket/old.txt

# DNS
/aliyun dns list example.com
/aliyun dns add example.com A www 1.2.3.4

# RDS
/aliyun rds list
/aliyun rds status rm-bp1xxx

# AI
/aliyun ai list
/aliyun ai enable dashscope

# 诊断
/aliyun diag
/aliyun config
```

## 智能提示

当对话中检测到以下关键词时，主动提示可用命令：

**资源关键词**：
- ECS、云服务器、实例、i-bp*
- OSS、对象存储、Bucket、oss://*
- DNS、域名解析、A记录、CNAME
- RDS、数据库、MySQL、rm-bp*
- ACK、K8s、集群、容器服务
- ACR、镜像仓库、registry
- SLB、负载均衡、lb-bp*

**动作关键词**：
- 查看、查询、列出、状态
- 上传、下载、删除、复制
- 添加、修改、配置
- 开通、启用

## 技术实现

### CLI 封装脚本

各资源类型对应的 `cli/*.sh` 脚本封装 aliyun CLI 命令：

```bash
# cli/ecs.sh 示例
ecs_list() {
    aliyun ecs DescribeInstances \
        --RegionId "$REGION" \
        --output cols=InstanceId,InstanceName,Status,PublicIpAddress
}

ecs_status() {
    local instance_id="$1"
    aliyun ecs DescribeInstanceStatus \
        --RegionId "$REGION" \
        --InstanceId.1 "$instance_id"
}
```

### SDK 脚本

`sdk/permission_helper.py` 处理复杂的权限诊断：

```python
class PermissionHelper:
    def diagnose_error(self, error_code, error_msg):
        """解析错误，返回缺少的权限列表"""

    def suggest_policy(self, actions):
        """根据所需 action 生成最小权限策略"""

    def check_ram_permission(self):
        """检查当前凭证是否有 RAM 管理权限"""

    def attach_policy(self, user, policy):
        """附加策略到用户（交互模式）"""

    def get_doc_url(self, service, action):
        """返回对应操作的官方文档链接"""
```

## 安装方式

```bash
git clone https://github.com/xxx/aliyun-skill.git
cd aliyun-skill
./install.sh
```

install.sh 将：
1. 检查依赖（aliyun CLI、jq、yq）
2. 复制 commands/aliyun.md 到 ~/.claude/commands/
3. 复制 plugins/aliyun/ 到 ~/.claude/plugins/
4. 设置脚本执行权限
