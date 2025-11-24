# User Service - Go
# Multi-stage build for optimal image size

# Build stage
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY main.go ./

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o user-service .

# Runtime stage
FROM alpine:3.19

# Install CA certificates for HTTPS
RUN apk --no-cache add ca-certificates

WORKDIR /app

# Copy the binary from builder
COPY --from=builder /app/user-service .

# Use non-root user with a different UID (65532 is standard for nonroot)
RUN adduser -D -u 65532 appuser
USER appuser

# Expose port
EXPOSE 8080

# Run the service
CMD ["./user-service"]