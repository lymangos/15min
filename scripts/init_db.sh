#!/bin/bash
# ============================================
# 数据库初始化脚本
# ============================================

set -e

# 配置
DB_NAME="${DB_NAME:-life_circle_15min}"
DB_USER="${DB_USER:-postgres}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"

echo "================================================"
echo "15分钟生活圈 - 数据库初始化"
echo "================================================"

# 创建数据库
echo "[1/4] 创建数据库..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${DB_NAME};" 2>/dev/null || true
sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME};"

# 安装扩展
echo "[2/4] 安装 PostGIS 和 pgRouting 扩展..."
sudo -u postgres psql -d ${DB_NAME} -c "CREATE EXTENSION IF NOT EXISTS postgis;"
sudo -u postgres psql -d ${DB_NAME} -c "CREATE EXTENSION IF NOT EXISTS pgrouting;"
sudo -u postgres psql -d ${DB_NAME} -c "CREATE EXTENSION IF NOT EXISTS hstore;"

# 运行迁移脚本
echo "[3/4] 运行数据库迁移..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MIGRATIONS_DIR="${SCRIPT_DIR}/../migrations"

for sql_file in ${MIGRATIONS_DIR}/*.sql; do
    if [ -f "$sql_file" ]; then
        echo "  - 执行: $(basename $sql_file)"
        sudo -u postgres psql -d ${DB_NAME} -f "$sql_file"
    fi
done

# 验证安装
echo "[4/4] 验证安装..."
sudo -u postgres psql -d ${DB_NAME} -c "
SELECT 
    'PostGIS' AS extension, 
    PostGIS_Version() AS version
UNION ALL
SELECT 
    'pgRouting', 
    pgr_version()::text;
"

echo ""
echo "================================================"
echo "✅ 数据库初始化完成！"
echo "================================================"
echo ""
echo "下一步："
echo "1. 下载 OSM 数据并使用 osm2pgrouting 导入路网"
echo "2. 使用 osm2pgsql 导入 POI 数据"
echo "3. 运行 migrations/003_import_osm_poi.sql 提取 POI"
echo ""
