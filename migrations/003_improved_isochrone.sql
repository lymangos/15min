-- ============================================================
-- v2.0 改进的等时圈计算函数
-- 生成更贴合实际路网的不规则多边形
-- ============================================================

-- ============================================================
-- 1. 改进版等时圈计算（基于道路可达性）
-- ============================================================

DROP FUNCTION IF EXISTS calculate_isochrone_v2(DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, DOUBLE PRECISION);

CREATE OR REPLACE FUNCTION calculate_isochrone_v2(
    p_lng DOUBLE PRECISION,
    p_lat DOUBLE PRECISION,
    p_time_minutes INTEGER DEFAULT 15,
    p_walk_speed_kmh DOUBLE PRECISION DEFAULT 5.0
)
RETURNS GEOMETRY AS $$
DECLARE
    v_source_id BIGINT;
    v_max_cost DOUBLE PRECISION;
    v_result GEOMETRY;
    v_node_count INTEGER;
    v_origin GEOMETRY;
BEGIN
    v_origin := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326);
    
    -- 查找最近节点
    v_source_id := find_nearest_node(p_lng, p_lat);
    
    IF v_source_id IS NULL THEN
        -- 如果找不到路网节点，返回简单的缓冲区
        RETURN ST_Transform(
            ST_Buffer(
                ST_Transform(v_origin, 3857),
                p_walk_speed_kmh * p_time_minutes / 60.0 * 1000
            ),
            4326
        );
    END IF;
    
    -- 计算最大成本（分钟）
    v_max_cost := p_time_minutes;
    
    -- 使用改进的方法：
    -- 1. 收集所有可达的道路线段（不仅是节点）
    -- 2. 使用 ST_ConcaveHull 生成边界，参数更小使边界更贴合
    -- 3. 步行不受单向限制，所以使用双向 cost
    WITH reachable_nodes AS (
        SELECT 
            node,
            agg_cost
        FROM pgr_drivingDistance(
            -- 步行路网：双向通行，不考虑单向道路限制
            'SELECT gid AS id, 
                    source, 
                    target, 
                    length_m / (' || p_walk_speed_kmh || ' * 1000.0 / 60.0) AS cost,
                    length_m / (' || p_walk_speed_kmh || ' * 1000.0 / 60.0) AS reverse_cost
             FROM ways',
            v_source_id,
            v_max_cost,
            FALSE
        )
    ),
    -- 收集可达节点的几何
    reachable_points AS (
        SELECT v.the_geom
        FROM reachable_nodes rn
        JOIN ways_vertices_pgr v ON rn.node = v.id
    ),
    -- 同时收集可达道路线段（更精确地表示可达边界）
    reachable_edges AS (
        SELECT w.the_geom
        FROM reachable_nodes rn
        JOIN ways w ON (w.source = rn.node OR w.target = rn.node)
        WHERE EXISTS (
            SELECT 1 FROM reachable_nodes rn2 
            WHERE rn2.node = w.source OR rn2.node = w.target
        )
    ),
    -- 合并所有几何：节点 + 线段上的插值点
    all_points AS (
        -- 可达节点
        SELECT the_geom FROM reachable_points
        UNION ALL
        -- 可达道路线段的端点和中点
        SELECT ST_StartPoint(the_geom) FROM reachable_edges
        UNION ALL
        SELECT ST_EndPoint(the_geom) FROM reachable_edges
        UNION ALL
        SELECT ST_LineInterpolatePoint(the_geom, 0.25) FROM reachable_edges WHERE ST_Length(the_geom) > 0.0001
        UNION ALL
        SELECT ST_LineInterpolatePoint(the_geom, 0.5) FROM reachable_edges WHERE ST_Length(the_geom) > 0.0001
        UNION ALL
        SELECT ST_LineInterpolatePoint(the_geom, 0.75) FROM reachable_edges WHERE ST_Length(the_geom) > 0.0001
    ),
    collected AS (
        SELECT ST_Collect(the_geom) AS geom, COUNT(*) AS cnt
        FROM all_points
    )
    SELECT 
        cnt,
        CASE 
            -- 点太少时返回缓冲区
            WHEN cnt < 10 THEN 
                ST_Transform(
                    ST_Buffer(ST_Transform(v_origin, 3857), p_walk_speed_kmh * p_time_minutes / 60.0 * 1000),
                    4326
                )
            -- 使用凹包，参数 0.3 生成更贴合道路的边界
            ELSE 
                COALESCE(
                    -- 先尝试 ST_ConcaveHull (target_percent=0.3 更凹)
                    ST_ConcaveHull(geom, 0.3),
                    -- 回退到凸包
                    ST_ConvexHull(geom),
                    -- 最终回退到缓冲区
                    ST_Transform(
                        ST_Buffer(ST_Transform(v_origin, 3857), p_walk_speed_kmh * p_time_minutes / 60.0 * 1000),
                        4326
                    )
                )
        END
    INTO v_node_count, v_result
    FROM collected;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION calculate_isochrone_v2 IS '改进版等时圈计算 - 生成更贴合路网的不规则多边形';


-- ============================================================
-- 2. 改进版批量计算等时圈
-- ============================================================

DROP FUNCTION IF EXISTS calculate_isochrones_v2(DOUBLE PRECISION, DOUBLE PRECISION, INTEGER[], DOUBLE PRECISION);

CREATE OR REPLACE FUNCTION calculate_isochrones_v2(
    p_lng DOUBLE PRECISION,
    p_lat DOUBLE PRECISION,
    p_time_thresholds INTEGER[] DEFAULT ARRAY[5, 10, 15],
    p_walk_speed_kmh DOUBLE PRECISION DEFAULT 5.0
)
RETURNS TABLE (
    minutes INTEGER,
    distance_m DOUBLE PRECISION,
    geom GEOMETRY,
    geojson TEXT
) AS $$
DECLARE
    v_threshold INTEGER;
    v_geom GEOMETRY;
BEGIN
    FOREACH v_threshold IN ARRAY p_time_thresholds
    LOOP
        v_geom := calculate_isochrone_v2(p_lng, p_lat, v_threshold, p_walk_speed_kmh);
        RETURN QUERY
        SELECT 
            v_threshold AS minutes,
            (p_walk_speed_kmh * v_threshold / 60.0 * 1000) AS distance_m,
            v_geom AS geom,
            ST_AsGeoJSON(v_geom) AS geojson;
    END LOOP;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION calculate_isochrones_v2 IS '批量计算改进版等时圈';


-- ============================================================
-- 3. 替换原有函数（可选：保持向后兼容）
-- ============================================================

-- 重新创建原有函数名，内部调用 v2 版本
CREATE OR REPLACE FUNCTION calculate_isochrone(
    p_lng DOUBLE PRECISION,
    p_lat DOUBLE PRECISION,
    p_time_minutes INTEGER DEFAULT 15,
    p_walk_speed_kmh DOUBLE PRECISION DEFAULT 5.0
)
RETURNS GEOMETRY AS $$
BEGIN
    RETURN calculate_isochrone_v2(p_lng, p_lat, p_time_minutes, p_walk_speed_kmh);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION calculate_isochrones(
    p_lng DOUBLE PRECISION,
    p_lat DOUBLE PRECISION,
    p_time_thresholds INTEGER[] DEFAULT ARRAY[5, 10, 15],
    p_walk_speed_kmh DOUBLE PRECISION DEFAULT 5.0
)
RETURNS TABLE (
    minutes INTEGER,
    distance_m DOUBLE PRECISION,
    geom GEOMETRY,
    geojson TEXT
) AS $$
BEGIN
    RETURN QUERY SELECT * FROM calculate_isochrones_v2(p_lng, p_lat, p_time_thresholds, p_walk_speed_kmh);
END;
$$ LANGUAGE plpgsql STABLE;
