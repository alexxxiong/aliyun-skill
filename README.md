# aliyun-skill

Claude Code 的阿里云资源管理 Skill。

## 功能特性

- **ECS** - 云服务器实例查询、状态监控
- **OSS** - 对象存储文件管理（上传/下载/删除）
- **DNS** - 域名解析记录管理
- **RDS** - 数据库实例状态查询
- **ACK** - 容器服务 K8s 集群管理
- **ACR** - 容器镜像服务仓库查询
- **SLB** - 负载均衡实例管理
- **AI** - AI 服务（通义千问/百炼）信息
- **智能权限控制** - 读写操作分离，敏感操作需确认
- **权限诊断** - 自动分析权限问题并给出建议

## 安装

### 前置依赖

- [aliyun CLI](https://help.aliyun.com/document_detail/139508.html) - 阿里云命令行工具
- [jq](https://stedolan.github.io/jq/) - JSON 处理工具
- [yq](https://github.com/mikefarah/yq) - YAML 处理工具

macOS 安装：
```bash
brew install aliyun-cli jq yq
```

### 安装 Skill

```bash
git clone https://github.com/your-username/aliyun-skill.git
cd aliyun-skill
./install.sh
```

### 配置凭证

支持三种凭证配置方式（按优先级）：

1. **项目级配置** - 在项目根目录创建 `.aliyun.yaml`
   ```yaml
   profile: my-project
   region: cn-hangzhou
   ```

2. **aliyun CLI 配置**
   ```bash
   aliyun configure
   ```

3. **环境变量**
   ```bash
   export ALIBABA_CLOUD_ACCESS_KEY_ID="your-access-key-id"
   export ALIBABA_CLOUD_ACCESS_KEY_SECRET="your-access-key-secret"
   ```

## 使用方法

### 首次配置

```bash
/aliyun config
```

### 常用命令

```bash
# ECS
/aliyun ecs list              # 列出所有实例
/aliyun ecs status i-bp1xxx   # 查看实例状态
/aliyun ecs monitor i-bp1xxx  # 查看实例监控

# OSS
/aliyun oss ls                # 列出 Bucket
/aliyun oss ls my-bucket/     # 列出文件
/aliyun oss cp file.txt oss://bucket/path/  # 上传文件
/aliyun oss download oss://bucket/file.txt  # 下载文件

# DNS
/aliyun dns list              # 列出域名
/aliyun dns list example.com  # 列出解析记录
/aliyun dns add example.com A www 1.2.3.4  # 添加记录
/aliyun dns delete <record-id>  # 删除记录

# RDS
/aliyun rds list              # 列出数据库实例
/aliyun rds status rm-bp1xxx  # 查看实例详情

# ACK
/aliyun ack list              # 列出 K8s 集群
/aliyun ack status <cluster-id>  # 查看集群详情

# ACR
/aliyun acr list              # 列出命名空间
/aliyun acr list <namespace>  # 列出仓库

# SLB
/aliyun slb list              # 列出负载均衡实例
/aliyun slb status <lb-id>    # 查看实例详情

# AI
/aliyun ai list               # 列出 AI 服务
/aliyun ai quota              # 查看 DashScope 配额

# 诊断
/aliyun diag                  # 诊断当前凭证权限
```

### 权限配置

默认权限配置：

| 资源 | 读操作 | 写操作 |
|-----|-------|-------|
| ECS | ✅ 自动执行 | ❌ 禁止 |
| RDS | ✅ 自动执行 | ❌ 禁止 |
| ACK | ✅ 自动执行 | ❌ 禁止 |
| ACR | ✅ 自动执行 | ❌ 禁止 |
| OSS | ✅ 自动执行 | ⚠️ 需确认 |
| DNS | ✅ 自动执行 | ✅ 直接执行 |
| SLB | ✅ 自动执行 | ✅ 直接执行 |
| AI  | ✅ 自动执行 | ⚠️ 需确认 |

可在 `~/.claude/plugins/aliyun/config.yaml` 中修改权限配置：

```yaml
resources:
  ecs: readonly        # readonly | confirm | direct
  oss: confirm
  dns: direct
```

## 目录结构

```
aliyun-skill/
├── install.sh              # 安装脚本
├── uninstall.sh            # 卸载脚本
├── commands/
│   └── aliyun.md           # Skill 主文件
└── plugins/
    └── aliyun/
        ├── auth.sh         # 凭证管理
        ├── init.sh         # 首次引导
        ├── output.sh       # 输出格式化
        ├── cli/            # CLI 脚本
        │   ├── ecs.sh
        │   ├── oss.sh
        │   ├── dns.sh
        │   ├── rds.sh
        │   ├── ack.sh
        │   ├── acr.sh
        │   ├── slb.sh
        │   └── ai.sh
        └── sdk/            # Python SDK 脚本
            ├── requirements.txt
            └── permission_helper.py
```

## 卸载

```bash
./uninstall.sh
```

## 许可证

MIT License
