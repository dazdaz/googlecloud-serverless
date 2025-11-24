# Gateway Service - Python
# This Dockerfile builds the Python-based gateway service
# that orchestrates calls to other microservices

FROM python:3.12-slim

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .

# Use non-root user for security (use UID 65532 to avoid conflicts)
RUN useradd -m -u 65532 appuser
USER appuser

# Expose port
EXPOSE 8080

# Run with gunicorn for production
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "8", "--timeout", "0", "main:app"]