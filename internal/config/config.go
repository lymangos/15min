package config

import (
	"os"
)

// Config 应用配置
type Config struct {
	Server   ServerConfig
	Database DatabaseConfig
	Amap     AmapConfig
}

// ServerConfig 服务器配置
type ServerConfig struct {
	Addr string
}

// DatabaseConfig 数据库配置
type DatabaseConfig struct {
	Host     string
	Port     string
	User     string
	Password string
	DBName   string
	SSLMode  string
}

// AmapConfig 高德地图API配置
type AmapConfig struct {
	Key     string
	Enabled bool
}

// DSN 返回数据库连接字符串
func (c DatabaseConfig) DSN() string {
	return "host=" + c.Host +
		" port=" + c.Port +
		" user=" + c.User +
		" password=" + c.Password +
		" dbname=" + c.DBName +
		" sslmode=" + c.SSLMode
}

// Load 加载配置（从环境变量）
func Load() (*Config, error) {
	amapKey := getEnv("AMAP_KEY", "b8c46da854c65a844724a50cbaa9ca54")
	return &Config{
		Server: ServerConfig{
			Addr: getEnv("SERVER_ADDR", ":8080"),
		},
		Database: DatabaseConfig{
			Host:     getEnv("DB_HOST", "localhost"),
			Port:     getEnv("DB_PORT", "5432"),
			User:     getEnv("DB_USER", "postgres"),
			Password: getEnv("DB_PASSWORD", "postgres"),
			DBName:   getEnv("DB_NAME", "life_circle_15min"),
			SSLMode:  getEnv("DB_SSLMODE", "disable"),
		},
		Amap: AmapConfig{
			Key:     amapKey,
			Enabled: amapKey != "",
		},
	}, nil
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
