#!/usr/bin/env python3
"""Convert YAML subagent spec to JSON for the dataplane v2 API."""
import yaml, json, sys

yaml_file = sys.argv[1]
output_file = sys.argv[2] if len(sys.argv) > 2 else "/tmp/subagent-body.json"

with open(yaml_file) as f:
    data = yaml.safe_load(f)

spec = data["spec"]

api_body = {
    "name": spec["name"],
    "system_prompt": spec.get("system_prompt", ""),
    "handoff_description": spec.get("handoff_description", ""),
    "handoffs": [],
    "tools": spec.get("tools", []),
    "mcp_tools": spec.get("mcp_tools", []),
    "agent_type": spec.get("agent_type", "Autonomous"),
}

with open(output_file, "w") as f:
    json.dump(api_body, f)

print(f"Wrote {output_file} ({len(json.dumps(api_body))} bytes)")
