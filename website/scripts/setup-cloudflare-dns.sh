#!/usr/bin/env bash
set -euo pipefail

# 将 GitHub Pages 自定义域名指向 github.io。
# 需要 Cloudflare API Token（Zone.Read + Zone.DNS Edit；提供 CLOUDFLARE_ZONE_ID 可免 Zone.Read），
# 不要把 token 写进仓库。
#
#   export CLOUDFLARE_API_TOKEN=...
#   website/scripts/setup-cloudflare-dns.sh
#
# 可选：
#   CLOUDFLARE_ZONE_NAME=looplooptech.com
#   CLOUDFLARE_RECORD_NAME=pinshell
#   CLOUDFLARE_CNAME_TARGET=niyongsheng.github.io
#   CLOUDFLARE_PROXIED=false        # GitHub Pages 建议 DNS only
#   CLOUDFLARE_ZONE_ID=...          # 跳过 zone 查询

ZONE_NAME="${CLOUDFLARE_ZONE_NAME:-looplooptech.com}"
RECORD_NAME="${CLOUDFLARE_RECORD_NAME:-pinshell}"
TARGET="${CLOUDFLARE_CNAME_TARGET:-niyongsheng.github.io}"
PROXIED="${CLOUDFLARE_PROXIED:-false}"
API="https://api.cloudflare.com/client/v4"

: "${CLOUDFLARE_API_TOKEN:?export CLOUDFLARE_API_TOKEN with Zone.DNS Edit permission}"

json_field() {
  python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception as exc:
    sys.exit("invalid Cloudflare response: %s" % exc)
if not data.get("success"):
    sys.exit("Cloudflare API error: %s" % data.get("errors"))
value = data
for key in sys.argv[1].split("."):
    if isinstance(value, list):
        value = value[int(key)]
    else:
        value = value[key]
print(value)
' "$1"
}

auth=(-H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json")

zone_id="${CLOUDFLARE_ZONE_ID:-}"
if [[ -z "${zone_id}" ]]; then
  zone_id=$(curl -fsS "${auth[@]}" \
    "${API}/zones?name=${ZONE_NAME}" | json_field 'result.0.id')
fi
[[ -n "${zone_id}" ]] || {
  echo "error: zone ${ZONE_NAME} not found (or token lacks Zone.Read)" >&2
  exit 1
}

name="${RECORD_NAME}.${ZONE_NAME}"
record_json=$(curl -fsS "${auth[@]}" \
  "${API}/zones/${zone_id}/dns_records?name=${name}")
record_id=$(python3 -c '
import json, sys
data = json.load(sys.stdin)
records = data.get("result") or []
if not data.get("success"):
    sys.exit("Cloudflare API error: %s" % data.get("errors"))
if records:
    bad = [r for r in records if r.get("type") != "CNAME"]
    if bad:
        sys.exit("error: %s already has non-CNAME records: %s" %
                 (sys.argv[1], ", ".join(r.get("type", "?") for r in bad)))
    print(records[0]["id"])
' "${name}" <<<"${record_json}")

payload=$(python3 -c '
import json, sys
print(json.dumps({
    "type": "CNAME",
    "name": sys.argv[1],
    "content": sys.argv[2],
    "ttl": 1,
    "proxied": sys.argv[3].lower() == "true",
}))
' "${RECORD_NAME}" "${TARGET}" "${PROXIED}")

if [[ -n "${record_id}" ]]; then
  echo "Updating ${name} -> ${TARGET} (proxied=${PROXIED})"
  curl -fsS -X PUT "${auth[@]}" \
    "${API}/zones/${zone_id}/dns_records/${record_id}" \
    --data "${payload}" | json_field 'result.id' >/dev/null
else
  echo "Creating ${name} -> ${TARGET} (proxied=${PROXIED})"
  curl -fsS -X POST "${auth[@]}" \
    "${API}/zones/${zone_id}/dns_records" \
    --data "${payload}" | json_field 'result.id' >/dev/null
fi

echo "Done. Check: dig +short ${name} CNAME"
echo "Then set GitHub Pages → Custom domain to ${name} and enable HTTPS."
