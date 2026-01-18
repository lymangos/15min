package service

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"time"

	"github.com/yourname/15min-life-circle/internal/config"
	"github.com/yourname/15min-life-circle/internal/model"
)

// AmapPOIService 高德地图POI服务
type AmapPOIService struct {
	apiKey  string
	enabled bool
	client  *http.Client
}

// AmapPOIResponse 高德API响应
type AmapPOIResponse struct {
	Status     string     `json:"status"`
	Info       string     `json:"info"`
	Count      string     `json:"count"`
	POIs       []AmapPOI  `json:"pois"`
}

// FlexibleString 处理高德API返回的灵活类型字段（可能是字符串或数组）
type FlexibleString string

func (f *FlexibleString) UnmarshalJSON(data []byte) error {
	// 先尝试解析为字符串
	var s string
	if err := json.Unmarshal(data, &s); err == nil {
		*f = FlexibleString(s)
		return nil
	}
	
	// 如果失败，尝试解析为字符串数组
	var arr []string
	if err := json.Unmarshal(data, &arr); err == nil {
		if len(arr) > 0 {
			*f = FlexibleString(arr[0])
		} else {
			*f = ""
		}
		return nil
	}
	
	// 都失败则设为空
	*f = ""
	return nil
}

// AmapPOI 高德POI数据
type AmapPOI struct {
	ID       string         `json:"id"`
	Name     string         `json:"name"`
	Type     string         `json:"type"`
	TypeCode string         `json:"typecode"`
	Address  FlexibleString `json:"address"`
	Location string         `json:"location"` // 经度,纬度
	Distance string         `json:"distance"`
}

// NewAmapPOIService 创建高德POI服务
func NewAmapPOIService(cfg config.AmapConfig) *AmapPOIService {
	return &AmapPOIService{
		apiKey:  cfg.Key,
		enabled: cfg.Enabled,
		client: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// IsEnabled 是否启用
func (s *AmapPOIService) IsEnabled() bool {
	return s.enabled && s.apiKey != ""
}

// 高德POI类型映射到我们的分类
// 参考：https://lbs.amap.com/api/webservice/download
var amapTypeMapping = map[string]struct {
	Category string
	SubType  string
}{
	// 医疗卫生
	"090100": {Category: "medical", SubType: "community_health"},  // 综合医院
	"090200": {Category: "medical", SubType: "community_health"},  // 专科医院
	"090300": {Category: "medical", SubType: "community_health"},  // 诊所
	"090400": {Category: "medical", SubType: "community_health"},  // 卫生站
	"090500": {Category: "medical", SubType: "pharmacy"},          // 药房药店
	"090600": {Category: "medical", SubType: "community_health"},  // 医疗保健服务
	"090700": {Category: "medical", SubType: "hospital"},          // 疾控中心
	
	// 教育
	"141200": {Category: "education", SubType: "kindergarten"},    // 幼儿园
	"141201": {Category: "education", SubType: "kindergarten"},    // 幼儿园
	"141202": {Category: "child", SubType: "nursery"},             // 亲子园
	"141300": {Category: "education", SubType: "primary"},         // 小学
	"141301": {Category: "education", SubType: "primary"},         // 小学
	"141400": {Category: "education", SubType: "secondary"},       // 中学
	"141401": {Category: "education", SubType: "secondary"},       // 初级中学
	"141402": {Category: "education", SubType: "secondary"},       // 高级中学
	
	// 养老服务
	"100105": {Category: "elderly", SubType: "elderly_center"},    // 福利院
	"100106": {Category: "elderly", SubType: "elderly_center"},    // 敬老院
	"100107": {Category: "elderly", SubType: "elderly_center"},    // 养老院
	
	// 商业服务
	"060100": {Category: "commerce", SubType: "supermarket"},      // 购物中心
	"060400": {Category: "commerce", SubType: "supermarket"},      // 超级市场
	"060401": {Category: "commerce", SubType: "supermarket"},      // 超市
	"060402": {Category: "commerce", SubType: "convenience"},      // 便利店
	"060500": {Category: "commerce", SubType: "market"},           // 农副产品市场
	"060501": {Category: "commerce", SubType: "market"},           // 菜市场
	"050100": {Category: "commerce", SubType: "restaurant"},       // 中餐厅
	"050200": {Category: "commerce", SubType: "restaurant"},       // 外国餐厅
	"050300": {Category: "commerce", SubType: "restaurant"},       // 快餐厅
	
	// 文化体育
	"080100": {Category: "culture", SubType: "culture_center"},    // 博物馆
	"080300": {Category: "culture", SubType: "library"},           // 图书馆
	"080400": {Category: "culture", SubType: "culture_center"},    // 科技馆
	"080500": {Category: "culture", SubType: "culture_center"},    // 文化宫
	"080600": {Category: "culture", SubType: "culture_center"},    // 美术馆
	"080700": {Category: "culture", SubType: "culture_center"},    // 展览馆
	"110000": {Category: "culture", SubType: "park"},              // 公园
	"110100": {Category: "culture", SubType: "park"},              // 公园
	"110101": {Category: "culture", SubType: "park"},              // 公园
	"110102": {Category: "culture", SubType: "park"},              // 动物园
	"110103": {Category: "culture", SubType: "park"},              // 植物园
	"080101": {Category: "culture", SubType: "sports_field"},      // 体育馆
	"080102": {Category: "culture", SubType: "sports_field"},      // 体育场
	"080103": {Category: "culture", SubType: "sports_field"},      // 运动场
	"080104": {Category: "culture", SubType: "sports_field"},      // 健身中心
	
	// 公共管理
	"130100": {Category: "public", SubType: "community_service"},  // 政府机构
	"130105": {Category: "public", SubType: "community_service"},  // 社区服务中心
	"130300": {Category: "public", SubType: "police"},             // 公安局
	"130301": {Category: "public", SubType: "police"},             // 派出所
	"160100": {Category: "public", SubType: "bank"},               // 银行
	"160300": {Category: "public", SubType: "post"},               // 邮局
	
	// 交通设施
	"150200": {Category: "transport", SubType: "bus_stop"},        // 公交车站
	"150201": {Category: "transport", SubType: "bus_stop"},        // 公交站
	"150500": {Category: "transport", SubType: "metro"},           // 地铁站
	"150501": {Category: "transport", SubType: "metro"},           // 轨道交通站
	"150900": {Category: "transport", SubType: "parking"},         // 停车场
	"150904": {Category: "transport", SubType: "bike_parking"},    // 停车场入口
	
	// 托幼托育
	"141203": {Category: "child", SubType: "nursery"},             // 托儿所
	"141204": {Category: "child", SubType: "nursery"},             // 早教中心
}

// 高德POI类型代码（用于搜索）
// 我们关注的类型
var amapSearchTypes = []string{
	"090000", // 医疗保健服务
	"141200", // 幼儿园
	"141300", // 小学
	"141400", // 中学
	"100100", // 福利院
	"060400", // 超市
	"060500", // 农副产品市场
	"050000", // 餐饮服务
	"080000", // 公共设施
	"110000", // 公园
	"130000", // 政府机构
	"150200", // 公交车站
	"150500", // 地铁站
	"160100", // 银行
	"160300", // 邮局
}

// SearchNearby 周边搜索POI
func (s *AmapPOIService) SearchNearby(lng, lat float64, radius int) ([]model.POI, error) {
	if !s.IsEnabled() {
		return nil, nil
	}

	var allPOIs []model.POI
	
	// 搜索多个类型
	types := "090000|141200|141300|141400|100100|060400|050000|080000|110000|130000|150200|150500|160100"
	
	pois, err := s.searchByType(lng, lat, radius, types)
	if err != nil {
		return nil, err
	}
	allPOIs = append(allPOIs, pois...)

	return allPOIs, nil
}

// searchByType 按类型搜索
func (s *AmapPOIService) searchByType(lng, lat float64, radius int, types string) ([]model.POI, error) {
	baseURL := "https://restapi.amap.com/v3/place/around"
	
	params := url.Values{}
	params.Set("key", s.apiKey)
	params.Set("location", fmt.Sprintf("%.6f,%.6f", lng, lat))
	params.Set("radius", strconv.Itoa(radius))
	params.Set("types", types)
	params.Set("offset", "50")  // 每页50条
	params.Set("page", "1")
	params.Set("extensions", "base")
	
	reqURL := baseURL + "?" + params.Encode()
	
	resp, err := s.client.Get(reqURL)
	if err != nil {
		return nil, fmt.Errorf("amap API request failed: %w", err)
	}
	defer resp.Body.Close()
	
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response failed: %w", err)
	}
	
	var result AmapPOIResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("parse response failed: %w", err)
	}
	
	if result.Status != "1" {
		return nil, fmt.Errorf("amap API error: %s", result.Info)
	}
	
	// 转换为内部POI格式
	var pois []model.POI
	for _, ap := range result.POIs {
		poi := s.convertToPOI(ap)
		if poi != nil {
			pois = append(pois, *poi)
		}
	}
	
	return pois, nil
}

// convertToPOI 转换高德POI为内部格式
func (s *AmapPOIService) convertToPOI(ap AmapPOI) *model.POI {
	// 解析坐标
	var lng, lat float64
	if _, err := fmt.Sscanf(ap.Location, "%f,%f", &lng, &lat); err != nil {
		return nil
	}
	
	// 获取类型映射（使用前6位类型码）
	typeCode := ap.TypeCode
	if len(typeCode) > 6 {
		typeCode = typeCode[:6]
	}
	
	mapping, ok := amapTypeMapping[typeCode]
	if !ok {
		// 尝试使用前4位
		if len(typeCode) >= 4 {
			mapping, ok = amapTypeMapping[typeCode[:4]+"00"]
		}
		if !ok {
			// 默认分类
			mapping = struct {
				Category string
				SubType  string
			}{Category: "public", SubType: "community_service"}
		}
	}
	
	return &model.POI{
		Name:     ap.Name,
		Category: mapping.Category,
		SubType:  mapping.SubType,
		Lng:      lng,
		Lat:      lat,
		Source:   "amap",
	}
}
