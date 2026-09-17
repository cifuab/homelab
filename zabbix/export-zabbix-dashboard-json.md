# Export Zabbix Dashboard as JSON Using the API

This guide shows how to export an existing Zabbix dashboard as a raw JSON object using the Zabbix API.

This is useful when the Zabbix frontend does not show a dashboard **Export** button.

---

## Example Dashboard URL

Example dashboard URL:

```text
http://192.168.0.58:8081/zabbix.php?action=dashboard.view&dashboardid=402&from=now-5m&to=now
```

From this URL:

```text
Dashboard ID = 402
Zabbix frontend base URL = http://192.168.0.58:8081
Zabbix API URL = http://192.168.0.58:8081/api_jsonrpc.php
```

---

## 1. Install Required Tool

Install `jq` for formatting JSON output:

```bash
sudo apt update
sudo apt install -y jq
```

---

## 2. Set Zabbix Variables

Update these values if your Zabbix URL or dashboard ID is different:

```bash
ZABBIX_URL="http://192.168.0.58:8081/api_jsonrpc.php"
DASHBOARD_ID="402"
```

---

## 3. Login to Zabbix API

Replace the password with your real Zabbix password:

```bash
AUTH_TOKEN=$(curl -s -X POST "$ZABBIX_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "user.login",
    "params": {
      "username": "Admin",
      "password": "zabbix"
    },
    "id": 1
  }' | jq -r '.result')

echo "$AUTH_TOKEN"
```

If the login works, the command prints a long authentication token.

If it prints:

```text
null
```

try the older Zabbix API login format:

```bash
AUTH_TOKEN=$(curl -s -X POST "$ZABBIX_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "user.login",
    "params": {
      "user": "Admin",
      "password": "zabbix"
    },
    "id": 1
  }' | jq -r '.result')

echo "$AUTH_TOKEN"
```

---

## 4. Verify Available Dashboards

Before exporting, confirm that the dashboard is visible through the API:

```bash
curl -s -X POST "$ZABBIX_URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"dashboard.get\",
    \"params\": {
      \"output\": [\"dashboardid\", \"name\"]
    },
    \"auth\": \"$AUTH_TOKEN\",
    \"id\": 2
  }" | jq
```

Look for your dashboard ID:

```text
402
```

---

## 5. Export the Dashboard as JSON

Run this command to export dashboard `402`:

```bash
curl -s -X POST "$ZABBIX_URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"dashboard.get\",
    \"params\": {
      \"dashboardids\": [\"$DASHBOARD_ID\"],
      \"output\": \"extend\",
      \"selectPages\": \"extend\",
      \"selectUsers\": \"extend\",
      \"selectUserGroups\": \"extend\"
    },
    \"auth\": \"$AUTH_TOKEN\",
    \"id\": 3
  }" | jq '.result[0]' > zabbix-dashboard-402-export.json
```

---

## 6. Validate the Exported File

Check that the file exists:

```bash
ls -lh zabbix-dashboard-402-export.json
```

Check the dashboard name:

```bash
cat zabbix-dashboard-402-export.json | jq '.name'
```

If the output is `null`, verify:

- the dashboard ID is correct
- the API URL is correct
- the authenticated user has access to the dashboard
- the API token was generated successfully

---

## 7. Save the Export in the Homelab Repository

Recommended repo structure:

```text
homelab/
└── zabbix/
    └── dashboards/
        └── opnsense-zabbix-dashboard.json
```

Create the folder and move the export:

```bash
mkdir -p zabbix/dashboards

mv zabbix-dashboard-402-export.json \
   zabbix/dashboards/opnsense-zabbix-dashboard.json
```

Commit the dashboard export:

```bash
git add zabbix/dashboards/opnsense-zabbix-dashboard.json
git commit -m "Add Zabbix dashboard API export"
git push
```

---

## 8. Optional: One-Shot Export Script

You can also create a reusable script:

```bash
cat > export-zabbix-dashboard.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ZABBIX_URL="${ZABBIX_URL:-http://192.168.0.58:8081/api_jsonrpc.php}"
DASHBOARD_ID="${DASHBOARD_ID:-402}"
ZABBIX_USER="${ZABBIX_USER:-Admin}"
ZABBIX_PASSWORD="${ZABBIX_PASSWORD:-zabbix}"
OUTPUT_FILE="${OUTPUT_FILE:-zabbix-dashboard-${DASHBOARD_ID}-export.json}"

echo "[INFO] Logging in to Zabbix API..."

AUTH_TOKEN=$(curl -s -X POST "$ZABBIX_URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"user.login\",
    \"params\": {
      \"username\": \"$ZABBIX_USER\",
      \"password\": \"$ZABBIX_PASSWORD\"
    },
    \"id\": 1
  }" | jq -r '.result')

if [[ "$AUTH_TOKEN" == "null" || -z "$AUTH_TOKEN" ]]; then
  echo "[ERROR] Login failed. Check ZABBIX_URL, ZABBIX_USER, and ZABBIX_PASSWORD."
  exit 1
fi

echo "[INFO] Exporting dashboard ID: $DASHBOARD_ID"

curl -s -X POST "$ZABBIX_URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"dashboard.get\",
    \"params\": {
      \"dashboardids\": [\"$DASHBOARD_ID\"],
      \"output\": \"extend\",
      \"selectPages\": \"extend\",
      \"selectUsers\": \"extend\",
      \"selectUserGroups\": \"extend\"
    },
    \"auth\": \"$AUTH_TOKEN\",
    \"id\": 2
  }" | jq '.result[0]' > "$OUTPUT_FILE"

if [[ ! -s "$OUTPUT_FILE" ]]; then
  echo "[ERROR] Export file is empty."
  exit 1
fi

if [[ "$(jq -r '.dashboardid // empty' "$OUTPUT_FILE")" != "$DASHBOARD_ID" ]]; then
  echo "[WARNING] Export completed, but dashboard ID in file does not match expected ID."
fi

echo "[INFO] Dashboard exported to: $OUTPUT_FILE"
jq '.name' "$OUTPUT_FILE"
EOF

chmod +x export-zabbix-dashboard.sh
```

Run it:

```bash
./export-zabbix-dashboard.sh
```

Or override values at runtime:

```bash
ZABBIX_URL="http://192.168.0.58:8081/api_jsonrpc.php" \
DASHBOARD_ID="402" \
ZABBIX_USER="Admin" \
ZABBIX_PASSWORD="your-real-password" \
OUTPUT_FILE="opnsense-zabbix-dashboard.json" \
./export-zabbix-dashboard.sh
```

---

## Notes

This method exports the dashboard as a raw Zabbix API object.

It is useful for:

- backing up dashboard layout
- version-controlling dashboard structure
- storing dashboard evidence in GitHub
- documenting a homelab monitoring project

It is not the same as the official Zabbix frontend YAML/XML export available in newer Zabbix versions.
