package service

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"

	"github.com/yourname/15min-life-circle/internal/config"
	"github.com/yourname/15min-life-circle/internal/database"
	"github.com/yourname/15min-life-circle/internal/model"
)

// EvaluationService 评价服务
type EvaluationService struct {
	db          *database.DB
	poiService  *POIService
	amapService *AmapPOIService
}

// NewEvaluationService 创建评价服务
func NewEvaluationService(db *database.DB, poiService *POIService, cfg *config.Config) *EvaluationService {
	return &EvaluationService{
		db:          db,
		poiService:  poiService,
		amapService: NewAmapPOIService(cfg.Amap),
	}
}

// Evaluate 执行综合评价
func (s *EvaluationService) Evaluate(ctx context.Context, req *model.EvaluationRequest) (*model.EvaluationResult, error) {
	req.Validate()

	// 调用数据库评价函数（使用用户配置的步行速度）
	query := `
		SELECT 
			total_score,
			grade,
			category,
			category_name,
			cat_weight,
			category_score,
			weighted_score,
			poi_count,
			details
		FROM evaluate_life_circle($1, $2, $3)
	`

	rows, err := s.db.Pool.Query(ctx, query, req.Lng, req.Lat, req.WalkSpeed)
	if err != nil {
		return nil, fmt.Errorf("evaluate: %w", err)
	}
	defer rows.Close()

	result := &model.EvaluationResult{
		Origin:         model.Point{req.Lng, req.Lat},
		CategoryScores: make([]model.CategoryScore, 0),
	}

	for rows.Next() {
		var (
			totalScore     float64
			grade          string
			category       string
			categoryName   string
			categoryWeight float64
			categoryScore  float64
			weightedScore  float64
			poiCount       int64
			detailsJSON    []byte
		)

		if err := rows.Scan(
			&totalScore,
			&grade,
			&category,
			&categoryName,
			&categoryWeight,
			&categoryScore,
			&weightedScore,
			&poiCount,
			&detailsJSON,
		); err != nil {
			return nil, fmt.Errorf("scan result: %w", err)
		}

		result.TotalScore = totalScore
		result.Grade = strings.TrimSpace(grade)

		// 解析详情
		var details []model.SubTypeScore
		if err := json.Unmarshal(detailsJSON, &details); err != nil {
			// 忽略解析错误
			details = nil
		}

		catScore := model.CategoryScore{
			Category:      category,
			Name:          categoryName,
			Score:         categoryScore,
			Weight:        categoryWeight,
			WeightedScore: weightedScore,
			POICount:      int(poiCount),
			Details:       details,
		}
		result.CategoryScores = append(result.CategoryScores, catScore)
	}

	// 生成评价说明
	result.Summary = model.GetGradeDescription(result.Grade)

	// 生成改进建议
	result.Suggestions = s.generateSuggestions(result.CategoryScores)

	// 获取等时圈 GeoJSON（使用用户配置的步行速度）
	isoService := NewIsochroneService(s.db)
	isoReq := &model.IsochroneRequest{
		Lng:            req.Lng,
		Lat:            req.Lat,
		TimeThresholds: []int{5, 10, 15},
		WalkSpeed:      req.WalkSpeed,
	}
	if isoFC, err := isoService.CalculateAsGeoJSON(ctx, isoReq); err == nil {
		result.Isochrone = isoFC
	}

	// 获取 POI GeoJSON（使用用户配置的步行速度）
	if pois, err := s.poiService.QueryInIsochrone(ctx, req.Lng, req.Lat, req.TimeThreshold, req.WalkSpeed); err == nil {
		// 尝试补充高德 POI 数据
		if s.amapService != nil && s.amapService.IsEnabled() {
			// 计算搜索半径（步行速度 * 15分钟）
			radius := int(req.WalkSpeed * 1000 / 60 * 15)
			if amapPOIs, err := s.amapService.SearchNearby(req.Lng, req.Lat, radius); err == nil {
				// 合并去重
				pois = s.mergePOIs(pois, amapPOIs)
				log.Printf("合并高德POI：本地 %d + 高德 %d = 总计 %d", len(pois)-len(amapPOIs), len(amapPOIs), len(pois))
			} else {
				log.Printf("高德POI查询失败: %v", err)
			}
		}
		result.POIs = s.poiService.POIsAsGeoJSON(pois)
	}

	return result, nil
}

// mergePOIs 合并本地和高德POI（去重）
func (s *EvaluationService) mergePOIs(localPOIs []model.POI, amapPOIs []model.POI) []model.POI {
	// 用于去重的集合（基于位置和名称）
	seen := make(map[string]bool)
	
	// 先添加本地POI
	for _, poi := range localPOIs {
		key := fmt.Sprintf("%.5f,%.5f,%s", poi.Lng, poi.Lat, poi.Name)
		seen[key] = true
		poi.Source = "osm"
	}
	
	result := localPOIs
	
	// 添加不重复的高德POI
	for _, poi := range amapPOIs {
		key := fmt.Sprintf("%.5f,%.5f,%s", poi.Lng, poi.Lat, poi.Name)
		
		// 检查是否已存在类似POI（距离在50米内且名称相似）
		isDuplicate := seen[key]
		if !isDuplicate {
			// 还可以检查附近是否有同名POI
			for _, local := range localPOIs {
				dist := distance(poi.Lng, poi.Lat, local.Lng, local.Lat)
				if dist < 50 && strings.Contains(poi.Name, local.Name) || strings.Contains(local.Name, poi.Name) {
					isDuplicate = true
					break
				}
			}
		}
		
		if !isDuplicate {
			result = append(result, poi)
			seen[key] = true
		}
	}
	
	return result
}

// distance 计算两点间距离（米）- 简化版
func distance(lng1, lat1, lng2, lat2 float64) float64 {
	// 简单的欧几里得距离近似（适用于小范围）
	// 1度纬度约111km，1度经度在杭州约90km
	dLat := (lat2 - lat1) * 111000
	dLng := (lng2 - lng1) * 90000
	return (dLat*dLat + dLng*dLng) / 2 // 简化平方根
}

// generateSuggestions 根据评分生成改进建议
func (s *EvaluationService) generateSuggestions(scores []model.CategoryScore) []string {
	var suggestions []string

	categoryNames := map[string]string{
		"medical":   "医疗卫生",
		"education": "教育设施",
		"commerce":  "商业服务",
		"culture":   "文化体育",
		"public":    "公共服务",
		"transport": "交通设施",
		"elderly":   "养老服务",
	}

	for _, cs := range scores {
		if cs.Score < 60 {
			name := categoryNames[cs.Category]
			if name == "" {
				name = cs.Name
			}
			suggestions = append(suggestions,
				fmt.Sprintf("【%s】设施覆盖不足（得分%.1f），建议增设相关配套设施", name, cs.Score))
		}
	}

	if len(suggestions) == 0 {
		suggestions = append(suggestions, "当前区域生活圈配套较为完善，建议保持现有服务水平")
	}

	return suggestions
}

// GetStandards 获取评价标准
func (s *EvaluationService) GetStandards(ctx context.Context) ([]model.EvaluationStandard, error) {
	query := `
		SELECT 
			category,
			sub_type,
			min_count_5,
			min_count_10,
			min_count_15,
			is_required,
			base_score
		FROM evaluation_standard
		ORDER BY category, sub_type
	`

	rows, err := s.db.Pool.Query(ctx, query)
	if err != nil {
		// 如果表不存在，返回默认标准
		return model.GetDefaultStandards(), nil
	}
	defer rows.Close()

	var standards []model.EvaluationStandard
	for rows.Next() {
		var std model.EvaluationStandard
		if err := rows.Scan(
			&std.Category,
			&std.SubType,
			&std.MinCount5,
			&std.MinCount10,
			&std.MinCount15,
			&std.Required,
			&std.BaseScore,
		); err != nil {
			return nil, fmt.Errorf("scan standard: %w", err)
		}
		standards = append(standards, std)
	}

	if len(standards) == 0 {
		return model.GetDefaultStandards(), nil
	}

	return standards, nil
}
