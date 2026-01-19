-- ============================================================
-- v2.1 优化版等时圈计算函数
-- 单次路网分析，批量生成多个等时圈
-- ============================================================

-- ============================================================
-- 1. 优化版批量计算等时圈（只做一次路网分析）
-- ============================================================

DROP FUNCTION IF EXISTS calculate_isochrones_optimized(DOUBLE PRECISION, DOUBLE PRECISION, INTEGER[], DOUBLE PRECISION);

CREATE OR REPLACE FUNCTION calculate_isochrones_optimized(
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
    v_source_id BIGINT;
    v_max_cost DOUBLE PRECISION;
    v_origin GEOMETRY;
    v_threshold INTEGER;
    v_result GEOMETRY;
BEGIN
    v_origin := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326);
    
    -- 查找最近节点
    v_source_id := find_nearest_node(p_lng, p_lat);
    
    IF v_source_id IS NULL THEN
        -- 如果找不到路网节点，返回简单的缓冲区
        FOREACH v_threshold IN ARRAY p_time_thresholds
        LOOP
            v_result := ST_Transform(
                ST_Buffer(
                    ST_Transform(v_origin, 3857),
                    p_walk_speed_kmh * v_threshold / 60.0 * 1000
                ),
                4326
            );
            RETURN QUERY SELECT 
                v_threshold,
                (p_walk_speed_kmh * v_threshold / 60.0 * 1000),
                v_result,
                ST_AsGeoJSON(v_result);
        END LOOP;
        RETURN;
    END IF;
    
    -- 计算最大时间阈值
    SELECT MAX(t) INTO v_max_cost FROM unnest(p_time_thresholds) AS t;
    
    -- 创建临时表存储所有可达节点（只做一次路网分析）
    CREATE TEMP TABLE IF NOT EXISTS temp_reachable_nodes (
        node BIGINT,
        agg_cost DOUBLE PRECISION
    ) ON COMMIT DROP;
    
    TRUNCATE temp_reachable_nodes;
    
    INSERT INTO temp_reachable_nodes (node, agg_cost)
    SELECT dd.node, dd.agg_cost
    FROM pgr_drivingDistance(
        'SELECT gid AS id, 
                source, 
                target, 
                length_m / (' || p_walk_speed_kmh || ' * 1000.0 / 60.0) AS cost,
                length_m / (' || p_walk_speed_kmh || ' * 1000.0 / 60.0) AS reverse_cost
         FROM ways',
        v_source_id,
        v_max_cost,
        FALSE
    ) AS dd;
    
    -- 为每个时间阈值生成等时圈（复用可达节点数据）
    FOREACH v_threshold IN ARRAY p_time_thresholds
    LOOP
        WITH 
        -- 筛选该时间阈值内的节点
        filtered_nodes AS (
            SELECT node FROM temp_reachable_nodes WHERE agg_cost <= v_threshold
        ),
        -- 获取节点几何
        node_points AS (
            SELECT v.the_geom
            FROM filtered_nodes fn
            JOIN ways_vertices_pgr v ON fn.node = v.id
        ),
        -- 获取可达道路线段
        reachable_edges AS (
            SELECT DISTINCT w.the_geom
            FROM filtered_nodes fn
            JOIN ways w ON (w.source = fn.node OR w.target = fn.node)
            WHERE EXISTS (
                SELECT 1 FROM filtered_nodes fn2 
                WHERE fn2.node = w.source OR fn2.node = w.target
            )
        ),
        -- 合并所有点
        all_points AS (
            SELECT the_geom FROM node_points
            UNION ALL
            SELECT ST_StartPoint(the_geom) FROM reachable_edges
            UNION ALL
            SELECT ST_EndPoint(the_geom) FROM reachable_edges
            UNION ALL
            SELECT ST_LineInterpolatePoint(the_geom, 0.5) FROM reachable_edges WHERE ST_Length(the_geom) > 0.0001
        ),
        collected AS (
            SELECT ST_Collect(the_geom) AS geom, COUNT(*) AS cnt
            FROM all_points
        )
        SELECT 
            CASE 
                WHEN cnt < 10 THEN 
                    ST_Transform(
                        ST_Buffer(ST_Transform(v_origin, 3857), p_walk_speed_kmh * v_threshold / 60.0 * 1000),
                        4326
                    )
                ELSE 
                    COALESCE(
                        ST_ConcaveHull(geom, 0.5),  -- 稍微放宽凹度参数提升性能
                        ST_ConvexHull(geom),
                        ST_Transform(
                            ST_Buffer(ST_Transform(v_origin, 3857), p_walk_speed_kmh * v_threshold / 60.0 * 1000),
                            4326
                        )
                    )
            END
        INTO v_result
        FROM collected;
        
        RETURN QUERY SELECT 
            v_threshold,
            (p_walk_speed_kmh * v_threshold / 60.0 * 1000),
            v_result,
            ST_AsGeoJSON(v_result);
    END LOOP;
    
    -- 清理临时表
    DROP TABLE IF EXISTS temp_reachable_nodes;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_isochrones_optimized IS '优化版批量等时圈计算 - 单次路网分析';


-- ============================================================
-- 2. 替换原有函数
-- ============================================================

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
    RETURN QUERY SELECT * FROM calculate_isochrones_optimized(p_lng, p_lat, p_time_thresholds, p_walk_speed_kmh);
END;
$$ LANGUAGE plpgsql;
