package model

// GeoJSON 基础结构
// 遵循 RFC 7946 规范

// Point 表示一个坐标点 [lng, lat]
type Point [2]float64

// Lng 返回经度
func (p Point) Lng() float64 { return p[0] }

// Lat 返回纬度
func (p Point) Lat() float64 { return p[1] }

// Geometry GeoJSON 几何对象
type Geometry struct {
	Type        string        `json:"type"`
	Coordinates interface{}   `json:"coordinates"`
}

// Feature GeoJSON 要素
type Feature struct {
	Type       string                 `json:"type"`
	Geometry   Geometry               `json:"geometry"`
	Properties map[string]interface{} `json:"properties"`
}

// FeatureCollection GeoJSON 要素集合
type FeatureCollection struct {
	Type     string    `json:"type"`
	Features []Feature `json:"features"`
}

// NewFeatureCollection 创建新的要素集合
func NewFeatureCollection() *FeatureCollection {
	return &FeatureCollection{
		Type:     "FeatureCollection",
		Features: []Feature{},
	}
}

// AddFeature 添加要素
func (fc *FeatureCollection) AddFeature(f Feature) {
	fc.Features = append(fc.Features, f)
}

// NewPointFeature 创建点要素
func NewPointFeature(lng, lat float64, props map[string]interface{}) Feature {
	return Feature{
		Type: "Feature",
		Geometry: Geometry{
			Type:        "Point",
			Coordinates: Point{lng, lat},
		},
		Properties: props,
	}
}

// NewPolygonFeature 创建多边形要素
func NewPolygonFeature(coordinates [][][2]float64, props map[string]interface{}) Feature {
	return Feature{
		Type: "Feature",
		Geometry: Geometry{
			Type:        "Polygon",
			Coordinates: coordinates,
		},
		Properties: props,
	}
}
