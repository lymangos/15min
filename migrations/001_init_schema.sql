-- ============================================================
-- 15分钟生活圈数据库 Schema
-- PostgreSQL + PostGIS + pgRouting
-- ============================================================

-- 确保扩展已安装
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgrouting;
CREATE EXTENSION IF NOT EXISTS hstore;  -- OSM 数据常用

-- ============================================================
-- 1. 路网相关表（由 osm2pgrouting 自动创建）
-- 这里只是文档说明，实际由 osm2pgrouting 导入
-- ============================================================

-- osm2pgrouting 会创建以下表:
-- ways          - 路网边表
-- ways_vertices_pgr - 路网节点表
-- configuration - 道路类型配置
-- pointsofinterest - POI点（可选）

-- ============================================================
-- 2. POI 兴趣点表
-- ============================================================

CREATE TABLE IF NOT EXISTS poi (
    id BIGSERIAL PRIMARY KEY,
    osm_id BIGINT,                           -- OSM 原始 ID
    name VARCHAR(255),                       -- 名称
    category VARCHAR(50) NOT NULL,           -- 大类代码
    sub_type VARCHAR(50) NOT NULL,           -- 子类代码
    
    -- 空间数据（WGS84 坐标系）
    geom GEOMETRY(Point, 4326) NOT NULL,
    
    -- 地址信息
    address VARCHAR(500),
    
    -- OSM 原始标签（hstore 格式）
    tags HSTORE,
    
    -- 元数据
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_source VARCHAR(50) DEFAULT 'osm'
);

-- 空间索引（关键！）
CREATE INDEX IF NOT EXISTS idx_poi_geom ON poi USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_poi_category ON poi (category);
CREATE INDEX IF NOT EXISTS idx_poi_sub_type ON poi (sub_type);
CREATE INDEX IF NOT EXISTS idx_poi_osm_id ON poi (osm_id);

COMMENT ON TABLE poi IS '兴趣点数据表，存储各类生活服务设施';
COMMENT ON COLUMN poi.geom IS '点位置，使用 SRID 4326 (WGS84)';

-- ============================================================
-- 3. POI 分类表
-- ============================================================

CREATE TABLE IF NOT EXISTS poi_category (
    code VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    weight DECIMAL(3,2) DEFAULT 0.10,       -- 评价权重 (0-1)
    sort_order INT DEFAULT 0,
    icon VARCHAR(50),                        -- 图标标识
    color VARCHAR(7)                         -- 颜色 (如 #FF5733)
);

CREATE TABLE IF NOT EXISTS poi_sub_type (
    code VARCHAR(50) PRIMARY KEY,
    category_code VARCHAR(50) REFERENCES poi_category(code),
    name VARCHAR(100) NOT NULL,
    osm_tags TEXT[],                         -- 匹配的 OSM 标签
    sort_order INT DEFAULT 0
);

-- ============================================================
-- 初始化默认分类数据
-- 参考标准:
--   1. 《城市居住区规划设计标准》GB 50180-2018
--   2. 《社区生活圈规划技术指南》TD/T 1062-2021
--   3. 《浙江省城镇社区生活圈规划导则》(2022)
--   4. 《城市公共服务设施规划标准》GB 50442-2008
-- ============================================================
INSERT INTO poi_category (code, name, description, weight, sort_order, color) VALUES
    -- 基础保障类设施 (权重较高)
    ('medical',   '医疗卫生', '社区卫生服务中心/站、诊所、药店等基层医疗设施', 0.18, 1, '#E74C3C'),
    ('education', '教育设施', '幼儿园、小学、中学等基础教育设施', 0.18, 2, '#3498DB'),
    ('elderly',   '养老服务', '社区养老服务中心、日间照料中心、老年活动室', 0.12, 3, '#E67E22'),
    
    -- 便民服务类设施
    ('commerce',  '商业服务', '菜市场/生鲜超市、综合超市、便利店、餐饮等', 0.15, 4, '#F39C12'),
    ('culture',   '文化体育', '社区文化活动中心、健身场地、公园绿地、阅览室', 0.12, 5, '#27AE60'),
    
    -- 公共服务类设施
    ('public',    '公共管理', '社区服务中心、派出所、银行网点、邮政服务', 0.10, 6, '#9B59B6'),
    ('transport', '交通设施', '公交站点、轨道交通站点、公共停车场、非机动车停车', 0.10, 7, '#1ABC9C'),
    
    -- 特殊服务类
    ('child',     '托幼托育', '托儿所、托育机构、儿童游乐设施', 0.05, 8, '#FF69B4')
ON CONFLICT (code) DO NOTHING;

INSERT INTO poi_sub_type (code, category_code, name, osm_tags, sort_order) VALUES
    -- ============================================================
    -- 医疗卫生 (18%) - 参考 GB 50180-2018 表5.0.2
    -- 15分钟生活圈要求: 社区卫生服务中心 1处
    -- 5-10分钟生活圈要求: 社区卫生服务站、药店
    -- ============================================================
    ('community_health', 'medical', '社区卫生服务中心/站', ARRAY['amenity=clinic', 'amenity=doctors', 'healthcare=centre'], 1),
    ('hospital',    'medical',   '医院',     ARRAY['amenity=hospital'], 2),
    ('pharmacy',    'medical',   '药店',     ARRAY['amenity=pharmacy'], 3),
    
    -- ============================================================
    -- 教育设施 (18%) - 参考 GB 50180-2018 表5.0.2
    -- 15分钟生活圈要求: 幼儿园、小学各1处
    -- ============================================================
    ('kindergarten','education', '幼儿园',   ARRAY['amenity=kindergarten'], 1),
    ('primary',     'education', '小学',     ARRAY['amenity=school'], 2),
    ('secondary',   'education', '初中',     ARRAY['amenity=school'], 3),
    
    -- ============================================================
    -- 养老服务 (12%) - 参考 TD/T 1062-2021 表1
    -- 15分钟生活圈要求: 社区养老服务中心 1处
    -- 5-10分钟生活圈要求: 老年人日间照料中心
    -- ============================================================
    ('elderly_center', 'elderly', '社区养老服务中心', ARRAY['amenity=social_facility', 'social_facility=nursing_home'], 1),
    ('daycare',     'elderly',   '日间照料中心', ARRAY['amenity=social_facility', 'social_facility=day_care'], 2),
    ('elderly_activity', 'elderly', '老年活动室', ARRAY['amenity=community_centre'], 3),
    
    -- ============================================================
    -- 商业服务 (15%) - 参考 GB 50180-2018 表5.0.2
    -- 15分钟生活圈要求: 菜市场或生鲜超市 1处
    -- 5-10分钟生活圈要求: 便利店、综合超市
    -- ============================================================
    ('market',      'commerce',  '菜市场/生鲜超市', ARRAY['amenity=marketplace', 'shop=greengrocer', 'shop=supermarket'], 1),
    ('supermarket', 'commerce',  '综合超市', ARRAY['shop=supermarket', 'shop=department_store'], 2),
    ('convenience', 'commerce',  '便利店',   ARRAY['shop=convenience'], 3),
    ('restaurant',  'commerce',  '餐饮服务', ARRAY['amenity=restaurant', 'amenity=cafe', 'amenity=fast_food'], 4),
    
    -- ============================================================
    -- 文化体育 (12%) - 参考 TD/T 1062-2021 表1
    -- 15分钟生活圈要求: 社区文化活动中心、室外综合健身场地、社区公园
    -- ============================================================
    ('culture_center', 'culture', '文化活动中心', ARRAY['amenity=community_centre', 'amenity=arts_centre'], 1),
    ('sports_field', 'culture',  '健身场地/球场', ARRAY['leisure=pitch', 'leisure=sports_centre', 'leisure=fitness_centre'], 2),
    ('park',        'culture',   '公园绿地', ARRAY['leisure=park', 'leisure=garden'], 3),
    ('library',     'culture',   '图书室/阅览室', ARRAY['amenity=library'], 4),
    
    -- ============================================================
    -- 公共管理 (10%) - 参考 TD/T 1062-2021 表1
    -- ============================================================
    ('community_service', 'public', '社区服务中心', ARRAY['amenity=townhall', 'office=government'], 1),
    ('police',      'public',    '派出所/警务室', ARRAY['amenity=police'], 2),
    ('bank',        'public',    '银行网点', ARRAY['amenity=bank', 'amenity=atm'], 3),
    ('post',        'public',    '邮政服务', ARRAY['amenity=post_office', 'amenity=post_box'], 4),
    
    -- ============================================================
    -- 交通设施 (10%) - 参考 GB 50180-2018
    -- 公交站点服务半径 300-500m
    -- ============================================================
    ('bus_stop',    'transport', '公交站点', ARRAY['highway=bus_stop', 'public_transport=platform'], 1),
    ('metro',       'transport', '轨道交通站', ARRAY['railway=station', 'railway=subway_entrance'], 2),
    ('parking',     'transport', '公共停车场', ARRAY['amenity=parking'], 3),
    ('bike_parking','transport', '非机动车停车', ARRAY['amenity=bicycle_parking'], 4),
    
    -- ============================================================
    -- 托幼托育 (5%) - 参考浙江省标准
    -- ============================================================
    ('nursery',     'child',     '托儿所/托育机构', ARRAY['amenity=childcare', 'amenity=nursery'], 1),
    ('playground',  'child',     '儿童游乐设施', ARRAY['leisure=playground'], 2)
ON CONFLICT (code) DO NOTHING;

-- ============================================================
-- 4. 评价标准表
-- 参考标准:
--   1. 《城市居住区规划设计标准》GB 50180-2018 表5.0.2
--   2. 《社区生活圈规划技术指南》TD/T 1062-2021 表1
--   3. 《浙江省城镇社区生活圈规划导则》(2022)
-- 
-- 千人指标和服务半径换算为设施数量要求
-- 按15分钟生活圈1.5-2万人规模计算
-- ============================================================

CREATE TABLE IF NOT EXISTS evaluation_standard (
    id SERIAL PRIMARY KEY,
    category VARCHAR(50) REFERENCES poi_category(code),
    sub_type VARCHAR(50) REFERENCES poi_sub_type(code),
    
    -- 各时间阈值要求的最少设施数量
    min_count_5 INT DEFAULT 0,               -- 5分钟圈内 (约400m)
    min_count_10 INT DEFAULT 0,              -- 10分钟圈内 (约800m)
    min_count_15 INT DEFAULT 0,              -- 15分钟圈内 (约1200m)
    
    -- 是否为必备设施 (根据 GB 50180-2018 规定的必配设施)
    is_required BOOLEAN DEFAULT FALSE,
    
    -- 评分基础分值
    base_score DECIMAL(5,2) DEFAULT 10,
    
    -- 服务半径要求 (米)
    service_radius INT DEFAULT 1000,
    
    -- 标准来源说明
    source VARCHAR(200) DEFAULT '《城市居住区规划设计标准》GB 50180-2018'
);

-- ============================================================
-- 初始化评价标准
-- 
-- 必配设施 (is_required=TRUE): 根据 GB 50180-2018 表5.0.2
-- - 社区卫生服务站: 十分钟生活圈 ≥1处
-- - 幼儿园: 十五分钟生活圈 ≥1处，服务半径 ≤300m
-- - 小学: 十五分钟生活圈 ≥1处，服务半径 ≤500m
-- - 菜市场/生鲜超市: 十五分钟生活圈 ≥1处
-- - 社区文化活动中心: 十五分钟生活圈 ≥1处
-- - 室外综合健身场地: 十五分钟生活圈 ≥1处
-- ============================================================

INSERT INTO evaluation_standard (category, sub_type, min_count_5, min_count_10, min_count_15, is_required, base_score, service_radius, source) VALUES
    -- ============================================================
    -- 医疗卫生 (权重18%)
    -- GB 50180-2018: 社区卫生服务站 千人指标 30-50㎡
    -- ============================================================
    ('medical', 'community_health', 0, 1, 1, TRUE, 40, 1000, 'GB 50180-2018 表5.0.2'),
    ('medical', 'pharmacy', 1, 2, 3, FALSE, 15, 500, 'TD/T 1062-2021'),
    ('medical', 'hospital', 0, 0, 1, FALSE, 15, 1500, '参考值'),
    
    -- ============================================================
    -- 教育设施 (权重18%)
    -- GB 50180-2018: 幼儿园服务半径 ≤300m，小学 ≤500m
    -- ============================================================
    ('education', 'kindergarten', 0, 1, 1, TRUE, 35, 300, 'GB 50180-2018 表5.0.2'),
    ('education', 'primary', 0, 0, 1, TRUE, 35, 500, 'GB 50180-2018 表5.0.2'),
    ('education', 'secondary', 0, 0, 1, FALSE, 15, 1000, 'GB 50180-2018'),
    
    -- ============================================================
    -- 养老服务 (权重12%)
    -- TD/T 1062-2021: 社区养老服务中心 15分钟 ≥1处
    -- GB 50180-2018: 老年人日间照料中心 十分钟生活圈
    -- ============================================================
    ('elderly', 'elderly_center', 0, 0, 1, TRUE, 35, 1000, 'TD/T 1062-2021 表1'),
    ('elderly', 'daycare', 0, 1, 1, FALSE, 25, 800, 'GB 50180-2018 表5.0.2'),
    ('elderly', 'elderly_activity', 0, 1, 2, FALSE, 15, 500, '浙江省导则'),
    
    -- ============================================================
    -- 商业服务 (权重15%)
    -- GB 50180-2018: 菜市场、生鲜超市 十五分钟生活圈
    -- ============================================================
    ('commerce', 'market', 0, 1, 1, TRUE, 30, 1000, 'GB 50180-2018 表5.0.2'),
    ('commerce', 'supermarket', 0, 1, 2, FALSE, 20, 800, 'TD/T 1062-2021'),
    ('commerce', 'convenience', 1, 2, 4, FALSE, 15, 300, 'TD/T 1062-2021'),
    ('commerce', 'restaurant', 0, 2, 4, FALSE, 10, 500, '参考值'),
    
    -- ============================================================
    -- 文化体育 (权重12%)
    -- TD/T 1062-2021: 社区文化活动中心、健身场地 15分钟必配
    -- GB 50180-2018: 社区公园 服务半径 ≤500m
    -- ============================================================
    ('culture', 'culture_center', 0, 0, 1, TRUE, 25, 1000, 'TD/T 1062-2021 表1'),
    ('culture', 'sports_field', 0, 1, 2, TRUE, 25, 800, 'GB 50180-2018 表5.0.2'),
    ('culture', 'park', 0, 1, 1, TRUE, 25, 500, 'GB 50180-2018 表5.0.2'),
    ('culture', 'library', 0, 0, 1, FALSE, 15, 1000, 'TD/T 1062-2021'),
    
    -- ============================================================
    -- 公共管理 (权重10%)
    -- TD/T 1062-2021: 社区服务中心 15分钟 ≥1处
    -- ============================================================
    ('public', 'community_service', 0, 0, 1, TRUE, 30, 1000, 'TD/T 1062-2021 表1'),
    ('public', 'police', 0, 0, 1, FALSE, 20, 1000, '参考值'),
    ('public', 'bank', 0, 1, 2, FALSE, 15, 800, '参考值'),
    ('public', 'post', 0, 0, 1, FALSE, 10, 1000, '参考值'),
    
    -- ============================================================
    -- 交通设施 (权重10%)
    -- GB 50180-2018: 公交站点服务半径 300-500m
    -- 轨道站点服务半径 500-800m
    -- ============================================================
    ('transport', 'bus_stop', 1, 2, 3, TRUE, 35, 300, 'GB 50180-2018'),
    ('transport', 'metro', 0, 0, 1, FALSE, 25, 800, 'GB 50180-2018'),
    ('transport', 'parking', 0, 1, 2, FALSE, 15, 500, '参考值'),
    ('transport', 'bike_parking', 1, 2, 4, FALSE, 10, 300, '参考值'),
    
    -- ============================================================
    -- 托幼托育 (权重5%)
    -- 浙江省标准: 每千人 2-3 个托位
    -- ============================================================
    ('child', 'nursery', 0, 0, 1, FALSE, 40, 500, '浙江省托育服务标准'),
    ('child', 'playground', 0, 1, 2, FALSE, 30, 300, 'TD/T 1062-2021')
ON CONFLICT DO NOTHING;

-- ============================================================
-- 5. 分析历史记录表（可选，用于缓存/统计）
-- ============================================================

CREATE TABLE IF NOT EXISTS analysis_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- 查询点
    origin GEOMETRY(Point, 4326) NOT NULL,
    lng DECIMAL(10, 7),
    lat DECIMAL(10, 7),
    
    -- 参数
    time_thresholds INT[] DEFAULT ARRAY[5, 10, 15],
    walk_speed DECIMAL(3,1) DEFAULT 5.0,
    
    -- 结果缓存
    total_score DECIMAL(5,2),
    grade CHAR(1),
    result_json JSONB,
    
    -- 等时圈几何缓存
    isochrone_5 GEOMETRY(Polygon, 4326),
    isochrone_10 GEOMETRY(Polygon, 4326),
    isochrone_15 GEOMETRY(Polygon, 4326),
    
    -- 元数据
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ip_address INET,
    user_agent TEXT
);

CREATE INDEX IF NOT EXISTS idx_analysis_origin ON analysis_history USING GIST (origin);
CREATE INDEX IF NOT EXISTS idx_analysis_created ON analysis_history (created_at DESC);

COMMENT ON TABLE analysis_history IS '分析历史记录，用于缓存和统计分析';
