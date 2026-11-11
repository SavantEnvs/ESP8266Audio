#!/usr/bin/env bash
#
# mayhem/test.sh — runs the programs mayhem/build.sh built with the project's normal flags:
#   * kat: decodes one committed fixture per codec and compares the sample count, rate, channel count
#     and an FNV-1a hash of every decoded sample with values recorded from the upstream decoders;
#   * id3: upstream's own assertion test (tests/host/id3.cpp) for AudioFileSourceID3.
# A patch that makes a decoder return early, emit different samples or exit(0) fails here.
# exit 0 = pass.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}


KAT="$SRC/mayhem/build-test/kat"
ID3="$SRC/mayhem/build-test/id3"
passed=0; failed=0

check() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    echo "FAIL $1" >&2
    echo "  expected: $2" >&2
    echo "  actual:   $3" >&2
  fi
}

# <codec> <fixture> <expected kat line>
while read -r codec fixture expected; do
  [ -n "$codec" ] || continue
  if [ ! -x "$KAT" ] || [ ! -f "$SRC/mayhem/$fixture" ]; then
    check "kat $codec" "$expected" "missing $KAT or $fixture"
    continue
  fi
  actual="$("$KAT" "$codec" "$SRC/mayhem/$fixture" 2>/dev/null | tail -n 1)"
  check "kat $codec" "$expected" "$actual"
done <<'KATS'
wav fuzz_wav/testsuite/test_8u_16.wav kat wav ret=0 rate=16000 channels=1 samples=16334 hash=c62e5e6d
mp3 fuzz_mp3/testsuite/pno-cs-head.mp3 kat mp3 ret=0 rate=48000 channels=2 samples=67969 hash=c5b360db
mp3a fuzz_mp3a/testsuite/pno-cs-head.mp3 kat mp3a ret=0 rate=48000 channels=2 samples=67968 hash=3107dd8b
aac fuzz_aac/testsuite/homer.aac kat aac ret=0 rate=44100 channels=2 samples=150528 hash=4b2dcd54
flac fuzz_flac/testsuite/gs-16b-2c-44100hz-head.flac kat flac ret=0 rate=44100 channels=2 samples=36864 hash=913476a0
mod fuzz_mod/testsuite/enigma-head.mod kat mod ret=0 rate=44100 channels=2 samples=883 hash=ca427db5
midi fuzz_midi/testsuite/furelise.mid kat midi ret=0 rate=22050 channels=2 samples=3690409 hash=6c5daa09
opus fuzz_opus/testsuite/gs-16b-2c-44100hz-head.opus kat opus ret=0 rate=48000 channels=2 samples=196645 hash=7fecc4bd
rtttl fuzz_rtttl/testsuite/tune0.rtttl kat rtttl ret=0 rate=22050 channels=2 samples=127008 hash=a78183c5
KATS

# The WAV decoder must refuse a stream with no RIFF header (begin() fails),
# so a decoder stubbed to "succeed" is caught too.
if [ -x "$KAT" ]; then
  junk="$(mktemp)"
  head -c 4096 /dev/zero > "$junk"
  for codec in wav; do
    if "$KAT" "$codec" "$junk" >/dev/null 2>&1; then
      check "kat $codec rejects zeros" "nonzero exit" "exit 0"
    else
      check "kat $codec rejects zeros" "nonzero exit" "nonzero exit"
    fi
  done
  rm -f "$junk"
else
  check "kat rejects zeros" "present" "missing $KAT"
fi

# Upstream's ID3 test asserts on parsed frames; it reads id3fix/ relative to its directory.
if [ -x "$ID3" ] && [ -d "$SRC/tests/host/id3fix" ]; then
  id3_out="$(cd "$SRC/tests/host" && "$ID3" 2>&1)"
  id3_rc=$?
  if [ "$id3_rc" -eq 0 ] && printf '%s\n' "$id3_out" | grep -q '^id3 tests passed$'; then
    check "upstream id3 test" ok ok
  else
    echo "$id3_out" >&2
    check "upstream id3 test" ok "exit $id3_rc"
  fi
else
  check "upstream id3 test" ok "missing $ID3 or tests/host/id3fix"
fi

emit_ctrf "esp8266audio-kat" "$passed" "$failed" 0
