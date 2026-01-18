#!/bin/bash
# ============================================
# OSM 数据导入脚本
# 使用 osm2pgrouting 导入路网
# ============================================

set -e

# 检查参数
if [ -z "$1" ]; then
    echo "用法: $0 <osm_file.osm.pbf>"
    echo ""
    echo "示例:"
    echo "  $0 ./data/beijing.osm.pbf"
    echo ""
    echo "提示: 可以从 https://download.geofabrik.de/ 下载 OSM 数据"
    exit 1
fi

OSM_FILE="$1"

# 检查文件存在
if [ ! -f "$OSM_FILE" ]; then
    echo "错误: 文件不存在: $OSM_FILE"
    exit 1
fi

# 配置
DB_NAME="${DB_NAME:-life_circle_15min}"
DB_USER="${DB_USER:-postgres}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"

echo "================================================"
echo "15分钟生活圈 - OSM 数据导入"
echo "================================================"
echo "数据文件: $OSM_FILE"
echo "目标数据库: $DB_NAME"
echo ""

# 检查 osm2pgrouting 是否安装
if ! command -v osm2pgrouting &> /dev/null; then
    echo "错误: osm2pgrouting 未安装"
    echo ""
    echo "安装方法:"
    echo "  Ubuntu: sudo apt install osm2pgrouting"
    echo "  或从源码编译: https://github.com/pgRouting/osm2pgrouting"
    exit 1
fi

# 如果是 .pbf 文件，先转换为 .osm
if [[ "$OSM_FILE" == *.pbf ]]; then
    echo "[0/3] 转换 PBF 到 OSM 格式..."
    OSM_XML="${OSM_FILE%.pbf}"
    
    if command -v osmconvert &> /dev/null; then
        osmconvert "$OSM_FILE" -o="$OSM_XML"
    elif command -v osmium &> /dev/null; then
        osmium cat "$OSM_FILE" -o "$OSM_XML"
    else
        echo "警告: 需要 osmconvert 或 osmium 来转换 PBF 文件"
        echo "尝试直接使用 PBF 文件..."
        OSM_XML="$OSM_FILE"
    fi
else
    OSM_XML="$OSM_FILE"
fi

# 导入路网数据
echo "[1/3] 使用 osm2pgrouting 导入路网..."

# 创建配置文件（适用于步行网络）
MAPCONFIG="/tmp/mapconfig_pedestrian.xml"
cat > "$MAPCONFIG" << 'EOF'
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

osm2pgrouting \
    -f "$OSM_XML" \
    -c "$MAPCONFIG" \
    -d "$DB_NAME" \
    -U "$DB_USER" \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    --clean

echo "[2/3] 添加路网索引..."
sudo -u postgres psql -d "$DB_NAME" << 'EOF'
-- 添加长度列（米）
ALTER TABLE ways ADD COLUMN IF NOT EXISTS length_m DOUBLE PRECISION;
UPDATE ways SET length_m = ST_Length(the_geom::geography);

-- 添加索引
CREATE INDEX IF NOT EXISTS idx_ways_source ON ways (source);
CREATE INDEX IF NOT EXISTS idx_ways_target ON ways (target);
CREATE INDEX IF NOT EXISTS idx_ways_geom ON ways USING GIST (the_geom);
CREATE INDEX IF NOT EXISTS idx_ways_vertices_geom ON ways_vertices_pgr USING GIST (the_geom);

-- 更新统计信息
ANALYZE ways;
ANALYZE ways_vertices_pgr;
EOF

echo "[3/3] 使用 osm2pgsql 导入 POI..."

# 检查 osm2pgsql 是否安装
if command -v osm2pgsql &> /dev/null; then
    osm2pgsql \
        -d "$DB_NAME" \
        -U "$DB_USER" \
        -H "$DB_HOST" \
        -P "$DB_PORT" \
        --slim \
        -C 2000 \
        "$OSM_FILE"
    
    # 提取 POI
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    sudo -u postgres psql -d "$DB_NAME" -f "${SCRIPT_DIR}/../migrations/003_import_osm_poi.sql"
else
    echo "警告: osm2pgsql 未安装，跳过 POI 导入"
    echo "请手动安装 osm2pgsql 并运行 POI 导入脚本"
fi

echo ""
echo "================================================"
echo "✅ OSM 数据导入完成！"
echo "================================================"
echo ""
echo "路网统计:"
sudo -u postgres psql -d "$DB_NAME" -c "
SELECT 
    COUNT(*) AS 边数,
    ROUND(SUM(length_m)/1000, 2) AS 总长度_km
FROM ways;
"
echo ""
echo "节点统计:"
sudo -u postgres psql -d "$DB_NAME" -c "
SELECT COUNT(*) AS 节点数 FROM ways_vertices_pgr;
"
echo ""
echo "POI 统计:"
sudo -u postgres psql -d "$DB_NAME" -c "
SELECT category AS 分类, COUNT(*) AS 数量 
FROM poi 
GROUP BY category 
ORDER BY COUNT(*) DESC;
"
