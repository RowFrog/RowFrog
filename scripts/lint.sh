#!/bin/bash
# Lint report for Swift (swift-format, rules in .swift-format) and JavaScript
# (ESLint, rules in eslint.config.mjs). It only reports for now and always
# exits 0 (good-practice doc, step 4). Next: one pure formatting change when the
# merge queue is empty, then new findings fail.
#
#   scripts/lint.sh          both, a count per rule, then the findings
#   scripts/lint.sh js       only JavaScript
#   scripts/lint.sh swift    only Swift (needs Xcode's xcrun swift-format)
cd "$(dirname "$0")/.." || exit 0
what=${1:-all}

if [[ $what == all || $what == js ]]; then
  echo "== ESLint (web/, cloudflare/)"
  if [[ -x node_modules/.bin/eslint ]]; then
    node_modules/.bin/eslint . > /tmp/rowfrog-eslint.txt
    grep -E "^ +[0-9]+:[0-9]+ +(warning|error) " /tmp/rowfrog-eslint.txt | grep -oE "[a-z-]+$" | sort | uniq -c | sort -rn
    echo "$(grep -cE "^ +[0-9]+:[0-9]+ +(warning|error) " /tmp/rowfrog-eslint.txt) findings; all in /tmp/rowfrog-eslint.txt"
  else
    echo "no node_modules/.bin/eslint; run npm ci first"
  fi
fi

if [[ $what == all || $what == swift ]]; then
  echo "== swift-format (ios/)"
  if xcrun --find swift-format >/dev/null 2>&1; then
    xcrun swift-format lint --recursive --parallel ios/RowFrog ios/RowFrogWidget ios/RowFrogTests ios/RowFrogUITests 2>&1 \
      | tee /tmp/rowfrog-swift-format.txt | grep -oE "\[[A-Za-z]+\]" | sort | uniq -c | sort -rn
    echo "$(grep -c warning /tmp/rowfrog-swift-format.txt) findings; all in /tmp/rowfrog-swift-format.txt"
  else
    echo "no swift-format (it comes with Xcode 16 and later)"
  fi
fi
exit 0
