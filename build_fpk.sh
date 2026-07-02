#!/usr/bin/env bash
# ============================================================================
# Magicmail FPK 打包构建脚本
# 1. 执行 build.sh linux amd64 单平台构建
# 2. 复制产物到 fnapp/app/server/
# 3. 进入 fnapp 目录执行 fnpack build
# ============================================================================

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 项目根目录（脚本所在位置）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SCRIPT_DIR}/bin"
FNAPP_SERVER_DIR="${SCRIPT_DIR}/fnapp/app/server"
FNAPP_DIR="${SCRIPT_DIR}/fnapp"
BINARY_NAME="magicmail"

print_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════╗"
    echo "║     Magicmail FPK 构建工具                ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Step 1: 执行 build.sh 进行单平台构建 (linux amd64)
step1_build() {
    echo -e "${BLUE}▶ [Step 1/3] 执行 build.sh linux amd64 构建...${NC}"
    
    cd "${SCRIPT_DIR}"
    ./build.sh linux amd64
    
    # 检查构建产物是否存在
    if [ ! -f "${BIN_DIR}/${BINARY_NAME}" ]; then
        echo -e "${RED}✗ 构建产物不存在: ${BIN_DIR}/${BINARY_NAME}${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}  ✅ 单平台构建完成${NC}"
}

# Step 2: 复制产物到 fnapp/app/server/
step2_copy() {
    echo -e "${BLUE}▶ [Step 2/3] 复制 ${BINARY_NAME} 到 fnapp/app/server/...${NC}"
    
    mkdir -p "${FNAPP_SERVER_DIR}"
    
    cp -f "${BIN_DIR}/${BINARY_NAME}" "${FNAPP_SERVER_DIR}/magicmail"
    chmod +x "${FNAPP_SERVER_DIR}/magicmail"
    
    local size
    size=$(du -h "${FNAPP_SERVER_DIR}/magicmail" | cut -f1)
    echo -e "${GREEN}  ✅ 已复制: ${FNAPP_SERVER_DIR}/magicmail (${size})${NC}"
}

# Step 3: 进入 fnapp 目录执行 fnpack build
step3_fnpack() {
    echo -e "${BLUE}▶ [Step 3/3] 执行 fnpack build...${NC}"
    
    cd "${FNAPP_DIR}"
    fnpack build
    
    echo -e "${GREEN}  ✅ FPK 打包完成${NC}"
}

# 主入口
main() {
    print_banner
    
    step1_build
    step2_copy
    step3_fnpack
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo -e "  ${GREEN}✅ FPK 构建流程全部完成！${NC}"
    echo -e "  输出文件: ${CYAN}${FNAPP_DIR}/*.fpk${NC}"
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
}

main "$@"
