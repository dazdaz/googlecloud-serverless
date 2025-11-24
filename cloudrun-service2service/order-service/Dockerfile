# Order Service - Node.js
# Simple Dockerfile for Cloud Run

FROM node:20-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies (using --omit=dev instead of deprecated --production)
RUN npm install --omit=dev

# Copy application code
COPY index.js ./

# Use the built-in node user (already exists with UID 1000 in node:alpine)
USER node

# Expose port
EXPOSE 8080

# Run the service
CMD ["node", "index.js"]