.PHONY: test backend-test voting-test jira-test frontend-test frontend-e2e frontend-build check install clean deploy-web-prod

VOTING_DIR := ../planning-poker-voting-service
JIRA_DIR := ../planning-poker-jira-service
WEB_DIR := ../planning-poker-web
VOTING_VENDOR := $(VOTING_DIR)/vendor/planning-poker-common
JIRA_VENDOR := $(JIRA_DIR)/vendor/planning-poker-common
BACKEND_PYTHONPATH := $(VOTING_VENDOR):$(JIRA_VENDOR):$(VOTING_DIR):$(JIRA_DIR)

install:
	pip3 install -r $(VOTING_DIR)/requirements.txt
	pip3 install -r $(JIRA_DIR)/requirements.txt

test: backend-test frontend-test

backend-test: install voting-test jira-test

voting-test:
	PYTHONPATH=$(BACKEND_PYTHONPATH) python3 -m pytest -q -p no:cacheprovider $(VOTING_DIR)/tests

jira-test:
	PYTHONPATH=$(BACKEND_PYTHONPATH) python3 -m pytest -q -p no:cacheprovider $(JIRA_DIR)/tests

frontend-test:
	cd $(WEB_DIR) && npm run test

frontend-e2e:
	cd $(WEB_DIR) && npm run test:e2e

frontend-build:
	cd $(WEB_DIR) && npm run build

check: backend-test frontend-test frontend-build
	PYTHONPATH=$(BACKEND_PYTHONPATH) python3 -m compileall -q $(VOTING_DIR)/app $(VOTING_DIR)/services $(VOTING_DIR)/config.py $(VOTING_DIR)/session_store.py
	PYTHONPATH=$(BACKEND_PYTHONPATH) python3 -m compileall -q $(JIRA_DIR)/app $(JIRA_DIR)/services $(JIRA_DIR)/config.py $(JIRA_DIR)/jira_fields.py
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
