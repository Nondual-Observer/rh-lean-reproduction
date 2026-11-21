#!/usr/bin/env bash
# 6_report.sh: gather every result into out/REPORT.md, ready to post on the Lean Zulip.
cd "$(dirname "$0")"; . ./common.sh

fence='```'
{
  echo "# Independent check of the claimed Lean proof of RH / GRH"
  echo "date_utc: $(date -u +%Y-%m-%dT%H:%MZ)"
  # Copy all existing reports with a single cat: section headers come from
  # here-documents on fds 3-9 (no extra processes). Each header also carries
  # the closing fence of the previous section. If any report could make cat
  # fail (unreadable, or the same file as REPORT.md), use the per-file loop
  # so a failure still aborts at exactly the same point.
  hdr=() args=()
  n=3 nargs=0 single=1 sep=''
  for f in hardware hash toolchain scan build_result check_summary replay_result; do
    hdr[n]=$sep
    if [ -f "$OUT/$f.txt" ]; then
      if [ ! -r "$OUT/$f.txt" ] || [ "$OUT/$f.txt" -ef "$OUT/REPORT.md" ]; then single=0; fi
      args[nargs]=/dev/fd/$n
      args[nargs+1]=$OUT/$f.txt
      nargs=$((nargs + 2))
      sep="$fence
"
    fi
    n=$((n + 1))
  done
  if [ "$single" = 1 ]; then
    if [ "$nargs" -gt 0 ]; then
      cat "${args[@]}" 3<<EOF 4<<EOF 5<<EOF 6<<EOF 7<<EOF 8<<EOF 9<<EOF
${hdr[3]}
## hardware
$fence
EOF
${hdr[4]}
## hash
$fence
EOF
${hdr[5]}
## toolchain
$fence
EOF
${hdr[6]}
## scan
$fence
EOF
${hdr[7]}
## build_result
$fence
EOF
${hdr[8]}
## check_summary
$fence
EOF
${hdr[9]}
## replay_result
$fence
EOF
      echo '```'
    fi
  else
    for f in hardware hash toolchain scan build_result check_summary replay_result; do
      if [ -f "$OUT/$f.txt" ]; then echo; echo "## $f"; echo '```'; cat "$OUT/$f.txt"; echo '```'; fi
    done
  fi
} > "$OUT/REPORT.md"
# Echo the report back without forking cat: read NUL-delimited chunks
# byte-wise (LC_ALL=C) and re-emit each with its NUL; the final read leaves
# the unterminated tail in c. Fall back to cat if the file is unreadable so
# the failure (message + status) stays the same.
if [ -r "$OUT/REPORT.md" ]; then
  c=''
  while LC_ALL=C IFS= read -r -d '' c; do printf '%s\0' "$c"; done < "$OUT/REPORT.md"
  printf '%s' "$c"
else
  cat "$OUT/REPORT.md"
fi
echo
echo "Saved: $OUT/REPORT.md"
