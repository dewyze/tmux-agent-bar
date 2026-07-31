#!/usr/bin/env bash
# Runs every tests/**/*_test.sh. Passing tests produce zero stdout.
set -u

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
export ROOT_DIR

failures=0
tests=0

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  files=()
  while IFS= read -r file; do
    files+=("$file")
  done < <(find "$ROOT_DIR/tests" -name '*_test.sh' | sort)
fi

for file in "${files[@]}"; do
  tests=$((tests + 1))
  if ! output="$(bash "$file" 2>&1)"; then
    failures=$((failures + 1))
    printf 'FAIL %s\n%s\n' "$file" "$output" >&2
  elif [ -n "$output" ]; then
    failures=$((failures + 1))
    printf 'FAIL (stdout not empty) %s\n%s\n' "$file" "$output" >&2
  fi
done

if [ "$failures" -gt 0 ]; then
  printf '%d/%d test files failed\n' "$failures" "$tests" >&2
  exit 1
fi
