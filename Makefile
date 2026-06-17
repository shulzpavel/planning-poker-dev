.PHONY: test backend-test frontend-test frontend-e2e frontend-build check install clean deploy-web-prod

install:
	pip3 install -r ../planning-poker-voting-service/requirements.txt

test: backend-test frontend-test

backend-test:
	PYTHONPATH=../planning-poker-voting-service python3 -m pytest -q -p no:cacheprovider

frontend-test:
	cd ../planning-poker-web && npm run test

frontend-e2e:
	cd ../planning-poker-web && npm run test:e2e

frontend-build:
	cd ../planning-poker-web && npm run build

check: backend-test frontend-test frontend-build
	PYTHONPATH=../planning-poker-voting-service python3 -m compileall -q ../planning-poker-voting-service
	docker compose config >/tmp/planning-poker-compose.yml
	docker compose -f docker-compose.prod.yml --env-file infra/deploy/prod.env.example config >/tmp/planning-poker-prod-compose.yml

clean:
	find . -type d -name __pycache__ -exec rm -r {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete
	find . -type f -name ".pytest_cache" -delete
	rm -rf .coverage htmlcov/ .pytest_cache/

deploy-web-prod:
	./infra/deploy/deploy-web-prod.sh
