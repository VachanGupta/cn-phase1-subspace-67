#!/bin/bash
# Write share/evidence/mac_abhay/MANIFEST.txt: one path per line, relative to that folder.
set -u
P="/Users/abhaymalik/Desktop/CN_subspace_67"
D="$P/share/evidence/mac_abhay"
cd "$D" || exit 1
find . -type f ! -name 'MANIFEST.txt*' ! -name '.DS_Store' | sed 's|^\./||' | LC_ALL=C sort > "$P/logs/MANIFEST.txt.tmp"
mv "$P/logs/MANIFEST.txt.tmp" "$D/MANIFEST.txt"
echo "MANIFEST.txt: $(wc -l < MANIFEST.txt | tr -d ' ') files"
