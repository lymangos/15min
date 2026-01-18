# 坐标系与空间计算指南

## 坐标系基础

### 常用坐标系

| SRID | 名称 | 类型 | 单位 | 使用场景 |
|------|------|------|------|----------|
| 4326 | WGS84 | 地理坐标系 | 度 | GPS、Web 地图、数据存储 |
| 3857 | Web Mercator | 投影坐标系 | 米 | Web 地图瓦片、显示 |
| 4490 | CGCS2000 | 地理坐标系 | 度 | 中国国家标准 |
| 4547 | CGCS2000 Zone 38 | 投影坐标系 | 米 | 中国中部地区 |

### 本项目坐标系策略

```
存储: SRID 4326 (WGS84)
  └── 原因: 与 OSM 数据一致，通用性强

计算: 使用 geography 类型或本地投影
  └── 原因: 精确的距离和面积计算

显示: SRID 4326
  └── 原因: Leaflet/Mapbox 默认使用 WGS84
```

## PostGIS 空间计算

### 距离计算

```sql
-- 方法1: 使用 geography 类型 (推荐，全球适用)
SELECT ST_Distance(
    point_a::geography,
    point_b::geography
) AS distance_meters;

-- 方法2: 使用 ST_DistanceSphere (球面近似)
SELECT ST_DistanceSphere(point_a, point_b) AS distance_meters;

-- 方法3: 投影后计算 (适用于小范围)
SELECT ST_Distance(
    ST_Transform(point_a, 3857),
    ST_Transform(point_b, 3857)
) AS distance_meters;
```

### 缓冲区分析

```sql
-- 创建指定距离的缓冲区
-- 使用 geography 类型确保距离准确

SELECT ST_Buffer(
    point::geography,
    1000  -- 1000米半径
)::geometry AS buffer_geom;

-- 或者先投影，再缓冲，再转回
SELECT ST_Transform(
    ST_Buffer(
        ST_Transform(point, 3857),
        1000
    ),
    4326
) AS buffer_geom;
```

### 空间查询

```sql
-- 查询距离某点 N 米内的 POI
SELECT *
FROM poi
WHERE ST_DWithin(
    geom::geography,
    ST_SetSRID(ST_MakePoint(116.4, 39.9), 4326)::geography,
    1000  -- 1000米
);

-- 查询在多边形内的 POI
SELECT *
FROM poi
WHERE ST_Within(geom, polygon_geom);

-- 查询与多边形相交的路段
SELECT *
FROM ways
WHERE ST_Intersects(the_geom, polygon_geom);
```

## 步行速度与距离

### 速度参考值

| 步行类型 | 速度 (km/h) | 速度 (m/min) |
|----------|-------------|--------------|
| 慢速步行 | 3.5 | 58.3 |
| 正常步行 | 5.0 | 83.3 |
| 快速步行 | 6.0 | 100.0 |

### 时间-距离换算

```
距离(米) = 速度(km/h) × 时间(分钟) × 1000 / 60

以 5 km/h 为例:
5分钟  = 5 × 5 × 1000 / 60 ≈ 417 米
10分钟 = 5 × 10 × 1000 / 60 ≈ 833 米
15分钟 = 5 × 15 × 1000 / 60 ≈ 1250 米
```

### SQL 中的成本计算

```sql
-- 路段成本 = 长度 / 速度
-- ways.cost 单位为分钟

UPDATE ways 
SET cost = length_m / (5.0 * 1000.0 / 60.0),
    reverse_cost = length_m / (5.0 * 1000.0 / 60.0);
```

## pgRouting 等时圈

### 核心函数: pgr_drivingDistance

```sql
-- 计算从起点出发，指定成本内可达的所有节点
SELECT * FROM pgr_drivingDistance(
    'SELECT id, source, target, cost, reverse_cost FROM ways',
    起点节点ID,
    最大成本,
    directed := false  -- 无向图 (步行可双向)
);
```

### 生成等时圈多边形

```sql
-- 方法1: 凹多边形 (更精确，贴合路网)
WITH reachable AS (
    SELECT node FROM pgr_drivingDistance(...)
)
SELECT ST_ConcaveHull(
    ST_Collect(v.the_geom),
    0.7  -- 凹度参数 (0=凸, 1=完全凹)
) AS isochrone
FROM reachable r
JOIN ways_vertices_pgr v ON r.node = v.id;

-- 方法2: 凸多边形 (简单快速)
SELECT ST_ConvexHull(ST_Collect(v.the_geom))
FROM reachable r
JOIN ways_vertices_pgr v ON r.node = v.id;

-- 方法3: Alpha Shape (需要 PostGIS 3.0+)
SELECT ST_AlphaShape(ST_Collect(v.the_geom), 0.001)
FROM reachable r
JOIN ways_vertices_pgr v ON r.node = v.id;
```

## GeoJSON 输出

```sql
-- 将几何转为 GeoJSON
SELECT ST_AsGeoJSON(geom) AS geojson FROM table;

-- 构建完整的 Feature
SELECT json_build_object(
    'type', 'Feature',
    'geometry', ST_AsGeoJSON(geom)::json,
    'properties', json_build_object(
        'id', id,
        'name', name
    )
) AS feature
FROM table;

-- 构建 FeatureCollection
SELECT json_build_object(
    'type', 'FeatureCollection',
    'features', json_agg(feature)
) AS geojson
FROM (
    SELECT json_build_object(...) AS feature
    FROM table
) t;
```

## 常见问题

### Q: 为什么不直接用圆形缓冲区?

实际步行受路网限制，直线距离和步行距离差异很大。基于路网的等时圈更准确反映真实可达性。

### Q: 计算很慢怎么办?

1. 确保有空间索引: `CREATE INDEX ON table USING GIST(geom);`
2. 减少路网范围: 只加载目标城市的数据
3. 使用缓存: 将常用点的等时圈结果缓存
4. 预计算: 对热点区域预计算等时圈

### Q: SRID 4326 能直接算距离吗?

可以使用 `ST_DistanceSphere` 或转为 `geography` 类型。但要注意:
- geometry 类型的 `ST_Distance` 返回的是度，不是米
- 必须转换后才能用于距离计算
