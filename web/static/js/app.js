/**
 * 15分钟生活圈 - 前端应用
 */

// ============================================
// 配置
// ============================================

const CONFIG = {
    // 默认地图中心 - 浙江杭州
    defaultCenter: [30.2741, 120.1551], // 杭州市中心（西湖附近）
    defaultZoom: 14,
    
    // API 端点
    apiBase: '/api/v1',
    
    // 等时圈样式
    isochroneStyles: {
        5: { color: '#2ecc71', fillColor: '#2ecc71', fillOpacity: 0.3, weight: 2 },
        10: { color: '#3498db', fillColor: '#3498db', fillOpacity: 0.25, weight: 2 },
        15: { color: '#9b59b6', fillColor: '#9b59b6', fillOpacity: 0.2, weight: 2 }
    },
    
    // POI 分类图标
    categoryIcons: {
        medical: '🏥',
        education: '🏫',
        elderly: '👴',
        commerce: '🛒',
        culture: '🎭',
        public: '🏛️',
        transport: '🚌',
        child: '👶'
    },
    
    // POI 分类颜色
    categoryColors: {
        medical: '#e74c3c',
        education: '#3498db',
        elderly: '#e67e22',
        commerce: '#f39c12',
        culture: '#27ae60',
        public: '#9b59b6',
        transport: '#1abc9c',
        child: '#ff69b4'
    }
};

// ============================================
// 应用状态
// ============================================

const state = {
    map: null,
    currentMarker: null,
    isochroneLayer: null,
    poiLayer: null,
    selectedLocation: null
};

// ============================================
// 初始化
// ============================================

document.addEventListener('DOMContentLoaded', () => {
    initMap();
    initEventListeners();
});

/**
 * 初始化地图
 */
function initMap() {
    // 创建地图
    state.map = L.map('map').setView(CONFIG.defaultCenter, CONFIG.defaultZoom);
    
    // 添加底图
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
        maxZoom: 19
    }).addTo(state.map);
    
    // 添加比例尺
    L.control.scale({ imperial: false }).addTo(state.map);
    
    // 初始化图层组
    state.isochroneLayer = L.layerGroup().addTo(state.map);
    state.poiLayer = L.layerGroup().addTo(state.map);
    
    // 地图点击事件
    state.map.on('click', handleMapClick);
}

/**
 * 初始化事件监听
 */
function initEventListeners() {
    // 可以添加其他事件监听器
}

// ============================================
// 地图交互
// ============================================

/**
 * 处理地图点击
 */
async function handleMapClick(e) {
    const { lat, lng } = e.latlng;
    
    // 更新选中位置
    state.selectedLocation = { lat, lng };
    updateLocationDisplay(lat, lng);
    
    // 更新标记
    updateMarker(lat, lng);
    
    // 执行分析
    await analyzePoint(lng, lat);
}

/**
 * 更新位置显示
 */
function updateLocationDisplay(lat, lng) {
    const container = document.getElementById('current-location');
    container.innerHTML = `
        <p><strong>经度:</strong> ${lng.toFixed(6)}</p>
        <p><strong>纬度:</strong> ${lat.toFixed(6)}</p>
    `;
}

/**
 * 更新地图标记
 */
function updateMarker(lat, lng) {
    if (state.currentMarker) {
        state.map.removeLayer(state.currentMarker);
    }
    
    state.currentMarker = L.marker([lat, lng], {
        icon: L.divIcon({
            className: 'custom-marker',
            html: '<div style="background:#e74c3c;width:20px;height:20px;border-radius:50%;border:3px solid white;box-shadow:0 2px 6px rgba(0,0,0,0.3);"></div>',
            iconSize: [20, 20],
            iconAnchor: [10, 10]
        })
    }).addTo(state.map);
}

// ============================================
// API 调用
// ============================================

/**
 * 分析指定点
 */
async function analyzePoint(lng, lat) {
    showLoading(true);
    
    try {
        const response = await fetch(`${CONFIG.apiBase}/analyze`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ lng, lat, time_threshold: 15 })
        });
        
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        
        const result = await response.json();
        
        // 渲染结果
        renderIsochrone(result.isochrone);
        renderPOIs(result.pois);
        renderEvaluationResult(result);
        
    } catch (error) {
        console.error('Analysis failed:', error);
        showError('分析失败，请重试');
        
        // 开发模式：使用模拟数据
        if (window.location.hostname === 'localhost') {
            renderMockResult(lng, lat);
        }
    } finally {
        showLoading(false);
    }
}

// ============================================
// 渲染函数
// ============================================

/**
 * 渲染等时圈
 */
function renderIsochrone(geojson) {
    state.isochroneLayer.clearLayers();
    
    if (!geojson || !geojson.features) return;
    
    geojson.features.forEach(feature => {
        if (feature.properties.type === 'isochrone') {
            const minutes = feature.properties.minutes;
            const style = CONFIG.isochroneStyles[minutes] || CONFIG.isochroneStyles[15];
            
            L.geoJSON(feature, {
                style: () => style
            }).addTo(state.isochroneLayer);
        }
    });
}

/**
 * 渲染 POI
 */
function renderPOIs(geojson) {
    state.poiLayer.clearLayers();
    
    if (!geojson || !geojson.features) return;
    
    geojson.features.forEach(feature => {
        if (feature.properties.type === 'poi') {
            const { category, name, sub_type } = feature.properties;
            const [lng, lat] = feature.geometry.coordinates;
            
            const color = CONFIG.categoryColors[category] || '#666';
            const icon = CONFIG.categoryIcons[category] || '📍';
            
            const marker = L.circleMarker([lat, lng], {
                radius: 6,
                fillColor: color,
                color: '#fff',
                weight: 2,
                fillOpacity: 0.8
            });
            
            marker.bindPopup(`
                <div class="poi-popup">
                    <h4>${icon} ${name || '未命名'}</h4>
                    <p><span class="category-tag">${getCategoryName(category)}</span></p>
                    <p>类型: ${getSubTypeName(sub_type)}</p>
                </div>
            `);
            
            marker.addTo(state.poiLayer);
        }
    });
}

/**
 * 渲染评价结果
 */
function renderEvaluationResult(result) {
    // 显示结果面板
    document.getElementById('result-panel').style.display = 'block';
    
    // 总分
    const scoreEl = document.getElementById('total-score');
    scoreEl.textContent = result.total_score ? result.total_score.toFixed(1) : '--';
    
    // 等级
    const gradeEl = document.getElementById('grade-badge');
    gradeEl.textContent = result.grade || '-';
    gradeEl.className = `grade-badge grade-${result.grade}`;
    
    // 摘要
    document.getElementById('result-summary').textContent = result.summary || '';
    
    // 分类评分
    renderCategoryScores(result.category_scores || []);
    
    // 建议
    renderSuggestions(result.suggestions || []);
}

/**
 * 渲染分类评分
 */
function renderCategoryScores(scores) {
    const container = document.getElementById('category-scores');
    
    container.innerHTML = scores.map(cs => {
        const icon = CONFIG.categoryIcons[cs.category] || '📍';
        const color = CONFIG.categoryColors[cs.category] || '#666';
        const score = cs.score || 0;
        
        return `
            <div class="category-item">
                <span class="category-icon">${icon}</span>
                <div class="category-info">
                    <div class="category-name">${cs.name}</div>
                    <div class="category-bar">
                        <div class="category-bar-fill" style="width: ${score}%; background: ${color};"></div>
                    </div>
                </div>
                <span class="category-score-value">${score.toFixed(0)}</span>
            </div>
        `;
    }).join('');
}

/**
 * 渲染建议
 */
function renderSuggestions(suggestions) {
    const list = document.getElementById('suggestion-list');
    list.innerHTML = suggestions.map(s => `<li>${s}</li>`).join('');
}

// ============================================
// 辅助函数
// ============================================

/**
 * 显示/隐藏加载状态
 */
function showLoading(show) {
    document.getElementById('loading').style.display = show ? 'flex' : 'none';
}

/**
 * 显示错误消息
 */
function showError(message) {
    // 简单的错误提示
    alert(message);
}

/**
 * 获取分类名称
 */
function getCategoryName(code) {
    const names = {
        medical: '医疗卫生',
        education: '教育设施',
        elderly: '养老服务',
        commerce: '商业服务',
        culture: '文化体育',
        public: '公共管理',
        transport: '交通设施',
        child: '托幼托育'
    };
    return names[code] || code;
}

/**
 * 获取子类型名称
 */
function getSubTypeName(code) {
    const names = {
        // 医疗卫生
        community_health: '社区卫生服务中心/站',
        hospital: '医院',
        pharmacy: '药店',
        // 教育设施
        kindergarten: '幼儿园',
        primary: '小学',
        secondary: '初中',
        // 养老服务
        elderly_center: '社区养老服务中心',
        daycare: '日间照料中心',
        elderly_activity: '老年活动室',
        // 商业服务
        market: '菜市场/生鲜超市',
        supermarket: '综合超市',
        convenience: '便利店',
        restaurant: '餐饮服务',
        // 文化体育
        culture_center: '文化活动中心',
        sports_field: '健身场地/球场',
        park: '公园绿地',
        library: '图书室/阅览室',
        // 公共管理
        community_service: '社区服务中心',
        police: '派出所/警务室',
        bank: '银行网点',
        post: '邮政服务',
        // 交通设施
        bus_stop: '公交站点',
        metro: '轨道交通站',
        parking: '公共停车场',
        bike_parking: '非机动车停车',
        // 托幼托育
        nursery: '托儿所/托育机构',
        playground: '儿童游乐设施'
    };
    return names[code] || code;
}

/**
 * 开发模式：模拟结果
 */
function renderMockResult(lng, lat) {
    // 模拟等时圈（简单圆形）
    state.isochroneLayer.clearLayers();
    
    [15, 10, 5].forEach(minutes => {
        const radius = minutes * 83.33; // 约 5km/h 步行速度
        const style = CONFIG.isochroneStyles[minutes];
        
        L.circle([lat, lng], {
            radius: radius,
            ...style
        }).addTo(state.isochroneLayer);
    });
    
    // 模拟评分结果
    const mockResult = {
        total_score: 72.5,
        grade: 'B',
        summary: '良好：生活圈配套较为完善，基本满足日常生活需求',
        category_scores: [
            { category: 'medical', name: '医疗卫生', score: 80, poi_count: 5 },
            { category: 'education', name: '教育设施', score: 75, poi_count: 3 },
            { category: 'commerce', name: '商业服务', score: 85, poi_count: 8 },
            { category: 'culture', name: '文化体育', score: 60, poi_count: 2 },
            { category: 'public', name: '公共服务', score: 70, poi_count: 4 },
            { category: 'transport', name: '交通设施', score: 90, poi_count: 6 },
            { category: 'elderly', name: '养老服务', score: 45, poi_count: 1 }
        ],
        suggestions: [
            '【文化体育】设施覆盖不足（得分60），建议增设相关配套设施',
            '【养老服务】设施覆盖不足（得分45），建议增设相关配套设施'
        ]
    };
    
    renderEvaluationResult(mockResult);
}
