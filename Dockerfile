# ============================================================================
# Magicmail Docker 镜像
# 多阶段构建: 前端(Vue+Vite) → Go后端(Embed) → 最终运行镜像
# ============================================================================

# ---- Stage 1: 构建前端 ----
FROM node:20-alpine AS frontend-builder

WORKDIR /app/web

COPY web/package.json web/pnpm-lock.yaml* ./
RUN corepack enable pnpm && pnpm install --frozen-lockfile || npm install

COPY web/ .
RUN npm run build

# ---- Stage 2: 构建 Go 二进制（嵌入前端产物） ----
FROM golang:1.25-alpine AS backend-builder

WORKDIR /app/server

# CGO 编译 SQLite 需要 C 编译器
RUN apk add --no-cache gcc musl-dev

# 先复制依赖文件，利用 Docker 缓存
COPY server/go.mod server/go.sum ./
RUN go mod download

# 复制源码和前端产物
COPY server/ .

# 从前端阶段复制构建产物到 embed 路径
COPY --from=frontend-builder /app/server/dist ./embedfs/dist

# 编译（CGO_ENABLED=0 纯静态链接，支持 SQLite 需要 CGO）
RUN CGO_ENABLED=1 go build -ldflags="-s -w -X main.isProduction=true" -o /magicmail .

# ---- Stage 3: 最终运行镜像 ----
FROM alpine:3.20

# 安装运行时依赖（SQLite 需要 libc 和 ca-certificates）
RUN apk add --no-cache ca-certificates tzdata

# 设置时区（可通过环境变量覆盖）
ENV TZ=Asia/Shanghai

# 创建非 root 用户（固定 UID=1000，与宿主机普通用户匹配）
RUN addgroup -S -g 1000 magicmail && \
    adduser -S -u 1000 -G magicmail -h /app/data -s /sbin/nologin magicmail

WORKDIR /app

# 从构建阶段复制二进制
COPY --from=backend-builder /magicmail /app/magicmail

# 数据持久化目录
RUN mkdir -p /app/data && chown magicmail:magicmail /app/data

USER magicmail

# 数据库路径、监听端口
ENV MAGICMAIL_DSN=/app/data/magicmail.db

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/ || exit 1

ENTRYPOINT ["/app/magicmail"]
