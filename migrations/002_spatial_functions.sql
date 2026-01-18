-- ============================================================
-- 核心空间函数
-- 用于等时圈计算和 POI 分析
-- ============================================================

-- ============================================================
-- 1. 查找最近的路网节点
-- ============================================================

CREATE OR REPLACE FUNCTION find_nearest_node(
    p_lng DOUBLE PRECISION,
    p_lat DOUBLE PRECISION,
    p_max_distance_m INTEGER DEFAULT 500
)
RETURNS BIGINT AS $$
DECLARE
    v_node_id BIGINT;
BEGIN
    -- 查找给定点最近的路网节点
    -- 使用 KNN 索引优化
    SELECT id INTO v_node_id
    FROM ways_vertices_pgr
    WHERE ST_DWithin(
        the_geom::geography,
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
        p_max_distance_m
    )
    ORDER BY the_geom <-> ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)
    LIMIT 1;
    
    RETURN v_node_id;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION find_nearest_node IS '查找给定经纬度最近的路网节点';

-- ============================================================
-- 2. 计算步行等时圈（基于 pgRouting）
-- ============================================================

CREATE OR REPLACE FUNCTION calculate_isochrone(
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
BEGIN
    -- 查找最近节点
    v_source_id := find_nearest_node(p_lng, p_lat);
    
    IF v_source_id IS NULL THEN
        -- 如果找不到路网节点，返回简单的缓冲区
        -- 使用投影坐标系计算距离后转回 4326
        RETURN ST_Transform(
            ST_Buffer(
                ST_Transform(ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326), 3857),
                p_walk_speed_kmh * p_time_minutes / 60.0 * 1000  -- 米
            ),
            4326
        );
    END IF;
    
    -- 计算最大成本（假设 ways 表的 cost 是分钟）
    -- 如果 cost 是长度（米），需要转换: cost_time = length / (speed * 1000 / 60)
    v_max_cost := p_time_minutes;
    
    -- 使用 pgr_drivingDistance 计算可达节点
    -- 然后用凹包/凸包生成等时圈多边形
    WITH reachable_nodes AS (
        SELECT 
            node,
            agg_cost
        FROM pgr_drivingDistance(
            -- 双向步行路网
            'SELECT gid AS id, 
                    source, 
                    target, 
                    -- 成本 = 距离(米) / 速度(m/min)
                    length_m / (' || p_walk_speed_kmh || ' * 1000.0 / 60.0) AS cost,
                    length_m / (' || p_walk_speed_kmh || ' * 1000.0 / 60.0) AS reverse_cost
             FROM ways 
             WHERE one_way != 1',  -- 排除单向道路或根据实际字段调整
            v_source_id,
            v_max_cost,
            FALSE  -- 非定向图
        )
    ),
    reachable_points AS (
        SELECT 
            v.the_geom
        FROM reachable_nodes rn
        JOIN ways_vertices_pgr v ON rn.node = v.id
    )
    SELECT 
        -- 使用 ST_ConcaveHull 生成凹多边形（更准确）
        -- 参数 0.7 控制凹度 (0=凸包, 1=完全凹)
        COALESCE(
            ST_ConcaveHull(ST_Collect(the_geom), 0.7),
            ST_ConvexHull(ST_Collect(the_geom)),
            ST_Buffer(ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography, 100)::geometry
        )
    INTO v_result
    FROM reachable_points;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION calculate_isochrone IS '计算步行等时圈多边形';

-- ============================================================
-- 3. 批量计算多个时间阈值的等时圈
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
DECLARE
    v_threshold INTEGER;
BEGIN
    FOREACH v_threshold IN ARRAY p_time_thresholds
    LOOP
        RETURN QUERY
        SELECT 
            v_threshold AS minutes,
            (p_walk_speed_kmh * v_threshold / 60.0 * 1000) AS distance_m,
            calculate_isochrone(p_lng, p_lat, v_threshold, p_walk_speed_kmh) AS geom,
            ST_AsGeoJSON(calculate_isochrone(p_lng, p_lat, v_threshold, p_walk_speed_kmh)) AS geojson;
    END LOOP;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================
-- 4. 查询等时圈内的 POI
-- ============================================================

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
    -- 计算等时圈
    v_isochrone := calculate_isochrone(p_lng, p_lat, p_time_minutes, p_walk_speed_kmh);
    v_origin := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326);
    
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

-- ============================================================
-- 5. 统计等时圈内 POI 数量
-- ============================================================

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
    v_isochrone := calculate_isochrone(p_lng, p_lat, p_time_minutes, p_walk_speed_kmh);
    
    RETURN QUERY
    SELECT 
        p.category,
        p.sub_type,
        COUNT(*)::BIGINT AS poi_count
    FROM poi p
    WHERE ST_Within(p.geom, v_isochrone)
    GROUP BY p.category, p.sub_type
    ORDER BY p.category, p.sub_type;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================
-- 6. 综合评分计算
-- ============================================================

CREATE OR REPLACE FUNCTION evaluate_life_circle(
    p_lng DOUBLE PRECISION,
    p_lat DOUBLE PRECISION,
    p_walk_speed_kmh DOUBLE PRECISION DEFAULT 5.0
)
RETURNS TABLE (
    total_score DECIMAL,
    grade CHAR(1),
    category VARCHAR,
    category_name VARCHAR,
    category_weight DECIMAL,
    category_score DECIMAL,
    weighted_score DECIMAL,
    poi_count BIGINT,
    details JSONB
) AS $$
BEGIN
    RETURN QUERY
    WITH 
    -- 计算各时间阈值的等时圈
    isochrones AS (
        SELECT 
            5 AS minutes, calculate_isochrone(p_lng, p_lat, 5, p_walk_speed_kmh) AS geom
        UNION ALL
        SELECT 
            10, calculate_isochrone(p_lng, p_lat, 10, p_walk_speed_kmh)
        UNION ALL
        SELECT 
            15, calculate_isochrone(p_lng, p_lat, 15, p_walk_speed_kmh)
    ),
    -- 统计各等时圈内的 POI
    poi_counts AS (
        SELECT 
            p.category,
            p.sub_type,
            i.minutes,
            COUNT(*)::INT AS cnt
        FROM poi p
        CROSS JOIN isochrones i
        WHERE ST_Within(p.geom, i.geom)
        GROUP BY p.category, p.sub_type, i.minutes
    ),
    -- 计算子类型得分
    subtype_scores AS (
        SELECT 
            es.category,
            es.sub_type,
            COALESCE(pc5.cnt, 0) AS count_5,
            COALESCE(pc10.cnt, 0) AS count_10,
            COALESCE(pc15.cnt, 0) AS count_15,
            es.min_count_5,
            es.min_count_10,
            es.min_count_15,
            es.is_required,
            es.base_score,
            -- 计算得分：满足要求得满分，部分满足按比例
            CASE 
                WHEN COALESCE(pc15.cnt, 0) >= es.min_count_15 THEN es.base_score
                WHEN es.min_count_15 > 0 THEN 
                    es.base_score * COALESCE(pc15.cnt, 0)::DECIMAL / es.min_count_15
                ELSE es.base_score
            END AS score
        FROM evaluation_standard es
        LEFT JOIN poi_counts pc5 ON pc5.category = es.category 
            AND pc5.sub_type = es.sub_type AND pc5.minutes = 5
        LEFT JOIN poi_counts pc10 ON pc10.category = es.category 
            AND pc10.sub_type = es.sub_type AND pc10.minutes = 10
        LEFT JOIN poi_counts pc15 ON pc15.category = es.category 
            AND pc15.sub_type = es.sub_type AND pc15.minutes = 15
    ),
    -- 按分类汇总
    category_summary AS (
        SELECT 
            ss.category,
            c.name AS category_name,
            c.weight AS category_weight,
            SUM(ss.score) AS raw_score,
            SUM(ss.base_score) AS max_score,
            SUM(ss.count_15) AS total_poi_count,
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'sub_type', ss.sub_type,
                    'count_5', ss.count_5,
                    'count_10', ss.count_10,
                    'count_15', ss.count_15,
                    'required', ss.min_count_15,
                    'score', ss.score,
                    'max_score', ss.base_score,
                    'is_required', ss.is_required
                )
            ) AS sub_details
        FROM subtype_scores ss
        JOIN poi_category c ON c.code = ss.category
        GROUP BY ss.category, c.name, c.weight
    ),
    -- 计算总分
    total AS (
        SELECT 
            -- 归一化到 100 分制
            ROUND(SUM(
                CASE 
                    WHEN max_score > 0 THEN (raw_score / max_score) * 100 * category_weight
                    ELSE 0
                END
            ) / SUM(category_weight), 2) AS total_score
        FROM category_summary
    )
    SELECT 
        t.total_score,
        CASE 
            WHEN t.total_score >= 90 THEN 'A'
            WHEN t.total_score >= 75 THEN 'B'
            WHEN t.total_score >= 60 THEN 'C'
            WHEN t.total_score >= 45 THEN 'D'
            ELSE 'E'
        END::CHAR(1) AS grade,
        cs.category,
        cs.category_name,
        cs.category_weight,
        ROUND(CASE WHEN cs.max_score > 0 THEN cs.raw_score / cs.max_score * 100 ELSE 0 END, 2) AS category_score,
        ROUND(CASE WHEN cs.max_score > 0 THEN cs.raw_score / cs.max_score * 100 * cs.category_weight ELSE 0 END, 2) AS weighted_score,
        cs.total_poi_count,
        cs.sub_details
    FROM category_summary cs
    CROSS JOIN total t
    ORDER BY cs.category;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION evaluate_life_circle IS '综合评价15分钟生活圈服务覆盖度';
