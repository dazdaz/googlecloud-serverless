// User Service (Go)
// ------------------
// This service manages user data and demonstrates how a Go-based
// Cloud Run service can:
// 1. Handle authenticated requests from other services
// 2. Make authenticated requests to other internal services (Order Service)
//
// This demonstrates a service mesh pattern where internal services
// communicate with each other using OIDC tokens.

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"golang.org/x/oauth2/google"
)

// User represents a user in the system
type User struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	Role      string    `json:"role"`
	CreatedAt time.Time `json:"created_at"`
}

// HealthResponse represents the health check response
type HealthResponse struct {
	Service  string `json:"service"`
	Language string `json:"language"`
	Status   string `json:"status"`
	Version  string `json:"version"`
}

// UsersResponse represents the response for user endpoints
type UsersResponse struct {
	Service string `json:"service"`
	Count   int    `json:"count,omitempty"`
	Users   []User `json:"users,omitempty"`
	User    *User  `json:"user,omitempty"`
	Message string `json:"message,omitempty"`
}

// UserWithOrders represents a user along with their orders
type UserWithOrders struct {
	Service string      `json:"service"`
	User    *User       `json:"user"`
	Orders  interface{} `json:"orders"`
	Flow    string      `json:"flow"`
}

// ErrorResponse represents an error response
type ErrorResponse struct {
	Error string `json:"error"`
}

// In-memory user storage (simulating a database)
var users = []User{
	{
		ID:        "user-001",
		Name:      "Alice Johnson",
		Email:     "alice@example.com",
		Role:      "admin",
		CreatedAt: time.Now().Add(-30 * 24 * time.Hour),
	},
	{
		ID:        "user-002",
		Name:      "Bob Smith",
		Email:     "bob@example.com",
		Role:      "developer",
		CreatedAt: time.Now().Add(-20 * 24 * time.Hour),
	},
	{
		ID:        "user-003",
		Name:      "Carol Williams",
		Email:     "carol@example.com",
		Role:      "viewer",
		CreatedAt: time.Now().Add(-10 * 24 * time.Hour),
	},
}

// ORDER_SERVICE_URL is the URL of the Order Service for service-to-service calls
var ORDER_SERVICE_URL = os.Getenv("ORDER_SERVICE_URL")

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Log ORDER_SERVICE_URL for debugging
	if ORDER_SERVICE_URL != "" {
		log.Printf("Order Service URL configured: %s", ORDER_SERVICE_URL)
	} else {
		log.Printf("ORDER_SERVICE_URL not configured - user-orders endpoint will be limited")
	}

	// Set up routes
	http.HandleFunc("/", healthHandler)
	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/users", usersHandler)
	http.HandleFunc("/users/", userByIDHandler)

	log.Printf("User Service (Go) starting on port %s", port)
	if err := http.ListenAndServe(":"+port, logRequest(http.DefaultServeMux)); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

// logRequest is a middleware that logs incoming requests
func logRequest(handler http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.Printf("%s %s - User-Agent: %s", r.Method, r.URL.Path, r.UserAgent())
		
		// Log authentication info (for debugging)
		authHeader := r.Header.Get("Authorization")
		if authHeader != "" {
			log.Printf("  Authorization header present (Bearer token)")
		}
		
		handler.ServeHTTP(w, r)
	})
}

// getIDToken fetches an OIDC ID token for the given audience (target service URL)
func getIDToken(ctx context.Context, audience string) (string, error) {
	// Use Google's default credentials to get an ID token
	// This works automatically on Cloud Run with the service's identity
	tokenSource, err := google.DefaultTokenSource(ctx, audience)
	if err != nil {
		return "", fmt.Errorf("failed to get token source: %v", err)
	}

	// For ID tokens, we need to use the IDTokenSource
	// The google.DefaultTokenSource returns access tokens, not ID tokens
	// We need to use the metadata server directly for ID tokens
	
	// Create a request to the metadata server
	metadataURL := fmt.Sprintf(
		"http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?audience=%s",
		audience,
	)
	
	req, err := http.NewRequestWithContext(ctx, "GET", metadataURL, nil)
	if err != nil {
		return "", fmt.Errorf("failed to create metadata request: %v", err)
	}
	req.Header.Set("Metadata-Flavor", "Google")
	
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		// If metadata server is not available (local dev), try using access token
		log.Printf("Metadata server not available, falling back to access token: %v", err)
		token, err := tokenSource.Token()
		if err != nil {
			return "", fmt.Errorf("failed to get token: %v", err)
		}
		return token.AccessToken, nil
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("metadata server returned %d: %s", resp.StatusCode, string(body))
	}
	
	idToken, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read ID token: %v", err)
	}
	
	return string(idToken), nil
}

// makeAuthenticatedRequest makes an HTTP request to another service with OIDC authentication
func makeAuthenticatedRequest(ctx context.Context, url string) ([]byte, error) {
	// Extract the base URL for the audience
	parts := strings.Split(url, "/")
	if len(parts) < 3 {
		return nil, fmt.Errorf("invalid URL: %s", url)
	}
	audience := parts[0] + "//" + parts[2]
	
	// Get OIDC ID token
	idToken, err := getIDToken(ctx, audience)
	if err != nil {
		return nil, fmt.Errorf("failed to get ID token: %v", err)
	}
	
	// Create request
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %v", err)
	}
	
	// Add Authorization header with Bearer token
	req.Header.Set("Authorization", "Bearer "+idToken)
	req.Header.Set("Content-Type", "application/json")
	
	// Make request
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %v", err)
	}
	defer resp.Body.Close()
	
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %v", err)
	}
	
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("service returned %d: %s", resp.StatusCode, string(body))
	}
	
	return body, nil
}

// healthHandler handles the health check endpoint
func healthHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" && r.URL.Path != "/health" {
		http.NotFound(w, r)
		return
	}

	response := HealthResponse{
		Service:  "user-service",
		Language: "Go",
		Status:   "healthy",
		Version:  "1.0.0",
	}

	writeJSON(w, http.StatusOK, response)
}

// usersHandler handles the /users endpoint
func usersHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		getAllUsers(w, r)
	case http.MethodPost:
		createUser(w, r)
	default:
		writeJSON(w, http.StatusMethodNotAllowed, ErrorResponse{
			Error: fmt.Sprintf("Method %s not allowed", r.Method),
		})
	}
}

// userByIDHandler handles the /users/{id} endpoint
func userByIDHandler(w http.ResponseWriter, r *http.Request) {
	// Extract user ID from path
	path := strings.TrimPrefix(r.URL.Path, "/users/")
	
	// Check if this is a request for user's orders: /users/{id}/orders
	if strings.Contains(path, "/orders") {
		parts := strings.Split(path, "/orders")
		userID := parts[0]
		getUserOrders(w, r, userID)
		return
	}
	
	if path == "" {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{
			Error: "User ID is required",
		})
		return
	}

	switch r.Method {
	case http.MethodGet:
		getUserByID(w, r, path)
	case http.MethodDelete:
		deleteUser(w, r, path)
	default:
		writeJSON(w, http.StatusMethodNotAllowed, ErrorResponse{
			Error: fmt.Sprintf("Method %s not allowed", r.Method),
		})
	}
}

// getAllUsers returns all users
func getAllUsers(w http.ResponseWriter, r *http.Request) {
	response := UsersResponse{
		Service: "user-service (Go)",
		Count:   len(users),
		Users:   users,
	}

	writeJSON(w, http.StatusOK, response)
}

// getUserByID returns a specific user by ID
func getUserByID(w http.ResponseWriter, r *http.Request, userID string) {
	for _, user := range users {
		if user.ID == userID {
			response := UsersResponse{
				Service: "user-service (Go)",
				User:    &user,
			}
			writeJSON(w, http.StatusOK, response)
			return
		}
	}

	writeJSON(w, http.StatusNotFound, ErrorResponse{
		Error: fmt.Sprintf("User with ID '%s' not found", userID),
	})
}

// getUserOrders fetches a user and their orders from the Order Service
// This demonstrates service-to-service communication: User Service -> Order Service
func getUserOrders(w http.ResponseWriter, r *http.Request, userID string) {
	log.Printf("getUserOrders called for user: %s", userID)
	
	// First, find the user
	var foundUser *User
	for _, user := range users {
		if user.ID == userID {
			foundUser = &user
			break
		}
	}
	
	if foundUser == nil {
		writeJSON(w, http.StatusNotFound, ErrorResponse{
			Error: fmt.Sprintf("User with ID '%s' not found", userID),
		})
		return
	}
	
	// Check if ORDER_SERVICE_URL is configured
	if ORDER_SERVICE_URL == "" {
		writeJSON(w, http.StatusServiceUnavailable, ErrorResponse{
			Error: "ORDER_SERVICE_URL not configured - cannot fetch orders",
		})
		return
	}
	
	// Make authenticated request to Order Service
	log.Printf("Calling Order Service at: %s/orders/user/%s", ORDER_SERVICE_URL, userID)
	
	orderURL := fmt.Sprintf("%s/orders/user/%s", ORDER_SERVICE_URL, userID)
	ordersData, err := makeAuthenticatedRequest(r.Context(), orderURL)
	if err != nil {
		log.Printf("Error calling Order Service: %v", err)
		writeJSON(w, http.StatusBadGateway, ErrorResponse{
			Error: fmt.Sprintf("Failed to fetch orders from Order Service: %v", err),
		})
		return
	}
	
	// Parse the orders response
	var ordersResponse interface{}
	if err := json.Unmarshal(ordersData, &ordersResponse); err != nil {
		log.Printf("Error parsing orders response: %v", err)
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{
			Error: "Failed to parse orders response",
		})
		return
	}
	
	// Return combined response
	response := UserWithOrders{
		Service: "user-service (Go)",
		User:    foundUser,
		Orders:  ordersResponse,
		Flow:    "User Service (Go) → Order Service (Node.js) via OIDC",
	}
	
	log.Printf("Successfully fetched orders for user %s", userID)
	writeJSON(w, http.StatusOK, response)
}

// createUser creates a new user
func createUser(w http.ResponseWriter, r *http.Request) {
	var newUser User
	if err := json.NewDecoder(r.Body).Decode(&newUser); err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{
			Error: "Invalid JSON body",
		})
		return
	}

	// Generate ID if not provided
	if newUser.ID == "" {
		newUser.ID = fmt.Sprintf("user-%03d", len(users)+1)
	}
	newUser.CreatedAt = time.Now()

	// Validate required fields
	if newUser.Name == "" {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{
			Error: "Name is required",
		})
		return
	}

	if newUser.Email == "" {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{
			Error: "Email is required",
		})
		return
	}

	users = append(users, newUser)

	response := UsersResponse{
		Service: "user-service (Go)",
		User:    &newUser,
		Message: "User created successfully",
	}

	writeJSON(w, http.StatusCreated, response)
}

// deleteUser deletes a user by ID
func deleteUser(w http.ResponseWriter, r *http.Request, userID string) {
	for i, user := range users {
		if user.ID == userID {
			users = append(users[:i], users[i+1:]...)
			response := UsersResponse{
				Service: "user-service (Go)",
				Message: fmt.Sprintf("User '%s' deleted successfully", userID),
			}
			writeJSON(w, http.StatusOK, response)
			return
		}
	}

	writeJSON(w, http.StatusNotFound, ErrorResponse{
		Error: fmt.Sprintf("User with ID '%s' not found", userID),
	})
}

// writeJSON writes a JSON response
func writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(data); err != nil {
		log.Printf("Error encoding JSON response: %v", err)
	}
}