# 15分钟生活圈系统 - 功能开发路线图

> 最后更新：2026-01-18

## 📋 功能清单总览

| 序号 | 功能 | 阶段 | 状态 |
|------|------|------|------|
| 1 | POI分类筛选开关 | 第一阶段 | ⏳ 待开发 |
| 2 | 步行速度自定义 | 第一阶段 | ⏳ 待开发 |
| 3 | 地址搜索定位 | 第二阶段 | ⏳ 待开发 |
| 4 | 当前位置定位 | 第二阶段 | ⏳ 待开发 |
| 5 | POI详情卡片 | 第二阶段 | ⏳ 待开发 |
| 6 | 评分雷达图 | 第三阶段 | ⏳ 待开发 |
| 7 | 导出报告 | 第三阶段 | ⏳ 待开发 |
| 8 | POI数据补充（地图API） | 第四阶段 | ⏳ 待开发 |

---

## 🚀 第一阶段：基础交互优化

**目标**：提升基本使用体验，让用户能自定义分析参数

### 1.1 POI分类筛选开关

**需求描述**：
- 在地图右侧或左侧面板添加POI分类复选框
- 用户可以勾选/取消勾选各个类别（交通设施、文化体育、商业服务等8类）
- 实时更新地图上显示的POI点
- 默认全部勾选

**技术要点**：
- 前端：在侧边栏添加复选框组件
- 前端：按分类过滤POI图层显示
- 不需要后端改动，纯前端筛选

**涉及文件**：
- `web/static/js/app.js` - 添加筛选逻辑
- `web/static/css/style.css` - 筛选面板样式
- `web/templates/index.html` - 添加筛选UI

### 1.2 步行速度自定义

**需求描述**：
- 在左侧面板底部显示当前步行速度（默认5.0 km/h）
- 提供滑块或下拉框让用户调整速度（范围：3.0-7.0 km/h）
- 速度预设：老人(3.5)、普通(5.0)、快步(6.0)
- 修改速度后，下次点击地图使用新速度计算

**技术要点**：
- 前端：添加速度配置UI组件
- 前端：将速度参数传递给分析API
- 后端：API已支持速度参数，无需改动

**涉及文件**：
- `web/static/js/app.js` - 速度参数处理
- `web/static/css/style.css` - 配置面板样式
- `web/templates/index.html` - 速度配置UI

---

## 🚀 第二阶段：定位与交互增强

**目标**：优化用户找点、查看POI的体验

### 2.1 地址搜索定位

**需求描述**：
- 在地图上方添加搜索框
- 输入地址/POI名称，显示搜索建议
- 选择结果后地图跳转到该位置并自动分析

**技术要点**：
- 集成高德地图Web服务API（输入提示 + 地理编码）
- 需要申请高德API Key
- 前端调用高德API获取位置

**涉及文件**：
- `web/static/js/app.js` - 搜索逻辑
- `web/templates/index.html` - 搜索框UI
- `internal/config/config.go` - API Key配置（可选）

**API参考**：
- 高德输入提示API：https://lbs.amap.com/api/webservice/guide/api/inputtips
- 高德地理编码API：https://lbs.amap.com/api/webservice/guide/api/georegeo

### 2.2 当前位置定位

**需求描述**：
- 地图右上角添加"我的位置"按钮
- 点击后获取用户GPS位置
- 跳转到用户位置并自动分析

**技术要点**：
- 使用浏览器 Geolocation API
- 需要HTTPS才能使用（本地localhost可用）
- 添加定位失败提示

**涉及文件**：
- `web/static/js/app.js` - 定位逻辑
- `web/static/css/style.css` - 按钮样式

### 2.3 POI详情卡片

**需求描述**：
- 点击地图上的POI点，弹出详情卡片
- 显示：名称、类别、子类型、距离、步行时间
- 卡片可关闭

**技术要点**：
- 使用Leaflet Popup或自定义弹窗
- POI属性已包含在GeoJSON中

**涉及文件**：
- `web/static/js/app.js` - POI点击事件处理
- `web/static/css/style.css` - 卡片样式

---

## 🚀 第三阶段：可视化与导出

**目标**：增强数据可视化，支持结果导出

### 3.1 评分雷达图

**需求描述**：
- 在评分结果区域显示雷达图
- 8个维度对应8个POI分类
- 直观展示各类别得分分布

**技术要点**：
- 使用 Chart.js 或 ECharts 绑定雷达图
- 动态更新图表数据

**涉及文件**：
- `web/static/js/app.js` - 图表渲染逻辑
- `web/templates/index.html` - 引入图表库、添加图表容器
- `web/static/css/style.css` - 图表区域样式

**库选择**：
- 推荐 ECharts（功能强大，中文文档好）
- 或 Chart.js（轻量，易上手）

### 3.2 导出报告

**需求描述**：
- 添加"导出报告"按钮
- 生成包含以下内容的PDF/图片：
  - 地图截图（带等时圈和POI）
  - 评分雷达图
  - 详细评分表格
  - 改进建议

**技术要点**：
- 使用 html2canvas 截取地图和图表
- 使用 jsPDF 生成PDF
- 或直接导出PNG图片

**涉及文件**：
- `web/static/js/app.js` - 导出逻辑
- `web/templates/index.html` - 引入导出库、添加导出按钮

**库选择**：
- html2canvas：截图
- jsPDF：生成PDF
- 或 dom-to-image：更好的截图质量

---

## 🚀 第四阶段：POI数据补充

**目标**：通过第三方地图API补充更丰富的POI数据

### 4.1 POI数据补充

**需求描述**：
- 在用户点击分析时，同时调用高德POI搜索API
- 补充OSM数据中缺失的POI（如托育机构、养老院等）
- 合并本地数据和API数据

**技术要点**：
- 高德POI搜索API（周边搜索）
- 需要处理数据去重
- 考虑API调用频率限制

**API选择对比**：

| 特性 | 高德 | 百度 |
|------|------|------|
| 免费配额 | 5000次/天 | 5000次/天 |
| POI类别 | 更细致 | 较粗略 |
| 文档质量 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| 数据准确性 | 高 | 高 |
| 推荐 | ✅ 推荐 | 备选 |

**涉及文件**：
- `internal/service/poi_external.go` - 新建，外部API调用
- `internal/api/handler.go` - 整合外部POI
- `internal/config/config.go` - API Key配置

**高德API参考**：
- 周边搜索：https://lbs.amap.com/api/webservice/guide/api/search#around
- POI类型编码：https://lbs.amap.com/api/webservice/download

---

## 📁 项目结构参考

```
/data/15min/
├── cmd/server/main.go          # 入口
├── internal/
│   ├── api/handler.go          # API处理器
│   ├── config/config.go        # 配置（含API Key）
│   ├── service/
│   │   ├── evaluation.go       # 评价服务
│   │   ├── isochrone.go        # 等时圈服务
│   │   ├── poi.go              # POI服务
│   │   └── poi_external.go     # 【新增】外部POI服务
│   └── ...
├── web/
│   ├── static/
│   │   ├── css/style.css       # 样式
│   │   └── js/app.js           # 前端逻辑
│   └── templates/index.html    # 页面模板
├── docs/
│   └── ROADMAP.md              # 本文档
└── docker-compose.yml
```

---

## 🔑 需要准备的资源

### 高德地图API Key

1. 访问 https://console.amap.com/
2. 注册/登录开发者账号
3. 创建应用，获取Web服务API Key
4. 配置到项目中

---

## 📝 开发约定

1. **每个阶段独立可用**：完成一个阶段后系统应该可以正常运行
2. **向后兼容**：新功能不影响现有功能
3. **代码注释**：关键逻辑添加中文注释
4. **Git提交**：每完成一个功能点提交一次

---

## 🏷️ 版本规划

| 版本 | 对应阶段 | 计划完成 |
|------|----------|----------|
| v1.1 | 第一阶段 | - |
| v1.2 | 第二阶段 | - |
| v1.3 | 第三阶段 | - |
| v1.4 | 第四阶段 | - |

---

## ✅ 完成检查清单

### 第一阶段
- [x] POI分类筛选开关
- [x] 步行速度自定义

### 第二阶段
- [ ] 地址搜索定位
- [ ] 当前位置定位
- [ ] POI详情卡片

### 第三阶段
- [ ] 评分雷达图
- [ ] 导出报告

### 第四阶段
- [ ] 高德API Key配置
- [ ] POI数据补充接口
- [ ] 数据合并去重
