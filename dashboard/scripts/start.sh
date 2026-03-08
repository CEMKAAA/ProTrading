#!/bin/bash
# ProTrading Dashboard - Start Script

set -e

echo "=========================================="
echo "  ProTrading Dashboard - Starting..."
echo "=========================================="

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running. Please start Docker first."
    exit 1
fi

# Create data directory if it doesn't exist
mkdir -p data

# Check for .env file
if [ ! -f ".env" ]; then
    echo "Warning: .env file not found. Creating from example..."
    cp .env.example .env
    echo "Please review and modify .env file as needed."
fi

# Build and start containers
echo "Building Docker images..."
docker-compose build

echo "Starting services..."
docker-compose up -d

# Wait for services to be healthy
echo "Waiting for services to start..."
sleep 5

# Check health
echo "Checking service health..."
if docker-compose ps | grep -q "unhealthy"; then
    echo "Warning: Some services are unhealthy. Check logs with: docker-compose logs"
else
    echo "All services started successfully!"
fi

echo ""
echo "=========================================="
echo "  Dashboard is running!"
echo "=========================================="
echo ""
echo "  Frontend:  http://localhost:3000"
echo "  Backend:   http://localhost:8000"
echo "  API Docs:  http://localhost:8000/docs"
echo ""
echo "  Commands:"
echo "    View logs:     docker-compose logs -f"
echo "    Stop:          docker-compose down"
echo "    Restart:       docker-compose restart"
echo ""
