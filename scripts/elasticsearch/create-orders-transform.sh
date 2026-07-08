#!/usr/bin/env bash
# Create and start the OTel Demo business-orders Elasticsearch transform.
#
# Prerequisites:
#   export ES_URL="https://<project>.es.<region>.aws.elastic.cloud"
#   export ES_API_KEY="<base64-api-key>"   # from vars.yml elastic_api_key
#
# Usage:
#   ./scripts/elasticsearch/create-orders-transform.sh
#   ./scripts/elasticsearch/create-orders-transform.sh --stop   # stop transform
#   ./scripts/elasticsearch/create-orders-transform.sh --reset  # re-backfill dest index
#   ./scripts/elasticsearch/create-orders-transform.sh --delete # stop + delete transform + dest index

set -euo pipefail

TRANSFORM_ID="otel-demo-orders-latest"
DEST_INDEX="orders-otel-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${ES_URL:?Set ES_URL (Elasticsearch API endpoint, not ingest)}"
: "${ES_API_KEY:?Set ES_API_KEY}"

auth_header() {
  printf 'Authorization: ApiKey %s' "${ES_API_KEY}"
}

es_curl() {
  curl -sS -f -H "$(auth_header)" -H "Content-Type: application/json" "$@"
}

case "${1:-}" in
  --stop)
    es_curl -X POST "${ES_URL}/_transform/${TRANSFORM_ID}/_stop?wait_for_completion=true&timeout=60s"
    echo "Transform ${TRANSFORM_ID} stopped."
    exit 0
    ;;
  --delete)
    es_curl -X POST "${ES_URL}/_transform/${TRANSFORM_ID}/_stop?wait_for_completion=true&timeout=60s" || true
    es_curl -X DELETE "${ES_URL}/_transform/${TRANSFORM_ID}"
    es_curl -X DELETE "${ES_URL}/${DEST_INDEX}" || true
    es_curl -X DELETE "${ES_URL}/_ingest/pipeline/orders-otel-demo-normalize" || true
    echo "Transform ${TRANSFORM_ID}, dest index ${DEST_INDEX}, and pipeline removed."
    exit 0
    ;;
  --reset)
    es_curl -X POST "${ES_URL}/_transform/${TRANSFORM_ID}/_stop?wait_for_completion=true&timeout=120s" || true
    es_curl -X DELETE "${ES_URL}/${DEST_INDEX}" || true
    es_curl -X POST "${ES_URL}/_transform/${TRANSFORM_ID}/_reset"
    es_curl -X POST "${ES_URL}/_transform/${TRANSFORM_ID}/_start"
    echo "Transform ${TRANSFORM_ID} reset and restarted."
    exit 0
    ;;
esac

echo "==> Creating ingest pipeline orders-otel-demo-normalize"
es_curl -X PUT "${ES_URL}/_ingest/pipeline/orders-otel-demo-normalize" \
  --data-binary @"${SCRIPT_DIR}/orders-otel-demo-pipeline.json"

echo "==> Creating transform ${TRANSFORM_ID}"
es_curl -X PUT "${ES_URL}/_transform/${TRANSFORM_ID}" \
  --data-binary @"${SCRIPT_DIR}/orders-otel-demo-transform.json"

echo "==> Starting transform ${TRANSFORM_ID}"
es_curl -X POST "${ES_URL}/_transform/${TRANSFORM_ID}/_start"

echo "==> Transform stats"
es_curl "${ES_URL}/_transform/${TRANSFORM_ID}/_stats" | python3 -m json.tool 2>/dev/null || true

cat <<EOF

Done.
  Transform ID : ${TRANSFORM_ID}
  Dest index   : ${DEST_INDEX}
  Data view    : index pattern "${DEST_INDEX}" (timestamp: @timestamp)

Verify in Discover:
  business.order.id: *

Or:
  curl -H "Authorization: ApiKey \$ES_API_KEY" \\
    "${ES_URL}/${DEST_INDEX}/_count"
EOF
