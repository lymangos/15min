#!/bin/bash
# ============================================
# 多城市 OSM 数据下载脚本
# ============================================

set -e

DATA_DIR="${DATA_DIR:-./data}"
mkdir -p "$DATA_DIR"

echo "================================================"
echo "15分钟生活圈 - 多城市数据下载"
echo "================================================"
echo ""

# 城市配置
declare -A CITIES=(
    ["hangzhou"]="浙江省杭州市"
    ["zhuji"]="浙江省诸暨市"
    ["shenyang"]="辽宁省沈阳市"
)

# 边界框 (west,south,east,north)
declare -A CITY_BOUNDS=(
    ["hangzhou"]="119.9,30.1,120.5,30.5"
    ["zhuji"]="119.8,29.5,120.5,30.0"
    ["shenyang"]="123.0,41.5,123.8,42.1"
)

# 从 Overpass API 下载数据
download_city() {
    local city=$1
    local bounds=${CITY_BOUNDS[$city]}
    local output="$DATA_DIR/${city}.osm"
    
    echo "📥 正在下载 ${CITIES[$city]} ..."
    echo "   边界: $bounds"
    
    if [ -f "$output" ]; then
        echo "   ⚠️ 文件已存在，跳过下载: $output"
        return 0
    fi
    
    # 使用 Overpass API 下载
    curl -s "https://overpass-api.de/api/map?bbox=$bounds" -o "$output"
    
    if [ -s "$output" ]; then
        echo "   ✅ 下载完成: $output ($(du -h "$output" | cut -f1))"
    else
        echo "   ❌ 下载失败"
        rm -f "$output"
        return 1
    fi
}

# 下载所有城市
for city in "${!CITIES[@]}"; do
    download_city "$city"
    echo ""
done

echo "================================================"
echo "✅ 所有城市数据下载完成！"
echo "================================================"
echo ""
echo "下一步: 运行导入脚本"
echo "  ./scripts/import_all_cities.sh"
