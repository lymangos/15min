#!/bin/bash
# ============================================
# 多城市 OSM 数据导入脚本
# 支持一次性导入多个城市到同一数据库
# ============================================

set -e

DATA_DIR="${DATA_DIR:-./data}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 数据库配置
DB_NAME="${DB_NAME:-life_circle_15min}"
DB_USER="${DB_USER:-postgres}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"

echo "================================================"
echo "15分钟生活圈 - 多城市数据导入"
echo "================================================"
echo ""

# 检查数据文件
check_city_data() {
    local city=$1
    local osm_file="$DATA_DIR/${city}.osm"
    
    if [ -f "$osm_file" ]; then
        echo "✅ ${city}: $(du -h "$osm_file" | cut -f1)"
        return 0
    else
        echo "❌ ${city}: 数据文件不存在"
        return 1
    fi
}

echo "检查城市数据文件..."
echo "---"
check_city_data "hangzhou" || true
check_city_data "zhuji" || true
check_city_data "shenyang" || true
echo ""

# 创建步行网络配置
create_pedestrian_config() {
    cat > /tmp/mapconfig_pedestrian.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <tag_name name="highway" id="1">
    <tag_value name="footway"       id="101" priority="1.0" maxspeed="5" />
    <tag_value name="pedestrian"    id="102" priority="1.0" maxspeed="5" />
    <tag_value name="path"          id="103" priority="1.0" maxspeed="5" />
    <tag_value name="steps"         id="104" priority="0.5" maxspeed="3" />
    <tag_value name="residential"   id="105" priority="1.0" maxspeed="5" />
    <tag_value name="living_street" id="106" priority="1.0" maxspeed="5" />
    <tag_value name="service"       id="107" priority="0.8" maxspeed="5" />
    <tag_value name="tertiary"      id="108" priority="0.7" maxspeed="5" />
    <tag_value name="secondary"     id="109" priority="0.5" maxspeed="5" />
    <tag_value name="primary"       id="110" priority="0.3" maxspeed="5" />
    <tag_value name="cycleway"      id="111" priority="0.8" maxspeed="5" />
  </tag_name>
</configuration>
EOF
}

# 导入单个城市
import_city() {
    local city=$1
    local osm_file="$DATA_DIR/${city}.osm"
    
    if [ ! -f "$osm_file" ]; then
        echo "⚠️ 跳过 ${city}: 数据文件不存在"
        return 0
    fi
    
    echo "📦 正在导入 ${city}..."
    
    # 首个城市使用 --clean，后续追加
    local clean_flag=""
    if [ "$2" = "first" ]; then
        clean_flag="--clean"
    fi
    
    # 导入路网
    osm2pgrouting \
        -f "$osm_file" \
        -c /tmp/mapconfig_pedestrian.xml \
        -d "$DB_NAME" \
        -U "$DB_USER" \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        $clean_flag 2>/dev/null || true
    
    # 导入 POI
    if command -v osm2pgsql &> /dev/null; then
        osm2pgsql \
            -d "$DB_NAME" \
            -U "$DB_USER" \
            -H "$DB_HOST" \
            -P "$DB_PORT" \
            --slim \
            -C 2000 \
            -a \
            "$osm_file" 2>/dev/null || true
    fi
    
    echo "✅ ${city} 导入完成"
}

# 主导入流程
echo "开始导入所有城市..."
echo ""

create_pedestrian_config

# 按顺序导入
import_city "hangzhou" "first"
import_city "zhuji"
import_city "shenyang"

echo ""
echo "更新索引和统计..."

# 后处理
PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'EOF'
-- 添加长度列（米）
ALTER TABLE ways ADD COLUMN IF NOT EXISTS length_m DOUBLE PRECISION;
UPDATE ways SET length_m = ST_Length(the_geom::geography) WHERE length_m IS NULL;

-- 添加索引
CREATE INDEX IF NOT EXISTS idx_ways_source ON ways (source);
CREATE INDEX IF NOT EXISTS idx_ways_target ON ways (target);
CREATE INDEX IF NOT EXISTS idx_ways_geom ON ways USING GIST (the_geom);
CREATE INDEX IF NOT EXISTS idx_ways_vertices_geom ON ways_vertices_pgr USING GIST (the_geom);

-- 更新统计信息
ANALYZE ways;
ANALYZE ways_vertices_pgr;
EOF

# 提取 POI
PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "${SCRIPT_DIR}/../migrations/003_import_osm_poi.sql"

echo ""
echo "================================================"
echo "✅ 所有城市导入完成！"
echo "================================================"
echo ""

# 统计信息
echo "路网统计:"
PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT 
    COUNT(*) AS 边数,
    ROUND(SUM(length_m)/1000, 2) AS 总长度_km
FROM ways;
"

echo ""
echo "POI 统计:"
PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT category AS 分类, COUNT(*) AS 数量 
FROM poi 
GROUP BY category 
ORDER BY COUNT(*) DESC;
"
