#!/usr/bin/env bash
set -Eeuo pipefail

JOB_ID="zoukas_r13_build_20260822"
PACKAGE_ID="ZOUKASPLAY_R13_FINAL_MOBILE_MAPS_SERVER_VALIDATED_20260822"
ACTIVE="/mnt/HC_Volume_106575984/zoukasplay/staging/zoukasplay-r26-native-silo-20260819T154055Z"
R9="/mnt/HC_Volume_106575984/zoukasplay/staging/ZOUKASPLAY_R9_MOBILE_VISUAL_TRUTHFUL_QA_20260822T093204Z"
STAGING="/mnt/HC_Volume_106575984/zoukasplay/staging"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
WORK="$STAGING/${PACKAGE_ID}_PREBUILD_${STAMP}"
SRC="$WORK/source"
EVIDENCE="$WORK/evidence"
PACKAGE_ROOT="$WORK/package/$PACKAGE_ID"
DELIVERY_DIR="/root/zoukas-deliveries"
STATUS_FILE="/root/zr13_jobs/${JOB_ID}.status.json"
LOG_FILE="/root/zr13_jobs/${JOB_ID}.log"
RUNTIME_PID=""
CURRENT_STAGE="PREFLIGHT"

mkdir -p /root/zr13_jobs "$WORK" "$EVIDENCE" "$PACKAGE_ROOT" "$DELIVERY_DIR"

write_status() {
  local state="$1"
  local detail="$2"
  STATE_VALUE="$state" DETAIL_VALUE="$detail" STAGE_VALUE="$CURRENT_STAGE" \
  WORK_VALUE="$WORK" SRC_VALUE="$SRC" EVIDENCE_VALUE="$EVIDENCE" \
  PACKAGE_VALUE="$PACKAGE_ID" DELIVERY_VALUE="$DELIVERY_DIR/${PACKAGE_ID}.zip" \
  python3 - "$STATUS_FILE" <<'PY'
import json, os, sys
payload={
  "job_id":"zoukas_r13_build_20260822",
  "package_id":os.environ["PACKAGE_VALUE"],
  "state":os.environ["STATE_VALUE"],
  "stage":os.environ["STAGE_VALUE"],
  "detail":os.environ["DETAIL_VALUE"],
  "work":os.environ["WORK_VALUE"],
  "candidate":os.environ["SRC_VALUE"],
  "evidence":os.environ["EVIDENCE_VALUE"],
  "zip_path":os.environ["DELIVERY_VALUE"],
}
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(payload,ensure_ascii=False,indent=2)+"\n")
PY
}

cleanup() {
  if [[ -n "$RUNTIME_PID" ]]; then
    kill "$RUNTIME_PID" >/dev/null 2>&1 || true
    wait "$RUNTIME_PID" >/dev/null 2>&1 || true
    RUNTIME_PID=""
  fi
}
fail() {
  local rc="$1"
  local line="$2"
  trap - ERR
  cleanup
  write_status "FAILED" "Failure at stage $CURRENT_STAGE, line $line, rc=$rc"
  echo "STATUS_FINAL=FAILED"
  echo "FAILED_STAGE=$CURRENT_STAGE"
  echo "BLOCKER_LINE=$line"
  echo "BLOCKER_RC=$rc"
  exit "$rc"
}
trap 'fail "$?" "$LINENO"' ERR
trap cleanup EXIT

write_status "RUNNING" "Starting server-side R13 prebuild"

CURRENT_STAGE="PREFLIGHT"
for p in "$ACTIVE" "$R9" "$ACTIVE/src" "$R9/src" "$ACTIVE/node_modules" "$R9/scripts/r12-full-matrix-qa.mjs" "$R9/scripts/r12-global-maps-qa.mjs"; do
  [[ -e "$p" ]]
done
command -v zip >/dev/null
command -v unzip >/dev/null
command -v sha256sum >/dev/null
command -v python3 >/dev/null
[[ -x /usr/bin/chromium-browser ]]

cat > "$EVIDENCE/EXPECTED_ACTIVE_BASELINE.sha256" <<'EOF_BASELINE'
bd4e0651a25fdb2ca5ebe5a904391221cc6feb2d3b33c11bdf02660696a232dd  src/components/BudgetCalculator.astro
285b06b587450da159153a8ffaf3890c833d3fbe8e9296312dd8a704dcec37a4  src/components/MobileFABs.astro
095c98cf25a8704b17cb366127a0fa081a438f465e90242cc21e9c07c09882f1  src/components/VerifiedReviews.astro
1d3af6719c2401bb89e03948b6d4fb21fda98a488357b30409cc11bbf4e48750  src/layouts/BaseLayout.astro
3a493ce54f761c7366bd52319016715f3a2f17bcc12ca3699b228d928f9b0900  src/pages/index.astro
1e20bd209af23f8136f5a09bba1cee7b07b538df7863c0b2c45e2ae5ece8c5cd  src/pages/pachete/index.astro
770dad152a0930b4c3c35b445d1d38a83c9dfa30cd9dfedcdc0cf5acc3dc8165  src/styles/global.css
EOF_BASELINE
(
  cd "$ACTIVE"
  sha256sum -c "$EVIDENCE/EXPECTED_ACTIVE_BASELINE.sha256"
) | tee "$EVIDENCE/baseline.log"

CURRENT_STAGE="COPY_SERVER_SOURCE"
write_status "RUNNING" "Copying canonical Hetzner source into isolated candidate"
mkdir -p "$SRC"
if command -v rsync >/dev/null 2>&1; then
  rsync -a \
    --exclude='/node_modules' \
    --exclude='/dist' \
    --exclude='/.astro' \
    --exclude='/backups' \
    --exclude='/.r5*' \
    "$ACTIVE/" "$SRC/"
else
  cp -a --reflink=auto "$ACTIVE/." "$SRC/"
  rm -rf "$SRC/node_modules" "$SRC/dist" "$SRC/.astro" "$SRC/backups"
fi
ln -s "$ACTIVE/node_modules" "$SRC/node_modules"

CURRENT_STAGE="APPLY_R13_PAYLOAD"
write_status "RUNNING" "Applying server-side mobile, reviews, Mpass, calculator and Maps changes"
for rel in \
  src/components/BudgetCalculator.astro \
  src/components/MobileFABs.astro \
  src/components/VerifiedReviews.astro \
  src/layouts/BaseLayout.astro \
  src/pages/index.astro \
  src/pages/pachete/index.astro \
  src/styles/global.css; do
  mkdir -p "$(dirname "$SRC/$rel")"
  cp -a "$R9/$rel" "$SRC/$rel"
done
mkdir -p "$SRC/scripts"
cp -a "$R9/scripts/r12-full-matrix-qa.mjs" "$SRC/scripts/r13-full-matrix-qa.mjs"
cp -a "$R9/scripts/r12-global-maps-qa.mjs" "$SRC/scripts/r13-global-maps-qa.mjs"

python3 - "$SRC/src/components/MobileFABs.astro" "$SRC/scripts/r13-full-matrix-qa.mjs" "$SRC/scripts/r13-global-maps-qa.mjs" <<'PY'
from pathlib import Path
import sys
mobile, full, maps = map(Path, sys.argv[1:])
m=mobile.read_text(encoding="utf-8")
assert m.count("<span>Locație</span>")==1, m.count("<span>Locație</span>")
m=m.replace("<span>Locație</span>","<span>Maps</span>")
mobile.write_text(m,encoding="utf-8")

f=full.read_text(encoding="utf-8")
f=f.replace("ZOUKASPLAY_R12_COMPLETE_MOBILE_MAPS_FULL_MATRIX_QA_20260822","ZOUKASPLAY_R13_FINAL_MOBILE_MAPS_FULL_MATRIX_QA_20260822")
f=f.replace("r12-","r13-")
full.write_text(f,encoding="utf-8")

g=maps.read_text(encoding="utf-8")
assert "before.triggerText.includes('Locație')" in g
g=g.replace("before.triggerText.includes('Locație')","before.triggerText.includes('Maps')")
g=g.replace("ZOUKASPLAY_R12_COMPLETE_MOBILE_MAPS_GLOBAL_QA_20260822","ZOUKASPLAY_R13_FINAL_MOBILE_MAPS_GLOBAL_QA_20260822")
g=g.replace("R12_GLOBAL_MAPS_QA.json","R13_GLOBAL_MAPS_QA.json")
g=g.replace("r12-global-maps","r13-global-maps")
maps.write_text(g,encoding="utf-8")
PY

grep -q '<span>Maps</span>' "$SRC/src/components/MobileFABs.astro"
! grep -q '<span>Locație</span>' "$SRC/src/components/MobileFABs.astro"
grep -q 'Aici ne găsești' "$SRC/src/components/MobileFABs.astro"
grep -q 'google.com/maps/dir' "$SRC/src/components/MobileFABs.astro"
grep -q 'waze.com/ul' "$SRC/src/components/MobileFABs.astro"
grep -q "triggerText.includes('Maps')" "$SRC/scripts/r13-global-maps-qa.mjs"
grep -q 'bilete.mpass.ro/bilete/zoukasplay' "$SRC/src/layouts/BaseLayout.astro"
grep -q 'bilete.mpass.ro/bilete/zoukasplay' "$SRC/src/pages/index.astro"
! grep -q '90 lei/persoană' "$SRC/src/components/BudgetCalculator.astro"

CURRENT_STAGE="SERVER_BUILD"
write_status "RUNNING" "Building R13 on Hetzner"
cd "$SRC"
export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=4096}"
export ASTRO_TELEMETRY_DISABLED=1
export XDG_CONFIG_HOME="$WORK/xdg-config"
mkdir -p "$XDG_CONFIG_HOME"
npm run build > "$EVIDENCE/build.log" 2>&1
[[ -f "$SRC/dist/server/entry.mjs" ]]
[[ -d "$SRC/dist/client" ]]
echo "SERVER_BUILD=PASS"

CURRENT_STAGE="SERVER_RUNTIME"
PORT="$(python3 - <<'PY'
import socket
s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()
PY
)"
HOST=127.0.0.1 PORT="$PORT" node "$SRC/dist/server/entry.mjs" > "$EVIDENCE/runtime.log" 2>&1 &
RUNTIME_PID="$!"
READY=0
for _ in $(seq 1 60); do
  if curl -fsS --max-time 5 "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then READY=1; break; fi
  sleep 1
done
[[ "$READY" == "1" ]]
for route in / /pachete/ /recenzii/ /petreceri/ /galerie/ /meniu/ /experienta/ /petreceri-copii-sector-3/; do
  [[ "$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT$route")" == "200" ]]
done
echo "SERVER_RUNTIME=PASS PORT=$PORT"

CURRENT_STAGE="SERVER_FULL_MATRIX_QA"
write_status "RUNNING" "Running 64 isolated server viewport-route checks"
mkdir -p "$EVIDENCE/full-matrix" "$EVIDENCE/maps-matrix"
ORIGIN="http://127.0.0.1:$PORT" EVIDENCE="$EVIDENCE/full-matrix" \
  node "$SRC/scripts/r13-full-matrix-qa.mjs" > "$EVIDENCE/full-matrix.stdout.log" 2>&1
python3 - "$EVIDENCE/full-matrix" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1]); found=[]
for p in root.glob("*.json"):
    try:d=json.loads(p.read_text(encoding="utf-8"))
    except Exception:continue
    if isinstance(d,dict) and "viewports" in d and "pass" in d: found.append((p,d))
assert len(found)==1, [(str(p),list(d)) for p,d in found]
p,d=found[0]
assert d.get("pass") is True, d
rows=d.get("viewports") or []
assert len(rows)==64, len(rows)
assert all(x.get("pass") is True for x in rows)
print(p)
PY
FULL_REPORT="$(python3 - "$EVIDENCE/full-matrix" <<'PY'
import json, pathlib, sys
for p in pathlib.Path(sys.argv[1]).glob("*.json"):
    try:d=json.loads(p.read_text(encoding="utf-8"))
    except Exception:continue
    if isinstance(d,dict) and "viewports" in d: print(p); break
PY
)"
echo "SERVER_FULL_MATRIX_QA=PASS_64_OF_64 REPORT=$FULL_REPORT"

CURRENT_STAGE="SERVER_MAPS_QA"
write_status "RUNNING" "Running 48 isolated server Maps checks"
MAPS_PROFILE="/dev/shm/zoukas-r13-prebuild-maps-$STAMP-$$"
rm -rf "$MAPS_PROFILE"
ORIGIN="http://127.0.0.1:$PORT" EVIDENCE="$EVIDENCE/maps-matrix" MAPS_PROFILE="$MAPS_PROFILE" \
  node "$SRC/scripts/r13-global-maps-qa.mjs" > "$EVIDENCE/maps-matrix.stdout.log" 2>&1
rm -rf "$MAPS_PROFILE"
python3 - "$EVIDENCE/maps-matrix/R13_GLOBAL_MAPS_QA.json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d.get("pass") is True, d
rows=d.get("checks") or []
assert len(rows)==48, len(rows)
assert all(x.get("pass") is True for x in rows)
assert all("Maps" in ((x.get("before") or {}).get("triggerText") or "") for x in rows)
print("SERVER_MAPS_QA=PASS_48_OF_48")
PY
cleanup

CURRENT_STAGE="PACKAGE_ASSEMBLY"
write_status "RUNNING" "Assembling one sealed R13 ZIP"
mkdir -p "$PACKAGE_ROOT/payload/src/components" \
         "$PACKAGE_ROOT/payload/src/layouts" \
         "$PACKAGE_ROOT/payload/src/pages/pachete" \
         "$PACKAGE_ROOT/payload/src/styles" \
         "$PACKAGE_ROOT/payload/scripts" \
         "$PACKAGE_ROOT/server_prebuild"

for rel in \
  src/components/BudgetCalculator.astro \
  src/components/MobileFABs.astro \
  src/components/VerifiedReviews.astro \
  src/layouts/BaseLayout.astro \
  src/pages/index.astro \
  src/pages/pachete/index.astro \
  src/styles/global.css; do
  mkdir -p "$(dirname "$PACKAGE_ROOT/payload/$rel")"
  cp -a "$SRC/$rel" "$PACKAGE_ROOT/payload/$rel"
done
cp -a "$SRC/scripts/r13-full-matrix-qa.mjs" "$PACKAGE_ROOT/payload/scripts/"
cp -a "$SRC/scripts/r13-global-maps-qa.mjs" "$PACKAGE_ROOT/payload/scripts/"
cp -a "$FULL_REPORT" "$PACKAGE_ROOT/server_prebuild/R13_FULL_MATRIX_QA.json"
cp -a "$EVIDENCE/maps-matrix/R13_GLOBAL_MAPS_QA.json" "$PACKAGE_ROOT/server_prebuild/"
cp -a "$EVIDENCE/build.log" "$PACKAGE_ROOT/server_prebuild/SERVER_BUILD.log"

printf '%s' 'IyEvdXNyL2Jpbi9lbnYgYmFzaApzZXQgLUVldW8gcGlwZWZhaWwKClBBQ0tBR0VfSUQ9IlpPVUtBU1NQTEFZX1IxM19GSU5BTF9NT0JJTEVfTUFQU19TRVJWRVJfVkFMSURBVEVEXzIwMjYwODIyIgpQQUNLQUdFX0RJUj0iJChjZCAtLSAiJChkaXJuYW1lIC0tICIke0JBU0hfU09VUkNFWzBdfSIpIiAmJiBwd2QgLVApIgpQQVlMT0FEPSIkUEFDS0FHRV9ESVIvcGF5bG9hZCIKU1RBR0lOR19CQVNFP ...' | base64 -d > "$PACKAGE_ROOT/DEPLOY_ZOUKASPLAY_R13_FINAL_MOBILE_MAPS.sh"
printf '%s' 'IyEvdXNyL2Jpbi9lbnYgYmFzaApzZXQgLUVldW8gcGlwZWZhaWwKUEFDS0FHRV9JRD0iWk9VS0FTU1BMQVlfUjEzX0ZJTkFMX01PQklMRV9NQVNQU19TRVJWRVJfVkFMSURBVEVEXzIwMjYwODIyIgpST09UPSIkKGNkIC0tICIkKGRpcm5hbWUgLS0gIiR7QkFTSF9TT1VSQ0VbMF19IikiICYmIHB3ZCAtUCkiCmNkICIkUk9PVCIKc2hhMjU2c3VtIC1jIE1BTklGRVNULnNoYTI1NgpiYXNoIC1uIERFUExPWV9aT1VLQVNQTEFZX1IxM19GSU5BTF9NT0JJTEVfTUFQUy5zaApub2RlIC0tY2hlY2sgcGF5bG9hZC9zY3JpcHRzL3IxMy1mdWxsLW1hdHJpeC1xYS5tanMKbm9kZSAtLWNoZWNrIHBheWxvYWQvc2NyaXB0cy9yMTMtZ2xvYmFsLW1hcHMtcWEubWpzCmdyZXAgLXEgJzxzcGFuPk1hcHM8L3NwYW4+JyBwYXlsb2FkL3NyYy9jb21wb25lbnRzL01vYmlsZUZBQnMuYXN0cm8KISBncmVwIC1xICc8c3Bhbj5Mb2NhxJtpZTwvc3Bhbj4nIHBheWxvYWQvc3JjL2NvbXBvbmVudHMvTW9iaWxlRkFCcy5hc3RybwpncmVwIC1xICdBaWNpIG5lIGfEg3NlyJl0aScgcGF5bG9hZC9zcmMvY29tcG9uZW50cy9Nb2JpbGVGQUJzLmFzdHJvCmdyZXAgLXEgJ2dvb2dsZS5jb20vbWFwcy9kaXInIHBheWxvYWQvc3JjL2NvbXBvbmVudHMvTW9iaWxlRkFCcy5hc3RybwpncmVwIC1xICd3YXplLmNvbS91bCcgcGF5bG9hZC9zcmMvY29tcG9uZW50cy9Nb2JpbGVGQUJzLmFzdHJvCmdyZXAgLXEgJ2JpbGV0ZS5tcGFzcy5yby9iaWxldGUvem91a2FzcGxheScgcGF5bG9hZC9zcmMvbGF5b3V0cy9CYXNlTGF5b3V0LmFzdHJvCmdyZXAgLXEgJ2JpbGV0ZS5tcGFzcy5yby9iaWxldGUvem91a2FzcGxheScgcGF5bG9hZC9zcmMvcGFnZXMvaW5kZXguYXN0cm8KISBncmVwIC1xICc5MCBsZWkvcGVyc29hbsSDJyBwYXlsb2FkL3NyYy9jb21wb25lbnRzL0J1ZGdldENhbGN1bGF0b3IuYXN0cm8KZ3JlcCAtcSAidHJpZ2dlclRleHQuaW5jbHVkZXMoJ01hcHMnKSIgcGF5bG9hZC9zY3JpcHRzL3IxMy1nbG9iYWwtbWFwcy1xYS5tanMKZWNobyAiUEFDS0FHRV9JRD0kUEFDS0FHRV9JRCIKZWNobyAiUEFDS0FHRV9TRUxGX1RFU1Q9UEFTUyIKZWNobyAiUEFDS0FHRV9WRVJJRlk9UEFTUyIK' | base64 -d > "$PACKAGE_ROOT/VERIFY_PACKAGE.sh"
printf '%s' 'Wk9VS0FTU1BMQVkgUjEzIOKAlCBTVEFSVCBIRVJFCgoxLiBUaGlzIHBhY2thZ2Ugd2FzIGFzc2VtYmxlZCBmcm9tIHRoZSBjYW5vbmljYWwgSGV0em5lciBzZXJ2ZXIgc291cmNlLgo ...' | base64 -d > "$PACKAGE_ROOT/START_HERE.txt"
printf '%s' 'UFJPSkVDVD1aT1VLQVNQTEFZClJPTEU9VFJBTlNQT1JUX09OTFkKUk9MRT1TRU...' | base64 -d > "$PACKAGE_ROOT/ANTIGRAVITY_PROMPT.txt"
chmod 755 "$PACKAGE_ROOT/DEPLOY_ZOUKASPLAY_R13_FINAL_MOBILE_MAPS.sh" "$PACKAGE_ROOT/VERIFY_PACKAGE.sh"

python3 - "$PACKAGE_ROOT/server_prebuild/PREBUILD_RECEIPT.json" "$WORK" "$SRC" "$EVIDENCE" "$FULL_REPORT" "$EVIDENCE/maps-matrix/R13_GLOBAL_MAPS_QA.json" <<'PY'
import hashlib, json, os, pathlib, sys
out,work,src,evidence,full_path,maps_path=sys.argv[1:]
full=json.load(open(full_path,encoding="utf-8"))
maps=json.load(open(maps_path,encoding="utf-8"))
payload={
  "package_id":"ZOUKASPLAY_R13_FINAL_MOBILE_MAPS_SERVER_VALIDATED_20260822",
  "status":"PASS",
  "canonical_source":"HETZNER_SERVER_ONLY",
  "project_built_locally":False,
  "production_changed_during_prebuild":False,
  "server_work":work,
  "server_candidate":src,
  "server_evidence":evidence,
  "server_build":"PASS",
  "isolated_full_matrix":{"pass":full.get("pass"),"checks":len(full.get("viewports") or [])},
  "isolated_maps_matrix":{"pass":maps.get("pass"),"checks":len(maps.get("checks") or [])},
  "mobile_bar":["Sună","WhatsApp","Maps"],
  "location_panel":"Aici ne găsești",
  "address":"Splaiul Unirii 213, Sector 3, București",
  "google_maps":True,
  "waze":True,
}
open(out,"w",encoding="utf-8").write(json.dumps(payload,ensure_ascii=False,indent=2)+"\n")
PY

cd "$PACKAGE_ROOT"
find . -type f ! -name MANIFEST.sha256 -print0 | sort -z | xargs -0 sha256sum > MANIFEST.sha256
bash VERIFY_PACKAGE.sh > server_prebuild/PACKAGE_VERIFY.log 2>&1
grep -q 'PACKAGE_VERIFY=PASS' server_prebuild/PACKAGE_VERIFY.log

CURRENT_STAGE="PACKAGE_ZIP"
ZIP_TMP="$WORK/package/${PACKAGE_ID}.zip"
rm -f "$ZIP_TMP"
cd "$WORK/package"
zip -qr "$ZIP_TMP" "$PACKAGE_ID"
unzip -tq "$ZIP_TMP"
ZIP_SHA="$(sha256sum "$ZIP_TMP" | awk '{print $1}')"
ZIP_SIZE="$(stat -c %s "$ZIP_TMP")"
cp -a "$ZIP_TMP" "$DELIVERY_DIR/${PACKAGE_ID}.zip"
printf '%s  %s\n' "$ZIP_SHA" "${PACKAGE_ID}.zip" > "$DELIVERY_DIR/${PACKAGE_ID}.zip.sha256"
chmod 644 "$DELIVERY_DIR/${PACKAGE_ID}.zip" "$DELIVERY_DIR/${PACKAGE_ID}.zip.sha256"

CURRENT_STAGE="FINALIZE"
STATE_VALUE="PASS" SHA_VALUE="$ZIP_SHA" SIZE_VALUE="$ZIP_SIZE" \
WORK_VALUE="$WORK" SRC_VALUE="$SRC" EVIDENCE_VALUE="$EVIDENCE" \
ZIP_VALUE="$DELIVERY_DIR/${PACKAGE_ID}.zip" \
python3 - "$STATUS_FILE" <<'PY'
import json, os, sys
payload={
  "job_id":"zoukas_r13_build_20260822",
  "package_id":"ZOUKASPLAY_R13_FINAL_MOBILE_MAPS_SERVER_VALIDATED_20260822",
  "state":"PASS",
  "stage":"FINALIZE",
  "canonical_source":"HETZNER_SERVER_ONLY",
  "project_built_locally":False,
  "production_changed_during_prebuild":False,
  "server_build":"PASS",
  "isolated_full_matrix":"PASS_64_OF_64",
  "isolated_maps_matrix":"PASS_48_OF_48",
  "maps_button":"PASS",
  "google_maps_link":"PASS",
  "waze_link":"PASS",
  "work":os.environ["WORK_VALUE"],
  "candidate":os.environ["SRC_VALUE"],
  "evidence":os.environ["EVIDENCE_VALUE"],
  "zip_path":os.environ["ZIP_VALUE"],
  "zip_size_bytes":int(os.environ["SIZE_VALUE"]),
  "zip_sha256":os.environ["SHA_VALUE"],
}
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(payload,ensure_ascii=False,indent=2)+"\n")
PY

trap - ERR
trap - EXIT
cleanup
echo "STATUS_FINAL=PASS"
echo "PACKAGE_ID=$PACKAGE_ID"
echo "SERVER_BUILD=PASS"
echo "ISOLATED_FULL_MATRIX_QA=PASS_64_OF_64"
echo "ISOLATED_MAPS_QA=PASS_48_OF_48"
echo "MAPS_BUTTON=PASS"
echo "GOOGLE_MAPS_LINK=PASS"
echo "WAZE_LINK=PASS"
echo "PRODUCTION_CHANGED_DURING_PREBUILD=FALSE"
echo "ZIP=$DELIVERY_DIR/${PACKAGE_ID}.zip"
echo "ZIP_SIZE_BYTES=$ZIP_SIZE"
echo "ZIP_SHA256=$ZIP_SHA"
