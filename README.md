# 15分钟生活圈 (15-Minute Life Circle)

一个基于 WebGIS 的城市服务可达性分析工具，用于评估城市某一点的"15分钟生活圈"服务覆盖情况。

## 🎯 功能特性

- **等时圈计算**: 基于真实路网计算 5/10/15 分钟步行可达范围
- **POI 统计**: 统计圈内医疗、教育、商业等各类设施
- **综合评分**: 基于城乡规划标准的服务设施覆盖评价
- **可视化展示**: 在地图上直观展示分析结果

## 🛠 技术栈

| 层级 | 技术 |
|------|------|
| 后端 | Go + Gin |
| 数据库 | PostgreSQL + PostGIS + pgRouting |
| 前端 | HTML/CSS/JS + Leaflet |
| 数据源 | OpenStreetMap |

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
│   ├── service/         # 业务逻辑
│   └── spatial/         # 空间计算
├── migrations/          # 数据库迁移脚本
├── scripts/             # 工具脚本
├── web/
│   ├── static/          # 静态资源
│   └── templates/       # HTML 模板
├── data/                # 数据文件 (OSM等)
└── docs/                # 文档
```

## 🚀 快速开始

### 1. 环境准备

```bash
# 安装 PostgreSQL + PostGIS + pgRouting
sudo apt update
sudo apt install postgresql-16 postgresql-16-postgis-3 postgresql-16-pgrouting

# 创建数据库
sudo -u postgres createdb life_circle_15min
sudo -u postgres psql -d life_circle_15min -c "CREATE EXTENSION postgis;"
sudo -u postgres psql -d life_circle_15min -c "CREATE EXTENSION pgrouting;"
```

### 2. 导入 OSM 数据

```bash
# 下载 OSM 数据 (以某城市为例)
wget https://download.geofabrik.de/asia/china-latest.osm.pbf

# 使用 osm2pgrouting 导入路网
osm2pgrouting -f your-city.osm -d life_circle_15min -U postgres
```

### 3. 运行应用

```bash
# 运行数据库迁移
go run cmd/migrate/main.go

# 启动服务器
go run cmd/server/main.go
```

## 📐 坐标系说明

| 用途 | SRID | 说明 |
|------|------|------|
| 存储 | 4326 (WGS84) | 经纬度坐标，与 OSM 一致 |
| 距离计算 | 投影坐标系 | 使用 `ST_Transform` 转为本地投影 |
| 前端显示 | 4326 | Leaflet/Mapbox 默认使用 |

## 📄 License

MIT License
