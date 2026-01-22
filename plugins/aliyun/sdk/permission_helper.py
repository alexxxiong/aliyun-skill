#!/usr/bin/env python3
# permission_helper.py - 权限诊断与策略管理

import json
import sys
import os
import re

# 服务权限映射
SERVICE_ACTIONS = {
    "ecs": {
        "read": ["ecs:Describe*", "ecs:List*"],
        "write": ["ecs:*"],
        "system_policy": "AliyunECSReadOnlyAccess"
    },
    "oss": {
        "read": ["oss:Get*", "oss:List*"],
        "write": ["oss:*"],
        "system_policy": "AliyunOSSFullAccess"
    },
    "dns": {
        "read": ["alidns:Describe*", "alidns:List*"],
        "write": ["alidns:*"],
        "system_policy": "AliyunDNSFullAccess"
    },
    "rds": {
        "read": ["rds:Describe*", "rds:List*"],
        "write": ["rds:*"],
        "system_policy": "AliyunRDSReadOnlyAccess"
    },
    "slb": {
        "read": ["slb:Describe*", "slb:List*"],
        "write": ["slb:*"],
        "system_policy": "AliyunSLBFullAccess"
    },
    "acr": {
        "read": ["cr:Get*", "cr:List*"],
        "write": ["cr:*"],
        "system_policy": "AliyunContainerRegistryReadOnlyAccess"
    },
    "ack": {
        "read": ["cs:Describe*", "cs:Get*", "cs:List*"],
        "write": ["cs:*"],
        "system_policy": "AliyunCSReadOnlyAccess"
    },
    "ram": {
        "read": ["ram:Get*", "ram:List*"],
        "write": ["ram:*"],
        "system_policy": "AliyunRAMFullAccess"
    }
}

# 官方文档链接
DOC_URLS = {
    "ecs": "https://help.aliyun.com/document_detail/25497.html",
    "oss": "https://help.aliyun.com/document_detail/31948.html",
    "dns": "https://help.aliyun.com/document_detail/29739.html",
    "rds": "https://help.aliyun.com/document_detail/26300.html",
    "slb": "https://help.aliyun.com/document_detail/27566.html",
    "acr": "https://help.aliyun.com/document_detail/60945.html",
    "ack": "https://help.aliyun.com/document_detail/87401.html",
    "ram": "https://help.aliyun.com/document_detail/28627.html"
}

def diagnose_error(error_code: str, error_msg: str) -> dict:
    """解析错误，返回诊断结果"""
    result = {
        "error_code": error_code,
        "missing_actions": [],
        "service": None,
        "doc_url": None
    }

    # 从错误信息中提取服务和操作
    # 常见格式: "You are not authorized to do action: ecs:DescribeInstances"
    action_match = re.search(r'action:\s*(\w+):(\w+)', error_msg, re.IGNORECASE)
    if action_match:
        service = action_match.group(1).lower()
        action = f"{service}:{action_match.group(2)}"
        result["service"] = service
        result["missing_actions"].append(action)
        result["doc_url"] = DOC_URLS.get(service)

    return result

def suggest_policy(service: str, actions: list = None, access_level: str = "read") -> dict:
    """生成建议的 RAM 策略"""
    if service not in SERVICE_ACTIONS:
        return {"error": f"Unknown service: {service}"}

    service_config = SERVICE_ACTIONS[service]

    if actions is None:
        actions = service_config.get(access_level, service_config["read"])

    policy = {
        "Version": "1",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": actions,
                "Resource": "*"
            }
        ]
    }

    return {
        "policy": policy,
        "system_policy": service_config.get("system_policy"),
        "doc_url": DOC_URLS.get(service)
    }

def get_doc_url(service: str) -> str:
    """获取服务文档链接"""
    return DOC_URLS.get(service, "https://help.aliyun.com/")

def main():
    if len(sys.argv) < 2:
        print("Usage: permission_helper.py <command> [args]")
        print("Commands:")
        print("  diagnose <error_code> <error_msg>  - Diagnose permission error")
        print("  suggest <service> [access_level]   - Suggest RAM policy")
        print("  doc <service>                      - Get documentation URL")
        sys.exit(1)

    command = sys.argv[1]

    if command == "diagnose":
        if len(sys.argv) < 4:
            print("Usage: permission_helper.py diagnose <error_code> <error_msg>")
            sys.exit(1)
        result = diagnose_error(sys.argv[2], sys.argv[3])
        print(json.dumps(result, indent=2, ensure_ascii=False))

    elif command == "suggest":
        if len(sys.argv) < 3:
            print("Usage: permission_helper.py suggest <service> [access_level]")
            sys.exit(1)
        service = sys.argv[2]
        access_level = sys.argv[3] if len(sys.argv) > 3 else "read"
        result = suggest_policy(service, access_level=access_level)
        print(json.dumps(result, indent=2, ensure_ascii=False))

    elif command == "doc":
        if len(sys.argv) < 3:
            print("Usage: permission_helper.py doc <service>")
            sys.exit(1)
        print(get_doc_url(sys.argv[2]))

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main()
