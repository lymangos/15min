package api

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/yourname/15min-life-circle/internal/model"
	"github.com/yourname/15min-life-circle/internal/service"
)

// Handler API 处理器
type Handler struct {
	isochroneService  *service.IsochroneService
	poiService        *service.POIService
	evaluationService *service.EvaluationService
}

// NewHandler 创建处理器
func NewHandler(
	isoService *service.IsochroneService,
	poiService *service.POIService,
	evalService *service.EvaluationService,
) *Handler {
	return &Handler{
		isochroneService:  isoService,
		poiService:        poiService,
		evaluationService: evalService,
	}
}

// CalculateIsochrone 计算等时圈
// POST /api/v1/isochrone
func (h *Handler) CalculateIsochrone(c *gin.Context) {
	var req model.IsochroneRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid request",
			"details": err.Error(),
		})
		return
	}

	result, err := h.isochroneService.CalculateAsGeoJSON(c.Request.Context(), &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "calculation failed",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, result)
}

// AnalyzePoint 综合分析某点
// POST /api/v1/analyze
func (h *Handler) AnalyzePoint(c *gin.Context) {
	var req model.EvaluationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid request",
			"details": err.Error(),
		})
		return
	}

	result, err := h.evaluationService.Evaluate(c.Request.Context(), &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "analysis failed",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, result)
}

// GetPOICategories 获取 POI 分类
// GET /api/v1/poi/categories
func (h *Handler) GetPOICategories(c *gin.Context) {
	categories, err := h.poiService.GetCategories(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "failed to get categories",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"categories": categories,
	})
}

// GetEvaluationStandards 获取评价标准
// GET /api/v1/evaluation/standards
func (h *Handler) GetEvaluationStandards(c *gin.Context) {
	standards, err := h.evaluationService.GetStandards(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "failed to get standards",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"standards": standards,
	})
}

// Response 统一响应结构
type Response struct {
	Success bool        `json:"success"`
	Data    interface{} `json:"data,omitempty"`
	Error   string      `json:"error,omitempty"`
}

// SuccessResponse 成功响应
func SuccessResponse(c *gin.Context, data interface{}) {
	c.JSON(http.StatusOK, Response{
		Success: true,
		Data:    data,
	})
}

// ErrorResponse 错误响应
func ErrorResponse(c *gin.Context, status int, message string) {
	c.JSON(status, Response{
		Success: false,
		Error:   message,
	})
}
