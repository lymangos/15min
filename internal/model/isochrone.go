package model

// IsochroneRequest 等时圈计算请求
type IsochroneRequest struct {
	// 起点经度
	Lng float64 `json:"lng" binding:"required"`
	// 起点纬度
	Lat float64 `json:"lat" binding:"required"`
	// 时间阈值（分钟），默认 [5, 10, 15]
	TimeThresholds []int `json:"time_thresholds"`
	// 步行速度 (km/h)，默认 5
	WalkSpeed float64 `json:"walk_speed"`
}

// Validate 验证请求参数
func (r *IsochroneRequest) Validate() {
	if len(r.TimeThresholds) == 0 {
		r.TimeThresholds = []int{5, 10, 15}
	}
	if r.WalkSpeed <= 0 {
		r.WalkSpeed = 5.0 // 默认步行速度 5 km/h
	}
}

// MaxDistanceMeters 计算最大距离（米）
func (r *IsochroneRequest) MaxDistanceMeters() float64 {
	maxTime := 0
	for _, t := range r.TimeThresholds {
		if t > maxTime {
			maxTime = t
		}
	}
	// 距离 = 速度 * 时间
	// km/h * min * 1000 / 60 = meters
	return r.WalkSpeed * float64(maxTime) * 1000.0 / 60.0
}

// DistanceForTime 计算指定时间对应的距离（米）
func (r *IsochroneRequest) DistanceForTime(minutes int) float64 {
	return r.WalkSpeed * float64(minutes) * 1000.0 / 60.0
}

// IsochroneResult 等时圈计算结果
type IsochroneResult struct {
	// 起点坐标
	Origin Point `json:"origin"`
	// 各时间阈值对应的多边形（GeoJSON）
	Polygons []IsochronePolygon `json:"polygons"`
}

// IsochronePolygon 单个等时圈多边形
type IsochronePolygon struct {
	// 时间阈值（分钟）
	Minutes int `json:"minutes"`
	// 对应的最大距离（米）
	Distance float64 `json:"distance"`
	// GeoJSON 几何
	Geometry Geometry `json:"geometry"`
}
