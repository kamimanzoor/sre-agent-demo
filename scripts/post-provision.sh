#!/bin/bash
# =============================================================================
# post-provision.sh — Runs automatically after azd provision
#
# Configures the SRE Agent using dataplane REST APIs (no srectl dependency):
#   - Uploads knowledge base files
#   - Creates subagents via dataplane v2 API
#   - Creates incident response plan
#   - (Optional) GitHub MCP + additional subagents
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

echo ""
echo "============================================="
echo "  SRE Agent Lab — Post-Provision Setup"
echo "============================================="
echo ""

# ── Read azd outputs ─────────────────────────────────────────────────────────
AGENT_ENDPOINT=$(azd env get-value SRE_AGENT_ENDPOINT 2>/dev/null || echo "")
AGENT_NAME=$(azd env get-value SRE_AGENT_NAME 2>/dev/null || echo "")
RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null || echo "")
CONTAINER_APP_URL=$(azd env get-value CONTAINER_APP_URL 2>/dev/null || echo "")
GITHUB_PAT_VALUE=$(azd env get-value GITHUB_PAT 2>/dev/null || echo "")

if [ -z "$AGENT_ENDPOINT" ] || [ -z "$AGENT_NAME" ]; then
  echo "❌ ERROR: Could not read agent details from azd environment."
  exit 1
fi

echo "📡 Agent: ${AGENT_ENDPOINT}"
echo "📦 RG:    ${RESOURCE_GROUP}"
echo ""

# ── Helper: Get bearer token ─────────────────────────────────────────────────
get_token() {
  az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv 2>/dev/null
}

# ── Helper: Create subagent via dataplane v2 API ─────────────────────────────
create_subagent() {
  local yaml_file="$1"
  local agent_name="$2"
  local token
  token=$(get_token)

  # Convert YAML spec to API JSON using helper script
  python3 "$SCRIPT_DIR/yaml-to-api-json.py" "$yaml_file" "/tmp/${agent_name}-body.json" > /dev/null 2>&1

  local http_code
  http_code=$(curl -s -o /tmp/${agent_name}-resp.txt -w "%{http_code}" \
    -X PUT "${AGENT_ENDPOINT}/api/v2/extendedAgent/agents/${agent_name}" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    --data-binary @"/tmp/${agent_name}-body.json")

  if [ "$http_code" = "200" ] || [ "$http_code" = "201" ] || [ "$http_code" = "204" ]; then
    echo "   ✅ Created: ${agent_name}"
  else
    echo "   ⚠️  ${agent_name} returned HTTP ${http_code}"
    cat "/tmp/${agent_name}-resp.txt" 2>/dev/null | head -3
  fi
  rm -f "/tmp/${agent_name}-body.json" "/tmp/${agent_name}-resp.txt"
}

# ── Step 1: Upload knowledge base files ──────────────────────────────────────
echo "📚 Step 1/4: Uploading knowledge base..."
TOKEN=$(get_token)

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${AGENT_ENDPOINT}/api/v1/AgentMemory/upload" \
  -H "Authorization: Bearer ${TOKEN}" \
  -F "triggerIndexing=true" \
  -F "files=@./knowledge-base/http-500-errors.md;type=text/plain" \
  -F "files=@./knowledge-base/grubify-architecture.md;type=text/plain")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo "   ✅ Uploaded: http-500-errors.md, grubify-architecture.md"
else
  echo "   ⚠️  Upload returned HTTP ${HTTP_CODE}"
fi
echo ""

# ── Step 2: Create incident-handler subagent ─────────────────────────────────
echo "🤖 Step 2/4: Creating incident-handler subagent..."
if [ -n "$GITHUB_PAT_VALUE" ]; then
  echo "   GitHub PAT detected — using full config"
  create_subagent "sre-config/agents/incident-handler-full.yaml" "incident-handler"
else
  echo "   No GitHub PAT — using core config"
  create_subagent "sre-config/agents/incident-handler-core.yaml" "incident-handler"
fi
echo ""

# ── Step 3: Create incident response plan ────────────────────────────────────
echo "🚨 Step 3/4: Creating incident response plan..."
TOKEN=$(get_token)

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PUT "${AGENT_ENDPOINT}/api/v1/incidentplayground/filters/grubify-http-errors" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  --data-binary '{"id":"grubify-http-errors","name":"Grubify HTTP 5xx Errors","priority":"3","titleContains":"5xx","handlingAgent":"incident-handler","agentMode":"autonomous","maxAttempts":3}')

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo "   ✅ Created: grubify-http-errors response plan"
else
  echo "   ⚠️  Response plan returned HTTP ${HTTP_CODE}"
fi
echo ""

# ── Step 4: GitHub integration (optional) ────────────────────────────────────
echo "🔗 Step 4/4: GitHub integration..."

if [ -n "$GITHUB_PAT_VALUE" ]; then
  # Upload triage runbook
  TOKEN=$(get_token)
  curl -s -o /dev/null \
    -X POST "${AGENT_ENDPOINT}/api/v1/AgentMemory/upload" \
    -H "Authorization: Bearer ${TOKEN}" \
    -F "triggerIndexing=true" \
    -F "files=@./knowledge-base/github-issue-triage.md;type=text/plain"
  echo "   ✅ Uploaded: github-issue-triage.md"

  # Create additional subagents
  create_subagent "sre-config/agents/code-analyzer.yaml" "code-analyzer"
  create_subagent "sre-config/agents/issue-triager.yaml" "issue-triager"

  echo ""
  echo "   GitHub integration: ✅ Configured"
else
  echo "   ⏭️  No GITHUB_PAT — skipping"
  echo "   To add later: GITHUB_PAT=<pat> ./scripts/setup-github.sh"
fi
echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
echo "============================================="
echo "  ✅ SRE Agent Lab Setup Complete!"
echo "============================================="
echo ""
echo "  🤖 Portal:  https://sre.azure.com"
echo "  🌐 App:     ${CONTAINER_APP_URL}"
echo "  📦 RG:      ${RESOURCE_GROUP}"
echo ""
echo "  Next: ./scripts/break-app.sh"
echo "============================================="
