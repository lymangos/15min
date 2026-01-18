/**
 * 15分钟生活圈 - 前端应用
 */

// ============================================
// 城市配置
// ============================================

const CITIES = {
    hangzhou: {
        name: '杭州',
        center: [30.2741, 120.1551],
        zoom: 14,
        bounds: [[30.1, 119.9], [30.5, 120.5]],  // [[南, 西], [北, 东]]
        description: '浙江省杭州市'
    },
    zhuji: {
        name: '诸暨',
        center: [29.85, 120.08],
        zoom: 14,
        bounds: [[29.6, 120.0], [29.9, 120.4]],
        description: '浙江省诸暨市'
    },
    shenyang: {
        name: '沈阳',
        center: [41.80, 123.43],
        zoom: 13,
        bounds: [[41.65, 123.2], [41.95, 123.6]],
        description: '辽宁省沈阳市'
    }
};

// ============================================
// 配置
// ============================================

const CONFIG = {
    // 当前选中的城市
    currentCity: 'hangzhou',
    
    // 默认地图中心 - 使用当前城市
    get defaultCenter() { return CITIES[this.currentCity].center; },
    get defaultZoom() { return CITIES[this.currentCity].zoom; },
    get cityBounds() { return CITIES[this.currentCity].bounds; },
    
    // API 端点
    apiBase: '/api/v1',
    
    // 高德地图 API Key（Web服务）
    // 注意：实际使用时请替换为您自己的 Key
    amapKey: '',  // 留空则使用本地 Nominatim
    
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
    selectedLocation: null,
    // 新增状态
    walkSpeed: 5.0,          // 步行速度 km/h
    categoryFilters: {       // POI 分类筛选状态
        medical: true,
        education: true,
        elderly: true,
        commerce: true,
        culture: true,
        public: true,
        transport: true,
        child: true
    },
    currentPOIs: null,       // 当前 POI 数据缓存
    currentResult: null,     // 当前分析结果缓存
    radarChart: null,        // ECharts 雷达图实例
    cityBoundsRect: null,    // 城市边界矩形
    baseLayers: null,        // 底图图层
    isMobile: false          // 是否移动端
};

// ============================================
// 初始化
// ============================================

document.addEventListener('DOMContentLoaded', () => {
    // 检测移动端
    state.isMobile = window.innerWidth <= 768;
    
    initMap();
    initEventListeners();
    initRadarChart();
    initCitySelector();
    initMobileControls();
});

/**
 * 初始化移动端控制
 */
function initMobileControls() {
    const toggleBtn = document.getElementById('toggle-sidebar');
    const closeBtn = document.getElementById('close-sidebar');
    const sidebar = document.getElementById('sidebar');
    const overlay = document.getElementById('sidebar-overlay');
    const mobileLocateBtn = document.getElementById('mobile-locate-btn');
    
    // 打开侧边栏
    if (toggleBtn) {
        toggleBtn.addEventListener('click', () => {
            sidebar.classList.add('open');
            overlay.classList.add('active');
            document.body.style.overflow = 'hidden';
        });
    }
    
    // 关闭侧边栏
    const closeSidebar = () => {
        sidebar.classList.remove('open');
        overlay.classList.remove('active');
        document.body.style.overflow = '';
    };
    
    if (closeBtn) {
        closeBtn.addEventListener('click', closeSidebar);
    }
    
    if (overlay) {
        overlay.addEventListener('click', closeSidebar);
    }
    
    // 移动端定位按钮
    if (mobileLocateBtn) {
        mobileLocateBtn.addEventListener('click', handleLocate);
    }
    
    // 分析完成后自动关闭侧边栏（移动端）
    window.closeSidebarAfterAnalysis = () => {
        if (state.isMobile && sidebar.classList.contains('open')) {
            closeSidebar();
        }
    };
    
    // 监听窗口大小变化
    window.addEventListener('resize', () => {
        state.isMobile = window.innerWidth <= 768;
        // 桌面端确保侧边栏可见
        if (!state.isMobile) {
            sidebar.classList.remove('open');
            overlay.classList.remove('active');
            document.body.style.overflow = '';
        }
    });
}

/**
 * 初始化地图
 */
function initMap() {
    // 获取城市边界
    const bounds = L.latLngBounds(CONFIG.cityBounds);
    
    // 创建地图，设置边界限制
    state.map = L.map('map', {
        maxBounds: bounds.pad(0.1),  // 稍微扩展边界，让边缘可见
        maxBoundsViscosity: 1.0,     // 完全限制在边界内
        tap: true,                   // 移动端点击支持
        touchZoom: true,             // 触摸缩放
        bounceAtZoomLimits: false    // 缩放限制时不反弹
    }).setView(CONFIG.defaultCenter, CONFIG.defaultZoom);
    
    // 添加底图 - 使用高德瓦片（国内访问更快）
    // 备选：OSM 官方瓦片
    const amapTile = L.tileLayer('https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}', {
        subdomains: ['1', '2', '3', '4'],
        maxZoom: 18,
        attribution: '&copy; 高德地图'
    });
    
    const osmTile = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
        maxZoom: 19
    });
    
    // 默认使用高德瓦片（国内更快）
    amapTile.addTo(state.map);
    
    // 保存瓦片图层引用，方便切换
    state.baseLayers = {
        '高德地图': amapTile,
        'OpenStreetMap': osmTile
    };
    
    // 添加城市边界可视化
    updateCityBoundsRect();
    
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
    // 步行速度滑块
    const speedSlider = document.getElementById('walk-speed');
    if (speedSlider) {
        speedSlider.addEventListener('input', handleSpeedChange);
    }
    
    // 速度预设按钮
    document.querySelectorAll('.speed-preset').forEach(btn => {
        btn.addEventListener('click', handleSpeedPreset);
    });
    
    // POI 筛选复选框
    document.querySelectorAll('#poi-filter-list .filter-checkbox input').forEach(checkbox => {
        checkbox.addEventListener('change', handleCategoryFilter);
    });
    
    // 全选/取消全选
    const filterAll = document.getElementById('filter-all');
    if (filterAll) {
        filterAll.addEventListener('change', handleFilterAll);
    }
    
    // 搜索功能
    const searchInput = document.getElementById('search-input');
    const searchBtn = document.getElementById('search-btn');
    const locateBtn = document.getElementById('locate-btn');
    
    if (searchInput) {
        // 输入时搜索建议
        let searchTimeout;
        searchInput.addEventListener('input', (e) => {
            clearTimeout(searchTimeout);
            searchTimeout = setTimeout(() => {
                handleSearchInput(e.target.value);
            }, 300);
        });
        
        // 回车搜索
        searchInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                handleSearch(searchInput.value);
            }
        });
        
        // 点击其他地方关闭搜索结果
        document.addEventListener('click', (e) => {
            if (!e.target.closest('#search-panel')) {
                hideSearchResults();
            }
        });
    }
    
    if (searchBtn) {
        searchBtn.addEventListener('click', () => {
            handleSearch(document.getElementById('search-input').value);
        });
    }
    
    if (locateBtn) {
        locateBtn.addEventListener('click', handleLocate);
    }
}

// ============================================
// 地址搜索功能
// ============================================

/**
 * 处理搜索输入（显示建议）
 */
async function handleSearchInput(query) {
    if (!query || query.length < 2) {
        hideSearchResults();
        return;
    }
    
    try {
        const results = await searchAddress(query);
        showSearchResults(results);
    } catch (error) {
        console.error('Search failed:', error);
    }
}

/**
 * 执行搜索
 */
async function handleSearch(query) {
    if (!query) return;
    
    try {
        const results = await searchAddress(query);
        if (results.length > 0) {
            // 选择第一个结果
            selectSearchResult(results[0]);
        } else {
            showToast('未找到相关地址', 'error');
        }
    } catch (error) {
        console.error('Search failed:', error);
        showToast('搜索失败，请重试', 'error');
    }
}

/**
 * 搜索地址（使用 Nominatim 免费 API）
 */
async function searchAddress(query) {
    // 使用 OpenStreetMap Nominatim API（免费，无需 Key）
    const url = `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(query)}&countrycodes=cn&limit=5&addressdetails=1`;
    
    const response = await fetch(url, {
        headers: {
            'Accept-Language': 'zh-CN,zh'
        }
    });
    
    if (!response.ok) {
        throw new Error('Search API failed');
    }
    
    const data = await response.json();
    
    return data.map(item => ({
        name: item.display_name.split(',')[0],
        address: item.display_name,
        lat: parseFloat(item.lat),
        lng: parseFloat(item.lon)
    }));
}

/**
 * 显示搜索结果
 */
function showSearchResults(results) {
    const container = document.getElementById('search-results');
    
    if (!results || results.length === 0) {
        container.style.display = 'none';
        return;
    }
    
    container.innerHTML = results.map((r, i) => `
        <div class="search-result-item" data-index="${i}">
            <div class="name">${r.name}</div>
            <div class="address">${r.address}</div>
        </div>
    `).join('');
    
    // 添加点击事件
    container.querySelectorAll('.search-result-item').forEach((item, i) => {
        item.addEventListener('click', () => {
            selectSearchResult(results[i]);
        });
    });
    
    container.style.display = 'block';
}

/**
 * 隐藏搜索结果
 */
function hideSearchResults() {
    const container = document.getElementById('search-results');
    if (container) {
        container.style.display = 'none';
    }
}

/**
 * 选择搜索结果
 */
function selectSearchResult(result) {
    hideSearchResults();
    document.getElementById('search-input').value = result.name;
    
    // 跳转到该位置
    state.map.setView([result.lat, result.lng], 16);
    
    // 更新状态并分析
    state.selectedLocation = { lat: result.lat, lng: result.lng };
    updateLocationDisplay(result.lat, result.lng);
    updateMarker(result.lat, result.lng);
    analyzePoint(result.lng, result.lat);
    
    showToast(`已定位到: ${result.name}`, 'success');
}

// ============================================
// 当前位置定位
// ============================================

/**
 * 处理定位按钮点击
 */
function handleLocate() {
    const locateBtn = document.getElementById('locate-btn');
    
    if (!navigator.geolocation) {
        showToast('您的浏览器不支持定位功能', 'error');
        return;
    }
    
    // 显示定位中状态
    locateBtn.classList.add('locating');
    locateBtn.textContent = '⏳';
    
    navigator.geolocation.getCurrentPosition(
        (position) => {
            const { latitude, longitude } = position.coords;
            
            // 恢复按钮状态
            locateBtn.classList.remove('locating');
            locateBtn.textContent = '📍';
            
            // 跳转到当前位置
            state.map.setView([latitude, longitude], 16);
            
            // 更新状态并分析
            state.selectedLocation = { lat: latitude, lng: longitude };
            updateLocationDisplay(latitude, longitude);
            updateMarker(latitude, longitude);
            analyzePoint(longitude, latitude);
            
            showToast('已定位到当前位置', 'success');
        },
        (error) => {
            // 恢复按钮状态
            locateBtn.classList.remove('locating');
            locateBtn.textContent = '📍';
            
            let message = '定位失败';
            switch (error.code) {
                case error.PERMISSION_DENIED:
                    message = '定位权限被拒绝，请在浏览器设置中允许';
                    break;
                case error.POSITION_UNAVAILABLE:
                    message = '无法获取位置信息';
                    break;
                case error.TIMEOUT:
                    message = '定位超时，请重试';
                    break;
            }
            showToast(message, 'error');
        },
        {
            enableHighAccuracy: true,
            timeout: 10000,
            maximumAge: 60000
        }
    );
}

// ============================================
// Toast 提示
// ============================================

/**
 * 显示 Toast 提示
 */
function showToast(message, type = 'info') {
    // 移除现有的 toast
    const existing = document.querySelector('.toast');
    if (existing) {
        existing.remove();
    }
    
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.textContent = message;
    document.body.appendChild(toast);
    
    // 3秒后自动消失
    setTimeout(() => {
        toast.remove();
    }, 3000);
}

/**
 * 处理步行速度变化
 */
function handleSpeedChange(e) {
    const speed = parseFloat(e.target.value);
    state.walkSpeed = speed;
    
    // 更新显示
    document.getElementById('speed-display').textContent = speed.toFixed(1);
    
    // 计算15分钟步行距离
    const distance = Math.round(speed * 1000 / 60 * 15);
    document.getElementById('walk-distance').textContent = distance;
    
    // 更新预设按钮状态
    document.querySelectorAll('.speed-preset').forEach(btn => {
        btn.classList.remove('active');
        if (parseFloat(btn.dataset.speed) === speed) {
            btn.classList.add('active');
        }
    });
}

/**
 * 处理速度预设按钮点击
 */
function handleSpeedPreset(e) {
    const speed = parseFloat(e.target.dataset.speed);
    state.walkSpeed = speed;
    
    // 更新滑块
    const slider = document.getElementById('walk-speed');
    slider.value = speed;
    
    // 更新显示
    document.getElementById('speed-display').textContent = speed.toFixed(1);
    const distance = Math.round(speed * 1000 / 60 * 15);
    document.getElementById('walk-distance').textContent = distance;
    
    // 更新按钮状态
    document.querySelectorAll('.speed-preset').forEach(btn => {
        btn.classList.remove('active');
    });
    e.target.classList.add('active');
}

/**
 * 处理 POI 分类筛选
 */
function handleCategoryFilter(e) {
    const checkbox = e.target;
    const label = checkbox.closest('.filter-checkbox');
    const category = label.dataset.category;
    
    if (category) {
        state.categoryFilters[category] = checkbox.checked;
        
        // 重新渲染 POI（使用缓存数据）
        if (state.currentPOIs) {
            renderPOIs(state.currentPOIs);
        }
        
        // 更新全选复选框状态
        updateFilterAllCheckbox();
    }
}

/**
 * 处理全选/取消全选
 */
function handleFilterAll(e) {
    const checked = e.target.checked;
    
    // 更新所有分类筛选状态
    Object.keys(state.categoryFilters).forEach(cat => {
        state.categoryFilters[cat] = checked;
    });
    
    // 更新所有复选框
    document.querySelectorAll('#poi-filter-list .filter-checkbox input').forEach(checkbox => {
        checkbox.checked = checked;
    });
    
    // 重新渲染 POI
    if (state.currentPOIs) {
        renderPOIs(state.currentPOIs);
    }
}

/**
 * 更新全选复选框状态
 */
function updateFilterAllCheckbox() {
    const allChecked = Object.values(state.categoryFilters).every(v => v);
    const noneChecked = Object.values(state.categoryFilters).every(v => !v);
    const filterAllCheckbox = document.getElementById('filter-all');
    
    if (filterAllCheckbox) {
        filterAllCheckbox.checked = allChecked;
        filterAllCheckbox.indeterminate = !allChecked && !noneChecked;
    }
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
            body: JSON.stringify({ 
                lng, 
                lat, 
                time_threshold: 15,
                walk_speed: state.walkSpeed  // 使用用户配置的速度
            })
        });
        
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        
        const result = await response.json();
        
        // 缓存 POI 数据
        state.currentPOIs = result.pois;
        
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
 * 渲染 POI（支持分类筛选）
 */
function renderPOIs(geojson) {
    state.poiLayer.clearLayers();
    
    if (!geojson || !geojson.features) return;
    
    geojson.features.forEach(feature => {
        if (feature.properties.type === 'poi') {
            const { category, name, sub_type } = feature.properties;
            
            // 检查该分类是否被筛选显示
            if (!state.categoryFilters[category]) {
                return; // 跳过被隐藏的分类
            }
            
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
            
            // 计算距离和步行时间
            let distanceHtml = '';
            if (state.selectedLocation) {
                const distance = calculateDistance(
                    state.selectedLocation.lat, 
                    state.selectedLocation.lng, 
                    lat, lng
                );
                const walkTime = (distance / (state.walkSpeed * 1000 / 60)).toFixed(1);
                distanceHtml = `
                    <div class="poi-distance">
                        <span class="distance-value">${Math.round(distance)}米</span>
                        <span class="walk-time">🚶 约${walkTime}分钟</span>
                    </div>
                `;
            }
            
            // 改进的 POI 详情卡片
            marker.bindPopup(`
                <div class="poi-popup">
                    <div class="poi-popup-header" style="background: linear-gradient(135deg, ${color}, ${adjustColor(color, -20)});">
                        <h4>
                            <span class="poi-icon">${icon}</span>
                            ${name || '未命名设施'}
                        </h4>
                    </div>
                    <div class="poi-popup-body">
                        <span class="poi-category" style="background: ${color};">${getCategoryName(category)}</span>
                        <div class="poi-info">
                            <div class="poi-info-item">
                                <span class="label">类型</span>
                                <span class="value">${getSubTypeName(sub_type)}</span>
                            </div>
                            <div class="poi-info-item">
                                <span class="label">坐标</span>
                                <span class="value">${lng.toFixed(4)}, ${lat.toFixed(4)}</span>
                            </div>
                        </div>
                        ${distanceHtml}
                    </div>
                </div>
            `, { maxWidth: 280 });
            
            marker.addTo(state.poiLayer);
        }
    });
    
    // 更新 POI 计数显示
    updatePOICount();
}

/**
 * 调整颜色深浅
 */
function adjustColor(color, amount) {
    const hex = color.replace('#', '');
    const num = parseInt(hex, 16);
    const r = Math.min(255, Math.max(0, (num >> 16) + amount));
    const g = Math.min(255, Math.max(0, ((num >> 8) & 0x00FF) + amount));
    const b = Math.min(255, Math.max(0, (num & 0x0000FF) + amount));
    return `#${(1 << 24 | r << 16 | g << 8 | b).toString(16).slice(1)}`;
}

/**
 * 更新 POI 计数显示
 */
function updatePOICount() {
    let visibleCount = 0;
    state.poiLayer.eachLayer(() => visibleCount++);
    
    // 如果有计数显示元素，更新它
    const countEl = document.getElementById('poi-count');
    if (countEl) {
        countEl.textContent = visibleCount;
    }
}

/**
 * 计算两点间距离（米）
 */
function calculateDistance(lat1, lng1, lat2, lng2) {
    const R = 6371000; // 地球半径（米）
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLng = (lng2 - lng1) * Math.PI / 180;
    const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
              Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
              Math.sin(dLng/2) * Math.sin(dLng/2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    return R * c;
}

/**
 * 渲染评价结果
 */
function renderEvaluationResult(result) {
    // 缓存结果（用于导出）
    state.currentResult = result;
    
    // 显示结果面板
    document.getElementById('result-panel').style.display = 'block';
    
    // 移动端：分析完成后自动关闭侧边栏，让用户看到地图
    if (typeof window.closeSidebarAfterAnalysis === 'function') {
        window.closeSidebarAfterAnalysis();
    }
    
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
    
    // 渲染雷达图
    renderRadarChart(result.category_scores || []);
    
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
            { category: 'elderly', name: '养老服务', score: 45, poi_count: 1 },
            { category: 'child', name: '托幼托育', score: 55, poi_count: 2 }
        ],
        suggestions: [
            '【文化体育】设施覆盖不足（得分60），建议增设相关配套设施',
            '【养老服务】设施覆盖不足（得分45），建议增设相关配套设施'
        ]
    };
    
    renderEvaluationResult(mockResult);
}

// ============================================
// 雷达图功能
// ============================================

/**
 * 初始化雷达图
 */
function initRadarChart() {
    const chartDom = document.getElementById('radar-chart');
    if (chartDom && typeof echarts !== 'undefined') {
        // 确保容器有正确尺寸后再初始化
        setTimeout(() => {
            state.radarChart = echarts.init(chartDom);
            
            // 监听窗口大小变化
            window.addEventListener('resize', () => {
                if (state.radarChart) {
                    state.radarChart.resize();
                }
            });
        }, 100);
    }
}

/**
 * 渲染雷达图
 */
function renderRadarChart(categoryScores) {
    // 如果图表未初始化，延迟重试
    if (!state.radarChart) {
        const chartDom = document.getElementById('radar-chart');
        if (chartDom && typeof echarts !== 'undefined') {
            state.radarChart = echarts.init(chartDom);
        } else {
            return;
        }
    }
    
    if (!categoryScores || categoryScores.length === 0) {
        return;
    }
    
    // 强制重新计算尺寸
    state.radarChart.resize();
    
    // 分类名称简称映射
    const shortNames = {
        '医疗卫生': '医疗',
        '教育设施': '教育',
        '养老服务': '养老',
        '商业服务': '商服',
        '文化体育': '文体',
        '公共管理': '公管',
        '交通设施': '交通',
        '托幼托育': '幼托'
    };
    
    // 准备雷达图数据 - 黑白专业风格，使用简称
    const indicators = categoryScores.map(cs => ({
        name: shortNames[cs.name] || cs.name,
        max: 100
    }));
    
    const values = categoryScores.map(cs => cs.score || 0);
    
    // 雷达图配置 - 黑白专业风格
    const option = {
        tooltip: {
            trigger: 'item',
            backgroundColor: 'rgba(50, 50, 50, 0.9)',
            borderColor: '#333',
            textStyle: {
                color: '#fff'
            },
            formatter: function(params) {
                let result = `<strong>各类设施评分</strong><br/>`;
                categoryScores.forEach((cs, i) => {
                    result += `${cs.name}: <strong>${values[i].toFixed(0)}</strong>分<br/>`;
                });
                return result;
            }
        },
        radar: {
            center: ['50%', '50%'],
            radius: '60%',
            indicator: indicators,
            shape: 'polygon',
            splitNumber: 4,
            axisName: {
                color: '#333',
                fontSize: 13,
                fontWeight: 'bold',
                fontWeight: 'normal',
                padding: [3, 5]
            },
            splitLine: {
                lineStyle: {
                    color: '#ccc',
                    width: 1
                }
            },
            splitArea: {
                show: true,
                areaStyle: {
                    color: ['#fff', '#f5f5f5', '#fff', '#f5f5f5']
                }
            },
            axisLine: {
                lineStyle: {
                    color: '#bbb'
                }
            }
        },
        series: [{
            name: '生活圈评分',
            type: 'radar',
            data: [{
                value: values,
                name: '评分',
                symbol: 'circle',
                symbolSize: 5,
                lineStyle: {
                    color: '#333',
                    width: 2
                },
                areaStyle: {
                    color: 'rgba(100, 100, 100, 0.2)'
                },
                itemStyle: {
                    color: '#333',
                    borderColor: '#fff',
                    borderWidth: 2
                }
            }]
        }]
    };
    
    state.radarChart.setOption(option, true);
}

// ============================================
// 辅助函数
// ============================================

/**
 * 获取雷达图两字简称
 */
function getRadarShortName(name) {
    const shortNames = {
        '医疗卫生': '医疗',
        '教育设施': '教育',
        '养老服务': '养老',
        '商业服务': '商服',
        '文化体育': '文体',
        '公共管理': '公管',
        '交通设施': '交通',
        '托幼托育': '幼托'
    };
    return shortNames[name] || name;
}

// ============================================
// 城市选择器
// ============================================

/**
 * 初始化城市选择器
 */
function initCitySelector() {
    const selector = document.getElementById('city-selector');
    if (!selector) return;
    
    // 填充城市选项
    selector.innerHTML = Object.entries(CITIES).map(([key, city]) => 
        `<option value="${key}" ${key === CONFIG.currentCity ? 'selected' : ''}>${city.name}</option>`
    ).join('');
    
    // 监听切换事件
    selector.addEventListener('change', (e) => {
        switchCity(e.target.value);
    });
    
    // 更新城市信息显示
    updateCityInfo();
}

/**
 * 切换城市
 */
function switchCity(cityKey) {
    if (!CITIES[cityKey]) return;
    
    CONFIG.currentCity = cityKey;
    const city = CITIES[cityKey];
    
    // 清除当前分析结果
    clearAnalysis();
    
    // 更新地图视图和边界
    const bounds = L.latLngBounds(city.bounds);
    state.map.setMaxBounds(bounds.pad(0.1));
    state.map.flyTo(city.center, city.zoom);
    
    // 更新边界矩形
    updateCityBoundsRect();
    
    // 更新城市信息
    updateCityInfo();
    
    console.log(`已切换到：${city.name}`);
}

/**
 * 更新城市边界矩形显示
 */
function updateCityBoundsRect() {
    // 移除旧的边界
    if (state.cityBoundsRect) {
        state.map.removeLayer(state.cityBoundsRect);
    }
    
    const bounds = CONFIG.cityBounds;
    state.cityBoundsRect = L.rectangle(bounds, {
        color: '#3498db',
        weight: 2,
        fillOpacity: 0,
        dashArray: '5, 5',
        interactive: false
    }).addTo(state.map);
}

/**
 * 更新城市信息显示
 */
function updateCityInfo() {
    const city = CITIES[CONFIG.currentCity];
    const infoEl = document.getElementById('city-info');
    if (infoEl) {
        infoEl.textContent = city.description;
    }
}

/**
 * 清除分析结果
 */
function clearAnalysis() {
    // 清除标记
    if (state.currentMarker) {
        state.map.removeLayer(state.currentMarker);
        state.currentMarker = null;
    }
    
    // 清除图层
    state.isochroneLayer.clearLayers();
    state.poiLayer.clearLayers();
    
    // 重置状态
    state.selectedLocation = null;
    state.currentPOIs = null;
    state.currentResult = null;
    
    // 隐藏结果面板
    document.getElementById('result-panel').style.display = 'none';
    document.getElementById('current-location').innerHTML = '<p class="placeholder">请在地图上点击选择位置</p>';
}
