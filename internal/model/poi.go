package model

// POI 兴趣点
type POI struct {
	ID         int64    `json:"id"`
	Name       string   `json:"name"`
	Category   string   `json:"category"`   // 大类：医疗、教育、商业等
	SubType    string   `json:"sub_type"`   // 小类：医院、诊所、药店等
	Lng        float64  `json:"lng"`
	Lat        float64  `json:"lat"`
	Address    string   `json:"address,omitempty"`
	Tags       []string `json:"tags,omitempty"`
	Source     string   `json:"source,omitempty"` // 数据来源：osm、amap
}

// POICategory POI 分类（基于城乡规划标准）
type POICategory struct {
	Code        string        `json:"code"`
	Name        string        `json:"name"`
	Description string        `json:"description"`
	SubTypes    []POISubType  `json:"sub_types"`
	Weight      float64       `json:"weight"` // 评价权重
}

// POISubType POI 子类型
type POISubType struct {
	Code   string `json:"code"`
	Name   string `json:"name"`
	OSMTag string `json:"osm_tag"` // 对应 OSM 标签
}

// POIStatistics POI 统计结果
type POIStatistics struct {
	Category     string `json:"category"`
	SubType      string `json:"sub_type"`
	Count        int    `json:"count"`
	// 在不同等时圈内的数量
	CountByTime  map[int]int `json:"count_by_time"`
}

// POIQueryResult POI 查询结果
type POIQueryResult struct {
	POIs       []POI           `json:"pois"`
	Statistics []POIStatistics `json:"statistics"`
	Total      int             `json:"total"`
}

// GetDefaultCategories 返回默认的 POI 分类体系
// 参考标准:
//   - 《城市居住区规划设计标准》GB 50180-2018
//   - 《社区生活圈规划技术指南》TD/T 1062-2021
//   - 《浙江省城镇社区生活圈规划导则》(2022)
func GetDefaultCategories() []POICategory {
	return []POICategory{
		{
			Code:        "medical",
			Name:        "医疗卫生",
			Description: "社区卫生服务中心/站、诊所、药店等基层医疗设施",
			Weight:      0.18,
			SubTypes: []POISubType{
				{Code: "community_health", Name: "社区卫生服务中心/站", OSMTag: "amenity=clinic"},
				{Code: "hospital", Name: "医院", OSMTag: "amenity=hospital"},
				{Code: "pharmacy", Name: "药店", OSMTag: "amenity=pharmacy"},
			},
		},
		{
			Code:        "education",
			Name:        "教育设施",
			Description: "幼儿园、小学、中学等基础教育设施",
			Weight:      0.18,
			SubTypes: []POISubType{
				{Code: "kindergarten", Name: "幼儿园", OSMTag: "amenity=kindergarten"},
				{Code: "primary", Name: "小学", OSMTag: "amenity=school"},
				{Code: "secondary", Name: "初中", OSMTag: "amenity=school"},
			},
		},
		{
			Code:        "elderly",
			Name:        "养老服务",
			Description: "社区养老服务中心、日间照料中心、老年活动室",
			Weight:      0.12,
			SubTypes: []POISubType{
				{Code: "elderly_center", Name: "社区养老服务中心", OSMTag: "amenity=social_facility"},
				{Code: "daycare", Name: "日间照料中心", OSMTag: "amenity=social_facility"},
				{Code: "elderly_activity", Name: "老年活动室", OSMTag: "amenity=community_centre"},
			},
		},
		{
			Code:        "commerce",
			Name:        "商业服务",
			Description: "菜市场/生鲜超市、综合超市、便利店、餐饮等",
			Weight:      0.15,
			SubTypes: []POISubType{
				{Code: "market", Name: "菜市场/生鲜超市", OSMTag: "amenity=marketplace"},
				{Code: "supermarket", Name: "综合超市", OSMTag: "shop=supermarket"},
				{Code: "convenience", Name: "便利店", OSMTag: "shop=convenience"},
				{Code: "restaurant", Name: "餐饮服务", OSMTag: "amenity=restaurant"},
			},
		},
		{
			Code:        "culture",
			Name:        "文化体育",
			Description: "社区文化活动中心、健身场地、公园绿地、阅览室",
			Weight:      0.12,
			SubTypes: []POISubType{
				{Code: "culture_center", Name: "文化活动中心", OSMTag: "amenity=community_centre"},
				{Code: "sports_field", Name: "健身场地/球场", OSMTag: "leisure=pitch"},
				{Code: "park", Name: "公园绿地", OSMTag: "leisure=park"},
				{Code: "library", Name: "图书室/阅览室", OSMTag: "amenity=library"},
			},
		},
		{
			Code:        "public",
			Name:        "公共管理",
			Description: "社区服务中心、派出所、银行网点、邮政服务",
			Weight:      0.10,
			SubTypes: []POISubType{
				{Code: "community_service", Name: "社区服务中心", OSMTag: "amenity=townhall"},
				{Code: "police", Name: "派出所/警务室", OSMTag: "amenity=police"},
				{Code: "bank", Name: "银行网点", OSMTag: "amenity=bank"},
				{Code: "post", Name: "邮政服务", OSMTag: "amenity=post_office"},
			},
		},
		{
			Code:        "transport",
			Name:        "交通设施",
			Description: "公交站点、轨道交通站点、公共停车场",
			Weight:      0.10,
			SubTypes: []POISubType{
				{Code: "bus_stop", Name: "公交站点", OSMTag: "highway=bus_stop"},
				{Code: "metro", Name: "轨道交通站", OSMTag: "railway=station"},
				{Code: "parking", Name: "公共停车场", OSMTag: "amenity=parking"},
				{Code: "bike_parking", Name: "非机动车停车", OSMTag: "amenity=bicycle_parking"},
			},
		},
		{
			Code:        "child",
			Name:        "托幼托育",
			Description: "托儿所、托育机构、儿童游乐设施",
			Weight:      0.05,
			SubTypes: []POISubType{
				{Code: "nursery", Name: "托儿所/托育机构", OSMTag: "amenity=childcare"},
				{Code: "playground", Name: "儿童游乐设施", OSMTag: "leisure=playground"},
			},
		},
	}
}
