#!/usr/bin/env bash
#
# External verification of a deployed PrestaShop instance.
# Run from your laptop:  ./scripts/verify-deployment.sh http://ec2-1-2-3-4.compute-1.amazonaws.com/
#
set -uo pipefail

BASE_URL="${1:-}"
if [[ -z $BASE_URL ]]; then
  echo "usage: $0 <storefront-url>"
  exit 2
fi
BASE_URL="${BASE_URL%/}"
[[ $BASE_URL == http* ]] || BASE_URL="http://${BASE_URL}"

pass=0
fail=0

check() {
  local label="$1" expected="$2" url="$3" body_check="${4:-}"
  local out code body
  body="$(mktemp)"
  out="$(curl -sSL -m 20 -o "$body" -w '%{http_code}' "$url" 2>&1)"
  code="${out##*$'\n'}"

  local ok=0
  [[ "$code" == "$expected" ]] && ok=1
  if [[ -n $body_check ]] && ! grep -qi -- "$body_check" "$body"; then
    ok=0
  fi

  if [[ $ok -eq 1 ]]; then
    printf 'PASS  %-52s HTTP %s\n' "$label" "$code"
    pass=$((pass + 1))
  else
    printf 'FAIL  %-52s got HTTP %s, wanted %s\n' "$label" "$code" "$expected"
    fail=$((fail + 1))
  fi
  rm -f "$body"
}

echo "Verifying $BASE_URL"
echo "--------------------------------------------------------------------"
check "Storefront responds"                  "200" "$BASE_URL/"            "prestashop"
check "Installer directory is gone"          "403" "$BASE_URL/install/"
check "Config directory not exposed"         "403" "$BASE_URL/config/settings.inc.php"
check "Static theme asset served"            "200" "$BASE_URL/themes/classic/assets/css/theme.css"

echo "--------------------------------------------------------------------"
echo "Passed: $pass   Failed: $fail"
echo
cat <<'EOT'
Manual checks that this script cannot do:
  * Open the /adminXXXX URL printed by: sudo cat /root/prestashop-summary.txt
  * Prove the database is remote (run ON the instance):
        ss -ltnp | grep 3306 || echo "no MySQL listening locally - database is external"
        mysql -h "$(grep DB_HOST /etc/prestashop/app.env | cut -d= -f2 | tr -d '\"')" \
              -u ps_app -p prestashop -e 'SELECT @@hostname, @@version;'
    @@hostname must look like an RDS instance (ip-10-20-x-x...), not the web server.
EOT
[[ $fail -eq 0 ]]
