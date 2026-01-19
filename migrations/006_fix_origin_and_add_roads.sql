-- ============================================================
-- v2.2 修复等时圈包含原点问题 + 添加道路网络输出
-- ============================================================

-- ============================================================
-- 1. 修复原点不在等时圈内的问题
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
    v_collected GEOMETRY;
    v_cnt INTEGER;
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
            minutes := v_threshold;
            distance_m := p_walk_speed_kmh * v_threshold / 60.0 * 1000;
            geom := v_result;
            geojson := ST_AsGeoJSON(v_result);
            RETURN NEXT;
        END LOOP;
        RETURN;
    END IF;
    
    -- 计算最大时间阈值
    SELECT MAX(t) INTO v_max_cost FROM unnest(p_time_thresholds) AS t;
    
    -- 创建临时表存储所有可达节点（只做一次路网分析）
    DROP TABLE IF EXISTS temp_reachable_nodes;
    CREATE TEMP TABLE temp_reachable_nodes (
        node BIGINT,
        agg_cost DOUBLE PRECISION
    );
    
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
        -- 收集所有点到变量（包括原点！）
        SELECT ST_Collect(pt.the_geom), COUNT(*) 
        INTO v_collected, v_cnt
        FROM (
            -- 【关键】添加原点，确保原点一定在等时圈内
            SELECT v_origin AS the_geom
            UNION ALL
            -- 节点几何
            SELECT v.the_geom
            FROM temp_reachable_nodes trn
            JOIN ways_vertices_pgr v ON trn.node = v.id
            WHERE trn.agg_cost <= v_threshold
            UNION ALL
            -- 可达道路的起点/终点/中点
            SELECT ST_StartPoint(w.the_geom)
            FROM ways w
            WHERE EXISTS (SELECT 1 FROM temp_reachable_nodes t1 WHERE t1.node = w.source AND t1.agg_cost <= v_threshold)
              AND EXISTS (SELECT 1 FROM temp_reachable_nodes t2 WHERE t2.node = w.target AND t2.agg_cost <= v_threshold)
            UNION ALL
            SELECT ST_EndPoint(w.the_geom)
            FROM ways w
            WHERE EXISTS (SELECT 1 FROM temp_reachable_nodes t1 WHERE t1.node = w.source AND t1.agg_cost <= v_threshold)
              AND EXISTS (SELECT 1 FROM temp_reachable_nodes t2 WHERE t2.node = w.target AND t2.agg_cost <= v_threshold)
            UNION ALL
            SELECT ST_LineInterpolatePoint(w.the_geom, 0.5)
            FROM ways w
            WHERE EXISTS (SELECT 1 FROM temp_reachable_nodes t1 WHERE t1.node = w.source AND t1.agg_cost <= v_threshold)
              AND EXISTS (SELECT 1 FROM temp_reachable_nodes t2 WHERE t2.node = w.target AND t2.agg_cost <= v_threshold)
              AND ST_Length(w.the_geom) > 0.0001
        ) AS pt;
        
        -- 根据点数量选择算法
        IF v_cnt IS NULL OR v_cnt < 10 THEN
            v_result := ST_Transform(
                ST_Buffer(ST_Transform(v_origin, 3857), p_walk_speed_kmh * v_threshold / 60.0 * 1000),
                4326
            );
        ELSE
            -- 使用凹壳，并确保结果包含原点
            v_result := COALESCE(
                ST_ConcaveHull(v_collected, 0.5),
                ST_ConvexHull(v_collected),
                ST_Transform(
                    ST_Buffer(ST_Transform(v_origin, 3857), p_walk_speed_kmh * v_threshold / 60.0 * 1000),
                    4326
                )
            );
            
            -- 如果结果仍不包含原点，与原点缓冲区合并
            IF NOT ST_Within(v_origin, v_result) THEN
                v_result := ST_Union(
                    v_result,
                    ST_Transform(
                        ST_Buffer(ST_Transform(v_origin, 3857), 50), -- 50米缓冲
                        4326
                    )
                );
            END IF;
        END IF;
        
        -- 返回结果
        minutes := v_threshold;
        distance_m := p_walk_speed_kmh * v_threshold / 60.0 * 1000;
        geom := v_result;
        geojson := ST_AsGeoJSON(v_result);
        RETURN NEXT;
    END LOOP;
    
    -- 清理临时表
    DROP TABLE IF EXISTS temp_reachable_nodes;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calculate_isochrones_optimized IS '优化版批量等时圈计算 - 确保包含原点';

-- ============================================================
-- 2. 添加获取可达道路网络的函数
-- ============================================================

DROP FUNCTION IF EXISTS get_reachable_roads(DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, DOUBLE PRECISION);

CREATE OR REPLACE FUNCTION get_reachable_roads(
    p_lng DOUBLE PRECISION,
    p_lat DOUBLE PRECISION,
    p_time_minutes INTEGER DEFAULT 15,
    p_walk_speed_kmh DOUBLE PRECISION DEFAULT 5.0
)
RETURNS TABLE (
    road_geojson TEXT
) AS $$
DECLARE
    v_source_id BIGINT;
BEGIN
    -- 查找最近节点
    v_source_id := find_nearest_node(p_lng, p_lat);
    
    IF v_source_id IS NULL THEN
        RETURN;
    END IF;
    
    -- 返回可达道路的GeoJSON FeatureCollection
    RETURN QUERY
    SELECT json_build_object(
        'type', 'FeatureCollection',
        'features', COALESCE(json_agg(
            json_build_object(
                'type', 'Feature',
                'geometry', ST_AsGeoJSON(w.the_geom)::json,
                'properties', json_build_object(
                    'name', COALESCE(w.name, ''),
                    'type', 'road',
                    'cost', LEAST(t1.agg_cost, t2.agg_cost)
                )
            )
        ), '[]'::json)
    )::text
    FROM ways w
    JOIN (
        SELECT dd.node, dd.agg_cost
        FROM pgr_drivingDistance(
            'SELECT gid AS id, 
                    source, 
                    target, 
                    length_m / (' || p_walk_speed_kmh || ' * 1000.0 / 60.0) AS cost,
                    length_m / (' || p_walk_speed_kmh || ' * 1000.0 / 60.0) AS reverse_cost
             FROM ways',
            v_source_id,
            p_time_minutes,
            FALSE
        ) AS dd
    ) t1 ON w.source = t1.node
    JOIN (
        SELECT dd.node, dd.agg_cost
        FROM pgr_drivingDistance(
            'SELECT gid AS id, 
                    source, 
                    target, 
                    length_m / (' || p_walk_speed_kmh || ' * 1000.0 / 60.0) AS cost,
                    length_m / (' || p_walk_speed_kmh || ' * 1000.0 / 60.0) AS reverse_cost
             FROM ways',
            v_source_id,
            p_time_minutes,
            FALSE
        ) AS dd
    ) t2 ON w.target = t2.node
    WHERE t1.agg_cost <= p_time_minutes AND t2.agg_cost <= p_time_minutes;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_reachable_roads IS '获取指定时间内可达的道路网络';

-- ============================================================
-- 3. 更新 calculate_isochrones 包装函数
-- ============================================================

DROP FUNCTION IF EXISTS calculate_isochrones(DOUBLE PRECISION, DOUBLE PRECISION, INTEGER[], DOUBLE PRECISION);

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
