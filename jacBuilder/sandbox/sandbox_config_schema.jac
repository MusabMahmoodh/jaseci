"""Sandbox Configuration Schema

This file defines the configuration schema for the sandbox module.
The schema is used by jac-scale's config_loader to validate sandbox configuration.
"""

# Sandbox configuration schema (moved from jac-scale plugin_config.jac)
# This schema defines all valid sandbox configuration options

SANDBOX_CONFIG_SCHEMA = {
    "sandbox": {
        "type": "dict",
        "default": {},
        "description": "Sandbox configuration for ephemeral isolated preview environments",
        "nested": {
            "enabled": {
                "type": "bool",
                "default": False,
                "description": "Enable sandbox system for preview environments"
            },
            "type": {
                "type": "string",
                "default": "local",
                "description": "Sandbox provider type: 'kubernetes', 'docker', or 'local'"
            },
            "namespace": {
                "type": "string",
                "default": "jac-sandboxes",
                "description": "K8s namespace for sandbox pods"
            },
            "max_per_user": {
                "type": "int",
                "default": 3,
                "description": "Maximum concurrent sandboxes per user"
            },
            "ttl_seconds": {
                "type": "int",
                "default": 3600,
                "description": "Sandbox time-to-live in seconds before auto-cleanup"
            },
            "cpu_limit": {
                "type": "string",
                "default": "500m",
                "description": "CPU limit per sandbox (K8s format)"
            },
            "memory_limit": {
                "type": "string",
                "default": "512Mi",
                "description": "Memory limit per sandbox (K8s format)"
            },
            "base_image": {
                "type": "string",
                "default": "python:3.12-slim",
                "description": "Base Docker image for sandbox containers"
            },
            "storage_limit": {
                "type": "string",
                "default": "256Mi",
                "description": "Scratch storage limit per sandbox"
            },
            "domain_template": {
                "type": "string",
                "default": "{sandbox_id}.preview.example.com",
                "description": "URL template for sandbox preview routing"
            },
            "security_context": {
                "type": "bool",
                "default": True,
                "description": "Enable security context (non-root, read-only FS)"
            },
            "network_isolation": {
                "type": "bool",
                "default": True,
                "description": "Enable network isolation between sandboxes"
            },
            "ingress_class": {
                "type": "string",
                "default": "nginx",
                "description": "K8s Ingress class (nginx, alb, traefik)"
            },
            "tls_enabled": {
                "type": "bool",
                "default": False,
                "description": "Enable TLS via cert-manager"
            },
            "tls_issuer": {
                "type": "string",
                "default": "letsencrypt-prod",
                "description": "cert-manager ClusterIssuer name"
            },
            # Warm pool settings
            "warm_pool_size": {
                "type": "int",
                "default": 0,
                "description": "Number of warm pods to maintain"
            },
            "warm_pool_idle_timeout": {
                "type": "int",
                "default": 300,
                "description": "Seconds before idle warm pod is recycled"
            },
            # Dependency cache settings
            "dependency_cache_url": {
                "type": "string",
                "default": "",
                "description": "S3/MinIO URL for dependency cache archives"
            },
            "dependency_cache_timeout": {
                "type": "int",
                "default": 30,
                "description": "Seconds before cache fetch times out"
            },
            # Restart policy settings
            "restart_policy": {
                "type": "string",
                "default": "OnFailure",
                "description": "Pod restart policy: Always, OnFailure, Never"
            },
            "max_restarts": {
                "type": "int",
                "default": 5,
                "description": "Mark as failed after N restarts"
            },
            "grace_period_seconds": {
                "type": "int",
                "default": 30,
                "description": "Grace period for graceful shutdown (seconds)"
            },
            # Deploy-specific settings
            "max_per_user_deploy": {
                "type": "int",
                "default": 5,
                "description": "Maximum concurrent deploy sandboxes per user"
            }
        }
    }
};
