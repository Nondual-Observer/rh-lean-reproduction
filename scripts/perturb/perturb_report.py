#!/usr/bin/env python3
"""perturb_report.py: summarise a Lake build log from the perturbation experiment.

  python3 -I perturb_report.py <build.log> <src_dir>

For every file with a Lean error it prints the first error, the declaration that
contains it (found by scanning the source upward), and whether the declaration's
text mentions the patched quantities. Modules Lake skipped because an import
failed are counted, not listed: they are not first-layer failures.
"""
import collections, os, re, sys

ERR = re.compile(r"error: (?:\./)?(\S+?\.lean):(\d+):(\d+): (.*)")
FAILED_JOB = re.compile(r"✖ \[\d+/\d+\] Building (\S+)")
DECL = re.compile(r"^\s*(?:@\[[^\]]*\]\s*)?(?:private\s+|protected\s+|noncomputable\s+)*"
                  r"(theorem|lemma|def|abbrev|instance|structure|example)\s*([^\s:({\[]*)")
HINTS = ("RankVal", "sqrt", "9 / 2", "R.m", "R.k", "delta1", "m_up", "k_up")


def decl_at(path, line):
    try:
        lines = open(path, encoding="utf-8", errors="ignore").read().splitlines()
    except OSError:
        return "?", ""
    for i in range(min(line, len(lines)) - 1, -1, -1):
        m = DECL.match(lines[i])
        if m:
            j = i + 1
            while j < len(lines) and not DECL.match(lines[j]):
                j += 1
            return f"{m.group(1)} {m.group(2) or '(anonymous)'}", "\n".join(lines[i:j])
    return "?", ""


def main():
    log, src = sys.argv[1], sys.argv[2]
    first = collections.OrderedDict()
    failed_jobs = set()
    for raw in open(log, encoding="utf-8", errors="ignore"):
        m = ERR.search(raw)
        if m:
            f = m.group(1)
            if f not in first:
                first[f] = (int(m.group(2)), m.group(4).strip())
        m = FAILED_JOB.search(raw)
        if m:
            failed_jobs.add(m.group(1))
    print(f"files with Lean errors (first-layer failures): {len(first)}")
    print(f"failed Lake jobs in total (including those blocked by an import): {len(failed_jobs)}")
    print()
    for f, (ln, msg) in first.items():
        rel = f.split("src/", 1)[-1] if "src/" in f else f
        path = os.path.join(src, rel)
        name, body = decl_at(path, ln)
        hits = [h for h in HINTS if h in body]
        print(f"- {rel}:{ln}")
        print(f"    in:    {name}")
        print(f"    error: {msg[:200]}")
        print(f"    mentions: {', '.join(hits) if hits else '(none of the patched names)'}")
    print()
    print("Classify each entry by hand in mechanism/PERTURB.md:")
    print("  WINDOW     a size window of the balance (winA, winM, ...), expected")
    print("  LITERAL    a hardcoded exponent or constant that still holds after rescaling; patch and rerun")
    print("  REAL       a claim that is false at the new exponent; this is the finding")


if __name__ == "__main__":
    main()
