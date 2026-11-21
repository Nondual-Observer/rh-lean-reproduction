#!/usr/bin/env bash
# 1_preflight.sh: hardware check, download + hash check, red-flag scan.
# Safe: nothing from the archive is executed. About 5 minutes.
cd "$(dirname "$0")"; . ./common.sh

# ---- hardware ------------------------------------------------------------------
log "Hardware"
(
  hardware_host=$(uname -srm) || :
  case $hardware_host in
    Darwin\ *) is_mac(){ return 0; } ;;
    Linux\ *) is_mac(){ return 1; } ;;
  esac
  # Start the core count while the memory probe runs.
  exec 3< <(cores)
  hardware_ram=$(ram_gb) || :
  IFS= read -r hardware_cores <&3 || :
  exec 3<&-
  # free_gb writes a number without a trailing newline.
  IFS= read -r hardware_disk || :
  {
    echo "host: $hardware_host"
    echo "cores: $hardware_cores"
    echo "ram_gb: $hardware_ram"
    echo "disk_free_gb: $hardware_disk"
    echo "jobs_setting: $JOBS"
  } | tee "$OUT/hardware.txt"
  [ "$hardware_disk" -ge 60 ] || echo "WARNING: under 60 GB free. The build output is large; free up space first."
  if [ "$hardware_ram" -lt 64 ]; then
    echo "NOTE: $hardware_ram GB RAM. The full build will work at reduced parallelism ($JOBS at once) but will be slow."
  fi
) < <(free_gb)

# ---- download + verify ---------------------------------------------------------
log "Downloading $NPARTS parts from the author's site"
cd "$DL"
for i in $(seq -w 1 "$NPARTS"); do
  if [ -s "lean.tar.gz.part$i" ]; then echo "part$i already downloaded"; continue; fi
  curl -fL --retry 5 --retry-delay 5 -o "lean.tar.gz.part$i.tmp" "$BASE_URL$i"
  mv "lean.tar.gz.part$i.tmp" "lean.tar.gz.part$i"
done
cat $(for i in $(seq -w 1 "$NPARTS"); do echo "lean.tar.gz.part$i"; done) > lean.tar.gz

got_sha=$(sha lean.tar.gz); got_bytes=$(fsize lean.tar.gz)
{ echo "sha256: $got_sha"; echo "bytes: $got_bytes"; } | tee "$OUT/hash.txt"
[ "$got_sha" = "$EXPECTED_SHA" ]     || die "hash mismatch (expected $EXPECTED_SHA). Stop here."
[ "$got_bytes" = "$EXPECTED_BYTES" ] || die "size mismatch (expected $EXPECTED_BYTES bytes). Stop here."
echo "PASS: archive matches the published hash" | tee -a "$OUT/hash.txt"

log "Extracting"
rm -rf "$PROJ"
tar -xzf lean.tar.gz -C "$WORK"
[ -f "$PROJ/lean-toolchain" ] || die "no lean-toolchain after extracting; inspect with: tar -tzf $DL/lean.tar.gz | head"
{
  echo "toolchain: $(cat "$PROJ/lean-toolchain")"
  # Keep the line count available even if find reports a traversal error.
  lean_files=$(find "$PROJ" -name '*.lean' -not -path '*/.lake/*' | wc -l) || :
  echo "lean_files: ${lean_files// /}"
} | tee "$OUT/toolchain.txt"

# ---- red-flag scan (text only) -------------------------------------------------
log "Red-flag scan"
cd "$PROJ"
if [ -f lakefile.lean ]; then
  echo "NOTE: lakefile.lean exists. It is Lean code that runs at build time; read it before 2_setup.sh."
fi
if [ -f lakefile.toml ]; then
  echo "--- lakefile.toml (declarative, runs nothing) ---"
  tee "$OUT/lakefile.txt" < lakefile.toml
fi

rm -f "$OUT"/scan_*.txt; : > "$OUT/scan.txt"
scan(){  # label severity regex
  local n
  n=$(
    grep -rnE --include='*.lean' "$3" . 2>/dev/null | tee "$OUT/scan_$1.txt" | wc -l || {
      # Ignore grep's exit status and preserve failures from tee and wc.
      status=("${PIPESTATUS[@]}")
      if [ "${status[2]}" -ne 0 ]; then
        exit "${status[2]}"
      fi
      exit "${status[1]}"
    }
  )
  printf '%-16s %-9s %s\n' "$1" "$2" "${n// /}" | tee -a "$OUT/scan.txt"
}
printf '%-16s %-9s %s\n' PATTERN SEVERITY MATCHES | tee -a "$OUT/scan.txt"
scan sorry          CRITICAL 'sorry'
scan admit          CRITICAL '(^|[^A-Za-z_.])admit([^A-Za-z_]|$)'
scan axiom_decl     CRITICAL '^[[:space:]]*((private|protected|noncomputable)[[:space:]]+)*axiom[[:space:]]'
scan skipKernelTC   CRITICAL 'skipKernelTC'
scan native_decide  CRITICAL 'native_decide'
scan reduceBool     CRITICAL 'ofReduceBool|reduceBool'
scan implemented_by INFO     'implemented_by'
scan extern         INFO     '@\[extern'
scan buildtime_code INFO     '#eval|run_cmd|run_elab|run_meta|^[[:space:]]*initialize'
scan unsafe         INFO     'unsafe'

echo
if awk '$2=="CRITICAL" && $3>0 {f=1} END {exit !f}' "$OUT/scan.txt"; then
  echo "VERDICT: critical matches found. Open $OUT/scan_<pattern>.txt."
  echo "  Matches inside comments are harmless. Real uses mean the proof leans on something unproved."
else
  echo "VERDICT: no critical patterns in the source text."
fi
echo "buildtime_code matches are code that runs on your Mac during the build. Skim $OUT/scan_buildtime_code.txt before step 2."
echo
echo "Next: bash 2_setup.sh"
