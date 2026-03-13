.PHONY: help install dev test test-unit test-integration test-e2e lint format \
        docker-up docker-down docker-build db-migrate db-reset \
        tf-init tf-plan tf-apply clean

# Default target
help:
	@echo "RPV Capital - Development Commands"
	@echo ""
	@echo "Setup:"
	@echo "  make install        Install Python dependencies"
	@echo "  make dev            Start development environment (Docker)"
	@echo ""
	@echo "Testing:"
	@echo "  make test           Run all tests"
	@echo "  make test-unit      Run unit tests only"
	@echo "  make test-integration  Run integration tests"
	@echo "  make test-e2e       Run E2E tests"
	@echo "  make test-cov       Run tests with coverage report"
	@echo ""
	@echo "Code Quality:"
	@echo "  make lint           Run linter (ruff)"
	@echo "  make format         Format code (ruff)"
	@echo "  make typecheck      Run type checker (mypy)"
	@echo ""
	@echo "Docker:"
	@echo "  make docker-up      Start all containers"
	@echo "  make docker-down    Stop all containers"
	@echo "  make docker-build   Build all containers"
	@echo "  make docker-logs    Show container logs"
	@echo ""
	@echo "Database:"
	@echo "  make db-migrate     Run database migrations"
	@echo "  make db-reset       Reset database (WARNING: destroys data)"
	@echo ""
	@echo "Terraform:"
	@echo "  make tf-init        Initialize Terraform"
	@echo "  make tf-plan        Plan Terraform changes"
	@echo "  make tf-apply       Apply Terraform changes"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean          Remove build artifacts and caches"

# =====================================================
# Setup
# =====================================================

install:
	pip install -r requirements.txt
	pip install -e ".[dev]"
	playwright install chromium

dev: docker-up
	@echo "Development environment started!"
	@echo "Bot: http://localhost:8000"
	@echo "PostgreSQL: localhost:5432"
	@echo "LocalStack: localhost:4566"

# =====================================================
# Testing
# =====================================================

test:
	pytest tests/ -v

test-unit:
	pytest tests/unit/ -v

test-integration:
	pytest tests/integration/ -v

test-e2e:
	pytest tests/e2e/ -v

test-cov:
	pytest tests/ -v --cov=bot --cov=motor --cov=lambdas --cov-report=html --cov-report=term-missing
	@echo "Coverage report: htmlcov/index.html"

# =====================================================
# Code Quality
# =====================================================

lint:
	ruff check bot/ motor/ lambdas/ tests/

format:
	ruff check --fix bot/ motor/ lambdas/ tests/
	ruff format bot/ motor/ lambdas/ tests/

typecheck:
	mypy bot/ motor/ lambdas/

# =====================================================
# Docker
# =====================================================

docker-up:
	docker-compose up -d postgres localstack
	@echo "Waiting for PostgreSQL..."
	@sleep 3
	@make db-migrate

docker-down:
	docker-compose down

docker-build:
	docker-compose build

docker-logs:
	docker-compose logs -f

docker-bot:
	docker-compose up -d bot

docker-test:
	docker-compose --profile test run --rm tests

# =====================================================
# Database
# =====================================================

db-migrate:
	@echo "Running migrations..."
	PGPASSWORD=rpv_dev_password psql -h localhost -U rpv -d rpv_capital -f database/migrations/001_initial_schema.sql || true

db-reset:
	@echo "WARNING: This will destroy all data!"
	@read -p "Are you sure? (y/N) " confirm && [ "$$confirm" = "y" ]
	docker-compose down -v
	docker-compose up -d postgres
	@sleep 3
	@make db-migrate

db-shell:
	PGPASSWORD=rpv_dev_password psql -h localhost -U rpv -d rpv_capital

# =====================================================
# Terraform
# =====================================================

TF_ENV ?= dev
TF_DIR = infra/terraform/environments/$(TF_ENV)

tf-init:
	cd $(TF_DIR) && terraform init

tf-plan:
	cd $(TF_DIR) && terraform plan

tf-apply:
	cd $(TF_DIR) && terraform apply

tf-destroy:
	cd $(TF_DIR) && terraform destroy

# =====================================================
# Bot Development
# =====================================================

run-bot:
	uvicorn bot.main:app --host 0.0.0.0 --port 8000 --reload

run-esaj:
	python -m esaj_task.main

# =====================================================
# Lambda Local Testing
# =====================================================

run-crawler:
	python -c "from lambdas.crawler_prefeitura.handler import lambda_handler; lambda_handler({}, None)"

run-outbound:
	python -c "from lambdas.outbound_scheduler.handler import lambda_handler; lambda_handler({}, None)"

# =====================================================
# Cleanup
# =====================================================

clean:
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".mypy_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".ruff_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "htmlcov" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
	find . -type f -name ".coverage" -delete 2>/dev/null || true
	rm -rf .eggs/ *.egg-info/ build/ dist/
