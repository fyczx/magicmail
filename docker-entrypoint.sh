#!/bin/sh
set -e

# ============================================================================
# Magicmail 容器入口脚本
# 以 root 进入 → 修正数据目录归属 → su-exec 降权运行
# 兼容 Dockhand / Unraid 等 NAS 管理器（支持 PUID/PGID 环境变量）
# ============================================================================

PUID=${PUID:-1000}
PGID=${PGID:-1000}

# 确保数据目录存在（bind mount 可能覆盖，需要重建）
mkdir -p /app/data

# 以 root 身份修正 bind-mount 数据目录的归属
# 非 root 进入时会静默跳过（chown 无权限）
if [ "$(id -u)" = "0" ]; then
    echo "[entrypoint] Setting /app/data ownership to ${PUID}:${PGID}"
    chown -R "${PUID}:${PGID}" /app/data 2>/dev/null || true
fi

# 降权运行业务进程
echo "[entrypoint] Starting Magicmail as uid=${PUID} gid=${PGID}"
exec su-exec "${PUID}:${PGID}" /app/magicmail "$@"
