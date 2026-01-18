package service

import (
	"context"
	"fmt"

	"github.com/yourname/15min-life-circle/internal/database"
	"github.com/yourname/15min-life-circle/internal/model"
)

// POIService POI 服务
type POIService struct {
	db *database.DB
}

// NewPOIService 创建 POI 服务
func NewPOIService(db *database.DB) *POIService {
	return &POIService{db: db}
}

// QueryInIsochrone 查询等时圈内的 POI
func (s *POIService) QueryInIsochrone(ctx context.Context, lng, lat float64, minutes int, walkSpeed float64) ([]model.POI, error) {
	query := `
		SELECT 
			id,
			COALESCE(name, '') AS name,
			category,
			sub_type,
			lng,
			lat,
			distance_m,
			walk_time_min
		FROM query_pois_in_isochrone($1, $2, $3, $4, NULL)
	`

	rows, err := s.db.Pool.Query(ctx, query, lng, lat, minutes, walkSpeed)
	if err != nil {
		return nil, fmt.Errorf("query pois: %w", err)
	}
	defer rows.Close()

	var pois []model.POI
	for rows.Next() {
		var poi model.POI
		var distanceM, walkTimeMin float64
		if err := rows.Scan(
			&poi.ID,
			&poi.Name,
			&poi.Category,
			&poi.SubType,
			&poi.Lng,
			&poi.Lat,
			&distanceM,
			&walkTimeMin,
		); err != nil {
			return nil, fmt.Errorf("scan poi: %w", err)
		}
		pois = append(pois, poi)
	}

	return pois, nil
}

// CountByCategory 统计各分类的 POI 数量
func (s *POIService) CountByCategory(ctx context.Context, lng, lat float64, minutes int, walkSpeed float64) ([]model.POIStatistics, error) {
	query := `
		SELECT 
			category,
			sub_type,
			poi_count
		FROM count_pois_in_isochrone($1, $2, $3, $4)
	`

	rows, err := s.db.Pool.Query(ctx, query, lng, lat, minutes, walkSpeed)
	if err != nil {
		return nil, fmt.Errorf("count pois: %w", err)
	}
	defer rows.Close()

	var stats []model.POIStatistics
	for rows.Next() {
		var stat model.POIStatistics
		var count int64
		if err := rows.Scan(&stat.Category, &stat.SubType, &count); err != nil {
			return nil, fmt.Errorf("scan stat: %w", err)
		}
		stat.Count = int(count)
		stats = append(stats, stat)
	}

	return stats, nil
}

// POIsAsGeoJSON 将 POI 转换为 GeoJSON
func (s *POIService) POIsAsGeoJSON(pois []model.POI) *model.FeatureCollection {
	fc := model.NewFeatureCollection()

	for _, poi := range pois {
		feature := model.NewPointFeature(poi.Lng, poi.Lat, map[string]interface{}{
			"id":       poi.ID,
			"name":     poi.Name,
			"category": poi.Category,
			"sub_type": poi.SubType,
			"type":     "poi",
			"source":   poi.Source,
		})
		fc.AddFeature(feature)
	}

	return fc
}

// GetCategories 获取所有 POI 分类
func (s *POIService) GetCategories(ctx context.Context) ([]model.POICategory, error) {
	query := `
		SELECT 
			c.code,
			c.name,
			COALESCE(c.description, '') AS description,
			c.weight,
			COALESCE(
				JSON_AGG(
					JSON_BUILD_OBJECT(
						'code', st.code,
						'name', st.name,
						'osm_tag', COALESCE(st.osm_tags[1], '')
					) ORDER BY st.sort_order
				) FILTER (WHERE st.code IS NOT NULL),
				'[]'::json
			) AS sub_types
		FROM poi_category c
		LEFT JOIN poi_sub_type st ON st.category_code = c.code
		GROUP BY c.code, c.name, c.description, c.weight, c.sort_order
		ORDER BY c.sort_order
	`

	rows, err := s.db.Pool.Query(ctx, query)
	if err != nil {
		// 如果表不存在，返回默认分类
		return model.GetDefaultCategories(), nil
	}
	defer rows.Close()

	var categories []model.POICategory
	for rows.Next() {
		var cat model.POICategory
		var subTypesJSON []byte
		if err := rows.Scan(&cat.Code, &cat.Name, &cat.Description, &cat.Weight, &subTypesJSON); err != nil {
			return nil, fmt.Errorf("scan category: %w", err)
		}
		// 解析子类型
		// 这里简化处理，实际项目中应该解析 JSON
		categories = append(categories, cat)
	}

	if len(categories) == 0 {
		return model.GetDefaultCategories(), nil
	}

	return categories, nil
}
