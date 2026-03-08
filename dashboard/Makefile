# ProTrading Dashboard - Makefile
# Common commands for development and deployment

.PHONY: help install dev build start stop logs clean test lint format

# Default target
help:
	@echo "ProTrading Dashboard - Available Commands"
	@echo "=========================================="
	@echo ""
	@echo "Development:"
	@echo "  make install     - Install all dependencies"
	@echo "  make dev         - Start development environment"
	@echo "  make dev-backend - Start backend only (with hot reload)"
	@echo "  make dev-frontend- Start frontend only (with hot reload)"
	@echo ""
	@echo "Docker:"
	@echo "  make build       - Build Docker images"
	@echo "  make start       - Start all services"
	@echo "  make stop        - Stop all services"
	@echo "  make restart     - Restart all services"
	@echo "  make logs        - View logs"
	@echo "  make logs-backend- View backend logs"
	@echo "  make logs-frontend- View frontend logs"
	@echo ""
	@echo "Testing & Quality:"
	@echo "  make test        - Run all tests"
	@echo "  make lint        - Run linters"
	@echo "  make format      - Format code"
	@echo ""
	@echo "Maintenance:"
	@echo "  make clean       - Clean build artifacts"
	@echo "  make reset       - Reset database and clean"

# ===================
# Development
# ===================

install:
	@echo "Installing backend dependencies..."
	cd backend && pip install -r requirements.txt
	@echo "Installing frontend dependencies..."
	cd frontend && npm install
	@echo "Dependencies installed successfully!"

dev:
	docker-compose -f docker-compose.dev.yml up --build

dev-backend:
	cd backend && uvicorn dashboard.backend.main:app --reload --host 0.0.0.0 --port 8000

dev-frontend:
	cd frontend && npm run dev

# ===================
# Docker Commands
# ===================

build:
	docker-compose build

start:
	docker-compose up -d

stop:
	docker-compose down

restart:
	docker-compose down && docker-compose up -d

logs:
	docker-compose logs -f

logs-backend:
	docker-compose logs -f backend

logs-frontend:
	docker-compose logs -f frontend

# ===================
# Testing & Quality
# ===================

test:
	@echo "Running backend tests..."
	cd backend && pytest -v --cov=. --cov-report=html
	@echo "Running frontend tests..."
	cd frontend && npm run test

lint:
	@echo "Linting backend..."
	cd backend && flake8 . && mypy .
	@echo "Linting frontend..."
	cd frontend && npm run lint

format:
	@echo "Formatting backend..."
	cd backend && black . && isort .
	@echo "Formatting frontend..."
	cd frontend && npm run format

# ===================
# Maintenance
# ===================

clean:
	@echo "Cleaning build artifacts..."
	rm -rf backend/__pycache__
	rm -rf backend/.pytest_cache
	rm -rf backend/.mypy_cache
	rm -rf backend/htmlcov
	rm -rf frontend/dist
	rm -rf frontend/node_modules/.cache
	docker-compose down -v --remove-orphans
	@echo "Cleanup complete!"

reset:
	@echo "Resetting database..."
	rm -f data/*.db
	rm -f dashboard/data/*.db
	@echo "Database reset complete!"
	$(MAKE) clean
