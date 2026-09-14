#!/usr/bin/env bash
# repo_audit.sh — read-only audit of a git repository before a presentation rework.
# Mutates nothing: no checkout, no gc, no writes inside the repo.
# Usage:  bash repo_audit.sh [/path/to/repo] > audit.md

set -uo pipefail

REPO="${1:-.}"
cd "$REPO" 2>/dev/null || { echo "cannot cd to $REPO" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repository: $REPO" >&2; exit 1; }
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

h()  { printf '\n## %s\n\n' "$1"; }
h2() { printf '\n### %s\n\n' "$1"; }

printf '# Repo audit — %s\n\n' "$(basename "$ROOT")"
printf 'generated %s\n' "$(date -u '+%Y-%m-%d %H:%M UTC')"

# ---------------------------------------------------------------- 1. identity
h "1. Identity"
printf '| field | value |\n|---|---|\n'
printf '| root | `%s` |\n' "$ROOT"
printf '| branch | %s |\n' "$(git rev-parse --abbrev-ref HEAD)"
printf '| commits (HEAD) | %s |\n' "$(git rev-list --count HEAD)"
printf '| commits (all refs) | %s |\n' "$(git rev-list --all --count)"
printf '| tags | %s |\n' "$(git tag | wc -l | tr -d ' ')"
REM="$(git remote -v | awk '{print $1" "$2}' | sort -u | paste -sd'; ' -)"
printf '| remotes | %s |\n' "${REM:-none}"
printf '| worktree size | %s |\n' "$(du -sh --exclude=.git . 2>/dev/null | cut -f1)"
printf '| .git size | %s |\n' "$(du -sh .git 2>/dev/null | cut -f1)"
printf '\nHistory rewriting is only safe if nobody else holds a clone and there are\n'
printf 'no forks or open PRs. That cannot be checked locally — verify on the host.\n'

# ------------------------------------------------------------ 2. object store
h "2. Object store"
printf '```\n'; git count-objects -vH; printf '```\n'

# --------------------------------------------------- 3. blob history analysis
# One pass over every object reachable from any ref; blobs only, with paths.
git rev-list --objects --all 2>/dev/null \
  | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' 2>/dev/null \
  | awk '$1=="blob" && NF>3 { size=$3; $1=""; $2=""; $3=""; sub(/^ +/,""); print size"\t"$0 }' \
  > "$TMP/blobs.tsv"

git ls-files > "$TMP/head_files.txt" 2>/dev/null

h "3. Largest blobs in history"
printf 'Repeated paths are superseded revisions. These persist after a `git rm`.\n\n'
printf '| MB | path | at HEAD |\n|---:|---|---|\n'
sort -rn "$TMP/blobs.tsv" | head -20 | while IFS=$'\t' read -r size path; do
  mb=$(awk -v s="$size" 'BEGIN{printf "%.1f", s/1048576}')
  if grep -Fxq "$path" "$TMP/head_files.txt"; then at="yes"; else at="no"; fi
  printf '| %s | `%s` | %s |\n' "$mb" "$path" "$at"
done

h2 "3b. History blob volume by extension"
printf 'Compare against the HEAD column: the gap is what only a rewrite can reclaim.\n\n'
printf '| ext | revisions | history MB | HEAD MB |\n|---|---:|---:|---:|\n'
awk -F'\t' '{
  n=split($2,p,"/"); f=p[n];
  i=match(f,/\.[^.]+$/); ext = (i>0) ? substr(f,i) : "(none)";
  cnt[ext]++; hist[ext]+=$1;
} END { for (e in cnt) printf "%s\t%d\t%d\n", e, cnt[e], hist[e] }' "$TMP/blobs.tsv" \
  | sort -t$'\t' -k3 -rn | head -12 > "$TMP/byext.tsv"
while IFS=$'\t' read -r ext cnt bytes; do
  headb=$(awk -v E="$ext" '
    { n=split($0,p,"/"); f=p[n]; i=match(f,/\.[^.]+$/); e=(i>0)?substr(f,i):"(none)";
      if (e==E) print $0 }' "$TMP/head_files.txt" \
    | tr '\n' '\0' | xargs -0 -r du -kc 2>/dev/null | tail -1 | awk '{print $1*1024}')
  headb=${headb:-0}
  printf '| %s | %s | %.1f | %.1f |\n' "$ext" "$cnt" \
    "$(awk -v b="$bytes" 'BEGIN{print b/1048576}')" \
    "$(awk -v b="$headb" 'BEGIN{print b/1048576}')"
done < "$TMP/byext.tsv"

h2 "3c. GitHub size limits"
printf 'GitHub warns above 50 MB and hard-rejects any single file above 100 MB.\n\n'
awk -F'\t' '$1>52428800 {printf "- %.1f MB  `%s`\n", $1/1048576, $2}' "$TMP/blobs.tsv" \
  | sort -u | head -20 > "$TMP/over50.txt"
if [ -s "$TMP/over50.txt" ]; then cat "$TMP/over50.txt"; else printf 'no blob above 50 MB.\n'; fi
if awk -F'\t' '$1>104857600 {found=1} END{exit !found}' "$TMP/blobs.tsv"; then
  printf '\nAt least one blob exceeds the 100 MB hard limit — pushes will be rejected.\n'
fi
printf '\n'

# ------------------------------------------------------- 4. tracked artifacts
h "4. Largest tracked files at HEAD"
printf 'Binary results tracked as source are what regenerate history bloat.\n\n'
tr '\n' '\0' < "$TMP/head_files.txt" | xargs -0 -r du -k 2>/dev/null \
  | sort -rn | awk '$1>=1024' | head -20 \
  | awk '{ s=$1; $1=""; sub(/^ +/,""); printf "| %.1f | `%s` |\n", s/1024, $0 }' > "$TMP/big_head.txt"
if [ -s "$TMP/big_head.txt" ]; then
  printf '| MB | path |\n|---:|---|\n'; cat "$TMP/big_head.txt"
else
  printf 'no tracked file at HEAD reaches 1 MB.\n'
fi

# ----------------------------------------------------------- 5. authorship
h "5. Authorship"
printf 'Commits whose email is not linked to your GitHub account do not count as\n'
printf 'contributions and block pinning. Adding the address in Settings > Emails\n'
printf 'fixes this retroactively, without rewriting history.\n\n```\n'
git shortlog -sne --all 2>/dev/null | head -20
printf '```\n'

# --------------------------------------------------------- 6. hygiene files
h "6. Hygiene"
printf '| item | status |\n|---|---|\n'
for f in README.md README.rst LICENSE LICENSE.md .gitignore requirements.txt pyproject.toml environment.yml; do
  if [ -e "$f" ]; then printf '| %s | present |\n' "$f"; fi
done
for f in README.md LICENSE .gitignore; do
  [ -e "$f" ] || printf '| %s | **missing** |\n' "$f"
done
printf '\n'
h2 "6b. Junk on disk"
for p in .DS_Store __pycache__ .ipynb_checkpoints .claude .venv venv node_modules .idea .vscode; do
  n=$(find . -name "$p" -not -path './.git/*' 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] || continue
  t=$(git ls-files | grep -c "\(^\|/\)$p\(/\|$\)" || true)
  printf -- '- `%s` — %s on disk, %s tracked%s\n' "$p" "$n" "$t" \
    "$( [ "$t" -gt 0 ] && echo ' (needs removal from the index, not just .gitignore)')"
done

# -------------------------------------------------------------- 7. secrets
h "7. Possible secrets in tracked files"
printf 'Locations only — values are never printed. Going public exposes all history,\n'
printf 'so scan history too with gitleaks or trufflehog before flipping visibility.\n\n'
PAT='AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(api[_-]?key|secret|passwd|password|token)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{12,}'
if git grep -InE "$PAT" -- . 2>/dev/null | awk -F: '{print "- `"$1"` line "$2}' | sort -u | head -20 | grep -q .; then
  git grep -InE "$PAT" -- . 2>/dev/null | awk -F: '{print "- `"$1"` line "$2}' | sort -u | head -20
else
  printf 'none matched.\n'
fi

# ------------------------------------------------- 8. dead code / dead data
h "8. Dead references"
python3 - "$ROOT" <<'PY' 2>/dev/null || printf 'python3 unavailable — section skipped.\n'
import os, re, subprocess, sys, zipfile
root = sys.argv[1]
tracked = subprocess.run(["git","ls-files"], cwd=root, capture_output=True, text=True).stdout.split("\n")
tracked = [t for t in tracked if t]
py = [t for t in tracked if t.endswith(".py")]
basenames = {os.path.basename(t) for t in tracked}

DATA = r"[\w./\-{}]+\.(?:npz|npy|csv|tsv|pt|pth|eqx|h5|hdf5|pkl|parquet|mat)"
lit = re.compile(r"['\"](" + DATA + r")['\"]")
missing = []
for f in py:
    try: src = open(os.path.join(root,f), encoding="utf-8", errors="ignore").read()
    except OSError: continue
    for m in set(lit.findall(src)):
        if "{" in m or "%" in m:      # f-string / format template, cannot resolve
            continue
        if os.path.basename(m) not in basenames and not os.path.exists(os.path.join(root, m)):
            missing.append((f, m))

print("Scripts reading files that exist nowhere in the tree — these cannot run.\n")
if missing:
    print("| script | reads |\n|---|---|")
    for f, m in sorted(set(missing))[:25]:
        print(f"| `{f}` | `{m}` |")
else:
    print("none found.")

corpus = "\n".join(
    open(os.path.join(root,f), encoding="utf-8", errors="ignore").read()
    for f in tracked if f.endswith((".py",".md",".sh",".toml",".cfg",".yaml",".yml",".txt"))
)
SKIP = {"__init__","setup","conftest","main","__main__"}
orphans = [f for f in py
           if os.path.basename(f)[:-3] not in SKIP
           and corpus.count(os.path.basename(f)[:-3]) <= 1]
print("\nModules whose name appears nowhere else. Entry-point scripts land here\nlegitimately — this is a list to judge, not a delete list.\n")
if orphans:
    for f in orphans[:25]: print(f"- `{f}`")
else:
    print("none found.")

npz = [t for t in tracked if t.endswith(".npz")]
if npz:
    npz.sort(key=lambda t: os.path.getsize(os.path.join(root,t)) if os.path.exists(os.path.join(root,t)) else 0, reverse=True)
    print("\nCompression of the largest tracked .npz (STORED means np.savez, not savez_compressed):\n")
    for t in npz[:3]:
        p = os.path.join(root,t)
        if not os.path.exists(p): continue
        try:
            with zipfile.ZipFile(p) as z:
                infos = z.infolist()
                stored = sum(1 for i in infos if i.compress_type == 0)
                raw = sum(i.file_size for i in infos)
            print(f"- `{t}` — {os.path.getsize(p)/1048576:.1f} MB on disk, "
                  f"{stored}/{len(infos)} members STORED, {raw/1048576:.1f} MB raw")
        except zipfile.BadZipFile:
            pass
PY

h "9. Suggested order of work"
cat <<'EOF'
1. Answer the open questions this report raises. Nothing is deleted yet.
2. Decide the artifact boundary: what is source, what is a result to deposit.
3. Write the README and the deposit manifest. Still nothing deleted.
4. Delete dead code and untracked junk. Commit normally.
5. History rewrite LAST, after any deadline that depends on this repo, and only
   once the deposit archives exist outside the repo and forks are ruled out.
EOF
