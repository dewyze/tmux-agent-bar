# Shared test helpers. Source from *_test.sh files.
set -u

ROOT_DIR="${ROOT_DIR:-$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1" actual="$2" label="${3:-}"
  if [ "$expected" != "$actual" ]; then
    fail "assert_eq${label:+ ($label)}: expected [$expected] got [$actual]"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  case "$haystack" in
    *"$needle"*) ;;
    *) fail "assert_contains${label:+ ($label)}: [$needle] not found in [$haystack]" ;;
  esac
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  case "$haystack" in
    *"$needle"*) fail "assert_not_contains${label:+ ($label)}: [$needle] found in [$haystack]" ;;
  esac
}

assert_file_contains() {
  local file="$1" needle="$2" label="${3:-}"
  [ -f "$file" ] || fail "assert_file_contains${label:+ ($label)}: no such file $file"
  grep -qF -- "$needle" "$file" || fail "assert_file_contains${label:+ ($label)}: [$needle] not in $file: $(cat "$file")"
}
