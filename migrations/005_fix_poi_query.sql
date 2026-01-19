-- ============================================================
-- 修复 POI 查询使用优化版等时圈
-- ============================================================

-- 更新 query_pois_in_isochrone 使用优化版等时圈
CREATE OR REPLACE FUNCTION query_pois_in_isochrone(
    p_lng DOUBLE PRECISION,
    p_lat DOUBLE PRECISION,
    p_time_minutes INTEGER DEFAULT 15,
    p_walk_speed_kmh DOUBLE PRECISION DEFAULT 5.0,
    p_category VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    id BIGINT,
    name VARCHAR,
    category VARCHAR,
    sub_type VARCHAR,
    lng DOUBLE PRECISION,
    lat DOUBLE PRECISION,
    distance_m DOUBLE PRECISION,
    walk_time_min DOUBLE PRECISION
) AS $$
DECLARE
    v_isochrone GEOMETRY;
    v_origin GEOMETRY;
BEGIN
    -- 使用优化版等时圈计算（获取指定分钟数的等时圈）
    SELECT geom INTO v_isochrone
    FROM calculate_isochrones_optimized(p_lng, p_lat, ARRAY[p_time_minutes], p_walk_speed_kmh)
    WHERE minutes = p_time_minutes
    LIMIT 1;
    
    v_origin := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326);
    
    -- 如果等时圈为空，返回空结果
    IF v_isochrone IS NULL THEN
        RETURN;
    END IF;
    
    RETURN QUERY
    SELECT 
        p.id,
        p.name,
        p.category,
        p.sub_type,
        ST_X(p.geom) AS lng,
        ST_Y(p.geom) AS lat,
        ST_Distance(p.geom::geography, v_origin::geography) AS distance_m,
        ST_Distance(p.geom::geography, v_origin::geography) / (p_walk_speed_kmh * 1000 / 60) AS walk_time_min
    FROM poi p
    WHERE ST_Within(p.geom, v_isochrone)
      AND (p_category IS NULL OR p.category = p_category)
    ORDER BY distance_m;
END;
$$ LANGUAGE plpgsql STABLE;

-- 更新 count_pois_in_isochrone 使用优化版等时圈
CREATE OR REPLACE FUNCTION count_pois_in_isochrone(
    p_lng DOUBLE PRECISION,
    p_lat DOUBLE PRECISION,
    p_time_minutes INTEGER DEFAULT 15,
    p_walk_speed_kmh DOUBLE PRECISION DEFAULT 5.0
)
RETURNS TABLE (
    category VARCHAR,
    sub_type VARCHAR,
    poi_count BIGINT
) AS $$
DECLARE
    v_isochrone GEOMETRY;
BEGIN
    -- 使用优化版等时圈计算
    SELECT geom INTO v_isochrone
    FROM calculate_isochrones_optimized(p_lng, p_lat, ARRAY[p_time_minutes], p_walk_speed_kmh)
    WHERE minutes = p_time_minutes
    LIMIT 1;
    
    -- 如果等时圈为空，返回空结果
    IF v_isochrone IS NULL THEN
        RETURN;
    END IF;
    
    RETURN QUERY
    SELECT 
        p.category,
        p.sub_type,
        COUNT(*)::BIGINT AS poi_count
    FROM poi p
    WHERE ST_Within(p.geom, v_isochrone)
    GROUP BY p.category, p.sub_type
    ORDER BY p.category, poi_count DESC;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION query_pois_in_isochrone IS '查询等时圈内POI - 使用优化版等时圈';
COMMENT ON FUNCTION count_pois_in_isochrone IS '统计等时圈内POI数量 - 使用优化版等时圈';
