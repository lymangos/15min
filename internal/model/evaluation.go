package model

// EvaluationRequest 综合评价请求
type EvaluationRequest struct {
	// 起点经度
	Lng float64 `json:"lng" binding:"required"`
	// 起点纬度
	Lat float64 `json:"lat" binding:"required"`
	// 时间阈值（默认15分钟）
	TimeThreshold int `json:"time_threshold"`
	// 步行速度（km/h，默认5.0）
	WalkSpeed float64 `json:"walk_speed"`
}

// Validate 验证请求参数
func (r *EvaluationRequest) Validate() {
	if r.TimeThreshold <= 0 {
		r.TimeThreshold = 15
	}
	if r.WalkSpeed <= 0 {
		r.WalkSpeed = 5.0
	}
	// 限制步行速度范围 3.0 - 7.0 km/h
	if r.WalkSpeed < 3.0 {
		r.WalkSpeed = 3.0
	}
	if r.WalkSpeed > 7.0 {
		r.WalkSpeed = 7.0
	}
}

// EvaluationResult 综合评价结果
type EvaluationResult struct {
	// 起点坐标
	Origin Point `json:"origin"`
	// 总体评分 (0-100)
	TotalScore float64 `json:"total_score"`
	// 评价等级: A/B/C/D/E
	Grade string `json:"grade"`
	// 各分类得分
	CategoryScores []CategoryScore `json:"category_scores"`
	// 等时圈 GeoJSON
	Isochrone *FeatureCollection `json:"isochrone"`
	// 圈内 POI
	POIs *FeatureCollection `json:"pois"`
	// 可达道路网络 GeoJSON（可选）
	Roads interface{} `json:"roads,omitempty"`
	// 评价说明
	Summary string `json:"summary"`
	// 改进建议
	Suggestions []string `json:"suggestions"`
}

// CategoryScore 分类评分
type CategoryScore struct {
	Category    string  `json:"category"`
	Name        string  `json:"name"`
	Score       float64 `json:"score"`       // 0-100
	Weight      float64 `json:"weight"`      // 权重
	WeightedScore float64 `json:"weighted_score"` // 加权得分
	POICount    int     `json:"poi_count"`
	HasRequired bool    `json:"has_required"` // 是否满足必备设施
	Details     []SubTypeScore `json:"details"`
}

// SubTypeScore 子类型评分
type SubTypeScore struct {
	SubType  string `json:"sub_type"`
	Name     string `json:"name"`
	Count    int    `json:"count"`
	Required int    `json:"required"` // 标准要求数量
	Score    float64 `json:"score"`
}

// EvaluationStandard 评价标准
// 参考《城市居住区规划设计标准》GB 50180-2018
// 以及各城市15分钟生活圈规划导则
type EvaluationStandard struct {
	Category     string `json:"category"`
	SubType      string `json:"sub_type"`
	// 15分钟圈内要求的最少数量
	MinCount15   int    `json:"min_count_15"`
	// 10分钟圈内要求的最少数量
	MinCount10   int    `json:"min_count_10"`
	// 5分钟圈内要求的最少数量
	MinCount5    int    `json:"min_count_5"`
	// 是否为必备设施
	Required     bool   `json:"required"`
	// 分值基础
	BaseScore    float64 `json:"base_score"`
}

// GetDefaultStandards 返回默认评价标准
// 注意：子类型必须与数据库中 poi 表的 sub_type 字段匹配
func GetDefaultStandards() []EvaluationStandard {
	return []EvaluationStandard{
		// 医疗卫生 (数据库: hospital, pharmacy, clinic, dentist)
		{Category: "medical", SubType: "clinic", MinCount15: 1, MinCount10: 1, MinCount5: 0, Required: true, BaseScore: 30},
		{Category: "medical", SubType: "pharmacy", MinCount15: 2, MinCount10: 1, MinCount5: 1, Required: false, BaseScore: 10},
		{Category: "medical", SubType: "hospital", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: false, BaseScore: 10},
		{Category: "medical", SubType: "dentist", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: false, BaseScore: 5},

		// 教育设施 (数据库: kindergarten, school, college, university, library)
		{Category: "education", SubType: "kindergarten", MinCount15: 1, MinCount10: 1, MinCount5: 0, Required: true, BaseScore: 25},
		{Category: "education", SubType: "school", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: true, BaseScore: 25},
		{Category: "education", SubType: "college", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: false, BaseScore: 10},
		{Category: "education", SubType: "library", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: false, BaseScore: 10},

		// 商业服务 (数据库: supermarket, convenience, marketplace, restaurant, cafe...)
		{Category: "commerce", SubType: "supermarket", MinCount15: 1, MinCount10: 1, MinCount5: 0, Required: true, BaseScore: 20},
		{Category: "commerce", SubType: "convenience", MinCount15: 3, MinCount10: 2, MinCount5: 1, Required: false, BaseScore: 10},
		{Category: "commerce", SubType: "marketplace", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: false, BaseScore: 10},
		{Category: "commerce", SubType: "restaurant", MinCount15: 2, MinCount10: 1, MinCount5: 0, Required: false, BaseScore: 5},

		// 文化体育 (数据库: park, playground, cinema, pitch, garden, sports_centre, fitness_centre, community_centre)
		{Category: "culture", SubType: "park", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: true, BaseScore: 20},
		{Category: "culture", SubType: "playground", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: false, BaseScore: 10},
		{Category: "culture", SubType: "sports_centre", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: false, BaseScore: 10},
		{Category: "culture", SubType: "community_centre", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: false, BaseScore: 10},
		{Category: "culture", SubType: "cinema", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: false, BaseScore: 5},

		// 公共管理 (数据库: police, post_office, townhall)
		{Category: "public", SubType: "police", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: false, BaseScore: 15},
		{Category: "public", SubType: "post_office", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: false, BaseScore: 15},
		{Category: "public", SubType: "townhall", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: false, BaseScore: 20},

		// 交通设施 (数据库: platform, stop_position, station, bus_station, ferry_terminal)
		{Category: "transport", SubType: "platform", MinCount15: 2, MinCount10: 1, MinCount5: 1, Required: true, BaseScore: 15},
		{Category: "transport", SubType: "stop_position", MinCount15: 2, MinCount10: 1, MinCount5: 1, Required: false, BaseScore: 10},
		{Category: "transport", SubType: "station", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: false, BaseScore: 20},
		{Category: "transport", SubType: "bus_station", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: false, BaseScore: 10},

		// 养老服务 (数据库: social_facility)
		{Category: "elderly", SubType: "social_facility", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: false, BaseScore: 25},

		// 托幼托育 (需要高德API补充，数据库无相关数据)
		{Category: "child", SubType: "nursery", MinCount15: 1, MinCount10: 0, MinCount5: 0, Required: false, BaseScore: 25},
	}
}

// GetGrade 根据分数返回等级
func GetGrade(score float64) string {
	switch {
	case score >= 90:
		return "A"
	case score >= 75:
		return "B"
	case score >= 60:
		return "C"
	case score >= 45:
		return "D"
	default:
		return "E"
	}
}

// GetGradeDescription 获取等级描述
func GetGradeDescription(grade string) string {
	descriptions := map[string]string{
		"A": "优秀：15分钟生活圈配套完善，各类设施齐全，居民生活便利度高",
		"B": "良好：生活圈配套较为完善，基本满足日常生活需求",
		"C": "一般：生活圈配套基本满足需求，部分设施有待完善",
		"D": "较差：生活圈配套不足，多项设施缺失，建议重点改善",
		"E": "差：生活圈配套严重不足，急需规划建设",
	}
	return descriptions[grade]
}
