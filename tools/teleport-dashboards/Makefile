# teleport-dashboards — render and validate Grafana dashboards for a Teleport cluster.
#
# Dashboards in dashboards/ are the SOURCE set. Render them for a target
# deployment before installing: scripts/render-dashboards.py drops panels whose
# capabilities the cluster lacks, so nothing ships that cannot resolve a
# datasource.

PROFILE ?= full-enterprise
PROM_URL ?= http://localhost:9090

.PHONY: help render validate validate-live exporter-test clean

## help          Show this help
help:
	@grep -E '^##' Makefile | sed 's/## /  /'

## render        Render dashboards for a profile into the chart (PROFILE=oss-postgres)
render:
	@./scripts/render-dashboards.py --profile profiles/$(PROFILE).yaml --out chart/dashboards

## exporter-test Build and test the usage exporter (Go)
exporter-test:
	@cd exporter && go build ./... && go vet ./... && go test ./...

## validate      Everything offline: Go, renderer tests, validator self-test, every profile
validate: exporter-test
	@echo "== renderer unit tests"
	@python3 scripts/test_render_dashboards.py
	@echo "== validator self-test (must still detect its planted bugs)"
	@out=$$(./scripts/validate-dashboards.py --offline scripts/testdata/dashboard-selftest.json || true); \
	 for c in S2-overlap S3-undeclared-var S5-dangling-link S6-unpinned-datasource L3-count-condition; do \
	   echo "$$out" | grep -q "$$c" || { echo "VALIDATOR REGRESSED: $$c not detected"; exit 1; }; \
	 done; echo "   offline checks detected"
	@echo "== source dashboards"
	@./scripts/validate-dashboards.py --offline --quiet
	@echo "== each capability profile"
	@for p in profiles/*.yaml; do \
	   n=$$(basename $$p .yaml); \
	   ./scripts/render-dashboards.py --profile $$p --out rendered/$$n >/dev/null; \
	   if ls rendered/$$n/*.json >/dev/null 2>&1; then \
	     printf '   %-18s ' "$$n"; ./scripts/validate-dashboards.py --offline --quiet rendered/$$n/*.json | tail -1; \
	   else printf '   %-18s no dashboards (expected where no capability is available)\n' "$$n"; fi; \
	 done

## validate-live Execute every query against a live cluster (needs kubectl + Prometheus)
validate-live:
	@./scripts/validate-dashboards.py --prom $(PROM_URL)

## clean         Remove rendered output
clean:
	@rm -rf rendered chart/dashboards
