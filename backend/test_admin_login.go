package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

func main() {
	// URL вашего Render сервера
	baseURL := "https://tow-truck.onrender.com"

	// Тестируем admin login
	loginData := map[string]string{
		"user_id":  "admin",
		"password": "admin123", // стандартный пароль
	}

	jsonData, _ := json.Marshal(loginData)

	resp, err := http.Post(baseURL+"/api/v1/auth/admin/login", "application/json", bytes.NewBuffer(jsonData))
	if err != nil {
		fmt.Printf("❌ Ошибка подключения: %v\n", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode == 200 {
		fmt.Println("✅ Admin login работает!")

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)

		if tokens, ok := result["tokens"]; ok {
			fmt.Printf("🔑 Получен access token: %v\n", tokens)
		}
	} else {
		fmt.Printf("❌ Admin login не работает. Status: %d\n", resp.StatusCode)

		var errorResult map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&errorResult)
		fmt.Printf("Ошибка: %v\n", errorResult)
	}

	// Тестируем admin endpoints
	fmt.Println("\n🔍 Тестируем admin endpoints...")

	endpoints := []string{
		"/api/v1/admin/overview",
		"/api/v1/admin/driver-verifications",
		"/api/v1/admin/users",
		"/api/v1/admin/reviews",
		"/api/v1/admin/drivers-online",
	}

	for _, endpoint := range endpoints {
		resp, err := http.Get(baseURL + endpoint)
		if err != nil {
			fmt.Printf("❌ %s: Ошибка подключения\n", endpoint)
			continue
		}
		defer resp.Body.Close()

		if resp.StatusCode == 200 || resp.StatusCode == 401 {
			fmt.Printf("✅ %s: Endpoint существует (Status: %d)\n", endpoint, resp.StatusCode)
		} else {
			fmt.Printf("❌ %s: Endpoint не найден (Status: %d)\n", endpoint, resp.StatusCode)
		}

		time.Sleep(100 * time.Millisecond) // Пауза между запросами
	}
}