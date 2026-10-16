#!/usr/bin/env bash
# A test that cannot run here (say, tmux lacks side-status) exits 101, the
# tmux regress skip code: run.sh reports it on stderr and does not fail.
. "$(dirname "$0")/../testlib.sh"

cat > "$TEST_TMP/skipped_test.sh" <<'EOF'
exit 101
EOF

if ! bash "$ROOT_DIR/tests/run.sh" "$TEST_TMP/skipped_test.sh" >"$TEST_TMP/out" 2>"$TEST_TMP/err"; then
  fail "run.sh failed on a skipped test: $(cat "$TEST_TMP/err")"
fi
assert_eq "" "$(cat "$TEST_TMP/out")" "nothing on stdout"
assert_file_contains "$TEST_TMP/err" "SKIP $TEST_TMP/skipped_test.sh" "skip reported on stderr"
