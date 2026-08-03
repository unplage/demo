#!/usr/bin/env bash
set -euo pipefail

UPSTREAM="hehonghui/awesome-english-ebooks"
BRANCH="master"
API="https://api.github.com/repos/${UPSTREAM}/contents"
RAW="https://raw.githubusercontent.com/${UPSTREAM}/${BRANCH}"
BOOKS_DIR="books"

echo "=== Sync started at $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

# Step 1: Download latest issues
for dir in 01_economist 02_new_yorker 04_atlantic 05_wired; do
  echo ""
  echo "--- ${dir} ---"

  # List magazine directory, pick latest issue (dirs only, sort desc, first)
  latest=$(curl -sfS "${API}/${dir}?ref=${BRANCH}" | python3 -c "
import sys, json
items = json.load(sys.stdin)
dirs = [i['name'] for i in items if i['type'] == 'dir']
dirs.sort(reverse=True)
print(dirs[0] if dirs else '')
" 2>/dev/null || true)

  if [ -z "$latest" ]; then
    echo "  No issue found, skipping"
    continue
  fi
  echo "  Latest: ${latest}"

  # Check if already synced
  if [ -d "${BOOKS_DIR}/${dir}/${latest}" ] && [ -n "$(ls -A "${BOOKS_DIR}/${dir}/${latest}" 2>/dev/null)" ]; then
    echo "  Already synced, skipping"
    continue
  fi

  # Create target directory
  mkdir -p "${BOOKS_DIR}/${dir}/${latest}"

  # List issue directory and download matching files (epub, pdf, mobi)
  curl -sfS "${API}/${dir}/${latest}?ref=${BRANCH}" | python3 -c "
import sys, json, re
pattern = re.compile(r'\.(epub|pdf|mobi)$', re.IGNORECASE)
items = json.load(sys.stdin)
for item in items:
    if item['type'] == 'file' and pattern.search(item['name']):
        print(item['name'] + '|' + str(item.get('size', 0)))
" 2>/dev/null | while IFS='|' read -r fname fsize; do
    if [ -f "${BOOKS_DIR}/${dir}/${latest}/${fname}" ]; then
      echo "    [cached] ${fname}"
      continue
    fi
    if [ -n "$fsize" ] && [ "$fsize" -gt 0 ] 2>/dev/null; then
      size_mb=$(echo "scale=1;${fsize}/1048576" | bc)
      echo "    Downloading ${fname} (${size_mb}MB)..."
    else
      echo "    Downloading ${fname}..."
    fi
    curl -sL -o "${BOOKS_DIR}/${dir}/${latest}/${fname}" "${RAW}/${dir}/${latest}/${fname}"
  done

  # Remove old issue directories for this magazine
  if [ -d "${BOOKS_DIR}/${dir}" ]; then
    for old in "${BOOKS_DIR}/${dir}"/*/; do
      old_name=$(basename "$old")
      if [ "$old_name" != "$latest" ] && [ "$old_name" != ".git" ]; then
        echo "  Removing old: ${old_name}"
        rm -rf "$old"
      fi
    done
  fi

  echo "  Done"
done

# Step 2: Generate index.json
echo ""
echo "=== Generating index.json ==="

python3 - "$BOOKS_DIR" <<'PYEOF'
import os, sys, json, time

books_dir = sys.argv[1] if len(sys.argv) > 1 else "books"
MAGAZINE_NAMES = {
    "01_economist": "经济学人 The Economist",
    "02_new_yorker": "纽约客 The New Yorker",
    "04_atlantic": "大西洋月刊 The Atlantic",
    "05_wired": "连线 Wired",
}
FORMAT_ICONS = {"epub": "📖", "pdf": "📄", "mobi": "📱"}
FORMAT_LABELS = {"epub": "EPUB", "pdf": "PDF", "mobi": "MOBI"}

result = {
    "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "magazines": [],
}

if not os.path.isdir(books_dir):
    os.makedirs(books_dir, exist_ok=True)

for mag_dir in sorted(os.listdir(books_dir)):
    mag_path = os.path.join(books_dir, mag_dir)
    if not os.path.isdir(mag_path) or mag_dir.startswith("."):
        continue
    issues = sorted(
        [d for d in os.listdir(mag_path) if os.path.isdir(os.path.join(mag_path, d))],
        reverse=True,
    )
    if not issues:
        continue
    latest_issue = issues[0]
    issue_path = os.path.join(mag_path, latest_issue)
    files = []
    for fname in sorted(os.listdir(issue_path)):
        fpath = os.path.join(issue_path, fname)
        if not os.path.isfile(fpath):
            continue
        ext = fname.rsplit(".", 1)[-1].lower() if "." in fname else ""
        if ext not in ("epub", "pdf", "mobi"):
            continue
        fsize = os.path.getsize(fpath)
        files.append({
            "name": fname,
            "format": ext,
            "icon": FORMAT_ICONS.get(ext, "📄"),
            "label": FORMAT_LABELS.get(ext, ext.upper()),
            "size": fsize,
            "size_str": f"{fsize / 1048576:.1f} MB",
            "url": f"{books_dir}/{mag_dir}/{latest_issue}/{fname}",
        })
    result["magazines"].append({
        "id": mag_dir,
        "name": MAGAZINE_NAMES.get(mag_dir, mag_dir),
        "latest_issue": latest_issue,
        "file_count": len(files),
        "files": files,
    })

with open(os.path.join(books_dir, "index.json"), "w", encoding="utf-8") as f:
    json.dump(result, f, ensure_ascii=False, indent=2)

print(f"  Generated index.json with {len(result['magazines'])} magazines")
PYEOF

echo ""
echo "=== Sync completed at $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
