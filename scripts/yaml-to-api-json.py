#!/usr/bin/env python3
"""Convert YAML subagent spec to JSON for the dataplane v2 API.

The API expects an envelope: { name, type, tags, owner, properties: { ... } }
where properties contains camelCase fields matching ExtendedAgentSpecV2.
YAML uses snake_case (system_prompt, handoff_description, etc.) but the API
uses camelCase (instructions, handoffDescription, etc.).
"""
import yaml, json, sys

yaml_file = sys.argv[1]
output_file = sys.argv[2] if len(sys.argv) > 2 else "/tmp/subagent-body.json"

with open(yaml_file) as f:
    data = yaml.safe_load(f)

spec = data["spec"]

# Build the API envelope matching what srectl sends
api_body = {
    "name": spec["name"],
    "type": "ExtendedAgent",
    "tags": [],
    "owner": "",
    "properties": {
        "instructions": spec.get("system_prompt", ""),
        "handoffDescription": spec.get("handoff_description", ""),
        "handoffs": spec.get("handoffs", []),
        "tools": spec.get("tools", []),
        "mcpTools": spec.get("mcp_tools", []),
        "allowParallelToolCalls": True,
        "enableSkills": True,
    }
}

with open(output_file, "w") as f:
    json.dump(api_body, f)

print(f"Wrote {output_file} ({len(json.dumps(api_body))} bytes)")
