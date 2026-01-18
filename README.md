# 15分钟生活圈 (15-Minute Life Circle)

一个基于 WebGIS 的城市服务可达性分析工具，用于评估城市某一点的"15分钟生活圈"服务覆盖情况。

## 🎯 功能特性

- **等时圈计算**: 基于真实路网计算 5/10/15 分钟步行可达范围
- **POI 统计**: 统计圈内医疗、教育、商业等各类设施
- **综合评分**: 基于城乡规划标准的服务设施覆盖评价
- **可视化展示**: 在地图上直观展示分析结果
- **多城市支持**: 支持杭州、沈阳、诸暨等城市切换
- **高德API补充**: 自动补充高德POI数据，提升数据覆盖

## 🏙️ 支持城市

| 城市 | 覆盖范围 |
|------|----------|
| 杭州 | 主城区 |
| 沈阳 | 核心城区 |
| 诸暨 | 市区 |

## 🛠 技术栈

| 层级 | 技术 |
|------|------|
| 后端 | Go 1.21 + Gin |
| 数据库 | PostgreSQL + PostGIS + pgRouting |
| 前端 | HTML/CSS/JS + Leaflet + ECharts |
| 数据源 | OpenStreetMap + 高德地图API |

## 📁 项目结构

```
15min/
├── cmd/
│   └── server/          # 应用入口
├── internal/
│   ├── api/             # HTTP 处理器
│   ├── config/          # 配置管理
│   ├── database/        # 数据库连接
│   ├── model/           # 数据模型
│   └── service/         # 业务逻辑
├── migrations/          # 数据库迁移脚本
├── scripts/             # 工具脚本
├── web/
│   ├── static/          # 静态资源
│   └── templates/       # HTML 模板
├── data/                # 数据文件 (OSM等)
└── docs/                # 文档
```

## 🚀 快速开始

### 使用 Docker（推荐）

```bash
# 克隆项目
git clone https://github.com/lymangos/15min.git
cd 15min

# 启动服务
docker compose up -d

# 访问 http://localhost:8080
```

### 手动部署

```bash
# 1. 安装 PostgreSQL + PostGIS + pgRouting
sudo apt install postgresql-16 postgresql-16-postgis-3 postgresql-16-pgrouting

# 2. 创建数据库并启用扩展
sudo -u postgres createdb life_circle_15min
sudo -u postgres psql -d life_circle_15min -c "CREATE EXTENSION postgis; CREATE EXTENSION pgrouting;"

# 3. 导入 OSM 数据
osm2pgrouting -f data/hangzhou_subset.osm -d life_circle_15min -U postgres

# 4. 运行迁移脚本
psql -d life_circle_15min -f migrations/001_init_schema.sql
psql -d life_circle_15min -f migrations/002_spatial_functions.sql
psql -d life_circle_15min -f migrations/003_import_osm_poi.sql

# 5. 启动服务器
go run cmd/server/main.go
```

## 🔧 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `SERVER_ADDR` | 服务监听地址 | `:8080` |
| `DB_HOST` | 数据库主机 | `localhost` |
| `DB_PORT` | 数据库端口 | `5432` |
| `DB_NAME` | 数据库名 | `life_circle_15min` |
| `AMAP_KEY` | 高德地图API Key | - |

## 📐 坐标系说明

| 用途 | SRID | 说明 |
|------|------|------|
| 存储 | 4326 (WGS84) | 经纬度坐标，与 OSM 一致 |
| 距离计算 | 投影坐标系 | 使用 `ST_Transform` 转为本地投影 |
| 前端显示 | 4326 | Leaflet/Mapbox 默认使用 |

## 📄 License

MIT License
