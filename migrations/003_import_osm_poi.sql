-- ============================================================
-- OSM 数据导入辅助脚本
-- 从 OSM 数据提取 POI 到 poi 表
-- ============================================================

-- 从 osm2pgsql 导入的表提取 POI
-- 假设使用标准的 planet_osm_point 和 planet_osm_polygon 表

-- 如果使用 osm2pgsql 导入，执行以下语句

-- ============================================================
-- 1. 从点表提取 POI
-- ============================================================

INSERT INTO poi (osm_id, name, category, sub_type, geom, tags)
SELECT 
    osm_id,
    name,
    CASE 
        -- 医疗卫生
        WHEN amenity IN ('hospital') THEN 'medical'
        WHEN amenity IN ('clinic', 'doctors') THEN 'medical'
        WHEN amenity IN ('pharmacy') THEN 'medical'
        -- 教育设施
        WHEN amenity IN ('kindergarten') THEN 'education'
        WHEN amenity IN ('school') THEN 'education'
        -- 商业服务
        WHEN shop IN ('supermarket') THEN 'commerce'
        WHEN amenity IN ('marketplace') THEN 'commerce'
        WHEN shop IN ('convenience') THEN 'commerce'
        -- 文化体育
        WHEN amenity IN ('library') THEN 'culture'
        WHEN leisure IN ('sports_centre', 'stadium') THEN 'culture'
        WHEN leisure IN ('park') THEN 'culture'
        -- 公共服务
        WHEN amenity IN ('community_centre') THEN 'public'
        WHEN amenity IN ('bank') THEN 'public'
        WHEN amenity IN ('post_office') THEN 'public'
        -- 交通设施
        WHEN highway IN ('bus_stop') THEN 'transport'
        WHEN railway IN ('station') THEN 'transport'
        WHEN public_transport IN ('stop_position', 'platform') THEN 'transport'
        -- 养老服务
        WHEN amenity IN ('nursing_home', 'social_facility') THEN 'elderly'
    END AS category,
    CASE 
        WHEN amenity = 'hospital' THEN 'hospital'
        WHEN amenity IN ('clinic', 'doctors') THEN 'clinic'
        WHEN amenity = 'pharmacy' THEN 'pharmacy'
        WHEN amenity = 'kindergarten' THEN 'kindergarten'
        WHEN amenity = 'school' THEN 'primary'  -- 需要进一步区分
        WHEN shop = 'supermarket' THEN 'supermarket'
        WHEN amenity = 'marketplace' THEN 'marketplace'
        WHEN shop = 'convenience' THEN 'convenience'
        WHEN amenity = 'library' THEN 'library'
        WHEN leisure IN ('sports_centre', 'stadium') THEN 'sports'
        WHEN leisure = 'park' THEN 'park'
        WHEN amenity = 'community_centre' THEN 'community'
        WHEN amenity = 'bank' THEN 'bank'
        WHEN amenity = 'post_office' THEN 'post'
        WHEN highway = 'bus_stop' OR public_transport IN ('stop_position', 'platform') THEN 'bus'
        WHEN railway = 'station' THEN 'subway'
        WHEN amenity = 'nursing_home' THEN 'nursing'
        WHEN amenity = 'social_facility' THEN 'social'
    END AS sub_type,
    way AS geom,
    tags
FROM planet_osm_point
WHERE 
    amenity IN ('hospital', 'clinic', 'doctors', 'pharmacy', 
                'kindergarten', 'school', 'marketplace', 
                'library', 'community_centre', 'bank', 'post_office',
                'nursing_home', 'social_facility')
    OR shop IN ('supermarket', 'convenience')
    OR leisure IN ('sports_centre', 'stadium', 'park')
    OR highway = 'bus_stop'
    OR railway = 'station'
    OR public_transport IN ('stop_position', 'platform')
ON CONFLICT DO NOTHING;

-- ============================================================
-- 2. 从多边形表提取 POI（取质心）
-- ============================================================

INSERT INTO poi (osm_id, name, category, sub_type, geom, tags)
SELECT 
    osm_id,
    name,
    CASE 
        WHEN amenity IN ('hospital') THEN 'medical'
        WHEN amenity IN ('clinic', 'doctors') THEN 'medical'
        WHEN amenity IN ('kindergarten') THEN 'education'
        WHEN amenity IN ('school') THEN 'education'
        WHEN shop IN ('supermarket') THEN 'commerce'
        WHEN amenity IN ('marketplace') THEN 'commerce'
        WHEN amenity IN ('library') THEN 'culture'
        WHEN leisure IN ('sports_centre', 'stadium') THEN 'culture'
        WHEN leisure IN ('park') THEN 'culture'
        WHEN amenity IN ('community_centre') THEN 'public'
        WHEN amenity IN ('nursing_home', 'social_facility') THEN 'elderly'
    END AS category,
    CASE 
        WHEN amenity = 'hospital' THEN 'hospital'
        WHEN amenity IN ('clinic', 'doctors') THEN 'clinic'
        WHEN amenity = 'kindergarten' THEN 'kindergarten'
        WHEN amenity = 'school' THEN 'primary'
        WHEN shop = 'supermarket' THEN 'supermarket'
        WHEN amenity = 'marketplace' THEN 'marketplace'
        WHEN amenity = 'library' THEN 'library'
        WHEN leisure IN ('sports_centre', 'stadium') THEN 'sports'
        WHEN leisure = 'park' THEN 'park'
        WHEN amenity = 'community_centre' THEN 'community'
        WHEN amenity = 'nursing_home' THEN 'nursing'
        WHEN amenity = 'social_facility' THEN 'social'
    END AS sub_type,
    ST_Centroid(way) AS geom,
    tags
FROM planet_osm_polygon
WHERE 
    amenity IN ('hospital', 'clinic', 'doctors', 
                'kindergarten', 'school', 'marketplace', 
                'library', 'community_centre',
                'nursing_home', 'social_facility')
    OR shop IN ('supermarket')
    OR leisure IN ('sports_centre', 'stadium', 'park')
ON CONFLICT DO NOTHING;

-- ============================================================
-- 3. 更新统计信息
-- ============================================================

ANALYZE poi;

-- 查看导入结果
SELECT 
    category,
    sub_type,
    COUNT(*) AS count
FROM poi
GROUP BY category, sub_type
ORDER BY category, sub_type;
