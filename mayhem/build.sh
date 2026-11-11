#!/usr/bin/env bash
#
# mayhem/build.sh — builds the sanitized fuzz harnesses (and their -standalone reproducers) plus the
# known-answer test programs mayhem/test.sh runs. Runs in the commit image as `mayhem` in /mayhem.
# Re-runnable and offline: it only reads the checkout and the image's toolchain.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

: "${SRC:=/mayhem}"
cd "$SRC"

FUZZ_DIR="$SRC/mayhem/build-fuzz"        # sanitized + SanCov objects for the harnesses
TEST_DIR="$SRC/mayhem/build-test"   # normal-flag objects for the known-answer programs
HOST="$SRC/tests/host"              # upstream's Arduino shim (Arduino.h, Serial.cpp)
TARGETS="wav mp3 mp3a aac flac mod midi opus rtttl id3"

# Source lists, taken from tests/host/Makefile (upstream's own host build).
LIBMAD="decoder frame bit stream fixed timer layer3 synth huffman version"
LIBHELIX_MP3="dequant mp3dec stproc hufftabs dct32 trigtabs dqchan scalfact polyphase buffers bitstream imdct subband huffman mp3tabs"
LIBHELIX_AAC="decelmnt dct4 dequant sbrhuff sbrmath aactabs stproc hufftabs sbrtabs sbrfft filefmt tns trigtabs fft pns sbrfreq sbrside sbrhfadj buffers bitstream noiseless imdct aacdec sbrhfgen sbrqmf huffmanaac sbr sbrimdct"
LIBFLAC="md5 window memory cpu fixed format lpc crc bitreader bitmath stream_decoder float"

list() { local dir="$1"; shift; for f in "$@"; do echo "src/$dir/$f.c"; done; }

# compile_set <outdir> <lang c|c++> <cflags> <file>... : one object per source, in parallel.
compile_set() {
  local out="$1" lang="$2" flags="$3"; shift 3
  mkdir -p "$out"
  local cc="$CC" std=""
  [ "$lang" = "c++" ] && { cc="$CXX"; std="-std=c++11"; }
  printf '%s\n' "$@" | xargs -P "$MAYHEM_JOBS" -I{} bash -c \
    'f="$1"; o="$2/$(echo "${f%.*}" | tr / _).o"; '"$cc"' '"$std"' '"$flags"' -include Arduino.h -I src -I mayhem/shim -I tests/host -c "$f" -o "$o"' _ {} "$out"
}

# build_objects <rootdir> <cflags>: libraries (C) and Audio*.cpp for every target, under <rootdir>/<group>/.
build_objects() {
  local root="$1" flags="$2"
  rm -rf "$root"; mkdir -p "$root"
  # array-bounds is relaxed for libmad (synth.c indexes below a rebased pointer by design) and the Helix
  # MP3 decoder (huffman.c reads sfBand->l[] past its end on a valid file); ASan and the rest of UBSan halt.
  # signed-integer-overflow is also relaxed for libmad only: its mad_fixed_t (Q28) multiply/accumulate wraps
  # in 32 bits by design (layer3.c requantize/stereo/IMDCT), which fans out into one defect per source line.
  compile_set "$root/libmad" c "$flags -fno-sanitize=array-bounds,signed-integer-overflow" $(list libmad $LIBMAD)
  # Helix MP3 only has portable math under -DARDUINO; mayhem/shim/Arduino.h lets the host shim cope.
  compile_set "$root/helix_mp3" c "$flags -DARDUINO -fno-sanitize=array-bounds" $(list libhelix-mp3 $LIBHELIX_MP3)
  # FillBufferWithValidFrame() reads buff[-1] on its first call (buffValid == 0), so every input would
  # halt on array-bounds; relaxed for this one TU only.
  compile_set "$root/helix_mp3" c++ "$flags -DARDUINO -fno-sanitize=array-bounds" src/AudioGeneratorMP3a.cpp
  compile_set "$root/helix_aac" c "$flags -DUSE_DEFAULT_STDLIB" $(list libhelix-aac $LIBHELIX_AAC)
  compile_set "$root/libflac" c "$flags -DUSE_DEFAULT_STDLIB -I src/libflac" $(list libflac $LIBFLAC)
  compile_set "$root/libopus" c "$flags -DUSE_DEFAULT_STDLIB" $(find src/libopus -name '*.c' | sort)
  compile_set "$root/audio" c++ "$flags" \
    src/AudioLogger.cpp src/AudioFileSourcePROGMEM.cpp src/AudioFileSourceSTDIO.cpp src/AudioFileSourceID3.cpp \
    src/AudioGeneratorWAV.cpp src/AudioGeneratorMP3.cpp src/AudioGeneratorAAC.cpp \
    src/AudioGeneratorFLAC.cpp src/AudioGeneratorMOD.cpp src/AudioGeneratorMIDI.cpp src/AudioGeneratorOpus.cpp \
    src/AudioGeneratorRTTTL.cpp tests/host/Serial.cpp
}

objs() { ls "$1"/*.o; }

# Objects every target links, plus the one generator (and its library) the target fuzzes.
base_objs() { local d="$1"; for f in AudioLogger AudioFileSourcePROGMEM AudioFileSourceSTDIO AudioFileSourceID3 tests_host_Serial; do ls "$d/audio/"*"$f.o"; done; }
target_objs() {
  local d="$1" t="$2" o
  o="$(base_objs "$d")"
  case "$t" in
    wav) o="$o $d/audio/src_AudioGeneratorWAV.o" ;;
    mp3) o="$o $d/audio/src_AudioGeneratorMP3.o $(objs "$d/libmad")" ;;
    mp3a) o="$o $(objs "$d/helix_mp3")" ;;
    aac) o="$o $d/audio/src_AudioGeneratorAAC.o $(objs "$d/helix_aac")" ;;
    flac) o="$o $d/audio/src_AudioGeneratorFLAC.o $(objs "$d/libflac")" ;;
    mod) o="$o $d/audio/src_AudioGeneratorMOD.o" ;;
    midi) o="$o $d/audio/src_AudioGeneratorMIDI.o" ;;
    opus) o="$o $d/audio/src_AudioGeneratorOpus.o $(objs "$d/libopus")" ;;
    rtttl) o="$o $d/audio/src_AudioGeneratorRTTTL.o" ;;
    id3) ;;
  esac
  echo $o
}

# 1) The project, instrumented: sanitizers + SanCov (fuzzer-no-link) + DWARF <= 3.
# shift-base is relaxed: the WAV 8-bit path and the Helix/libmad fixed-point code left-shift negative or
# overflowing values on every input (benign on every supported compiler); the rest of UBSan still halts.
FUZZ_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fno-sanitize=shift-base -fsanitize=fuzzer-no-link"
build_objects "$FUZZ_DIR" "$FUZZ_FLAGS"

# 2) Harnesses: a libFuzzer binary and a run-once -standalone reproducer per target.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -x c -c "$STANDALONE_FUZZ_MAIN" -o "$FUZZ_DIR/standalone_main.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$FUZZ_DIR/lsan_off.o"
for t in $TARGETS; do
  libs="$(target_objs "$FUZZ_DIR" "$t")"
  common="-std=c++11 $FUZZ_FLAGS -include Arduino.h -I src -I mayhem/shim -I tests/host -I mayhem mayhem/fuzz_$t.cpp"
  $CXX $common $LIB_FUZZING_ENGINE $libs "$FUZZ_DIR/lsan_off.o" -o "$SRC/fuzz_$t"
  $CXX $common "$FUZZ_DIR/standalone_main.o" $libs "$FUZZ_DIR/lsan_off.o" -o "$SRC/fuzz_$t-standalone"
done

# 3) The test programs, with the project's normal flags: a known-answer probe and upstream's ID3 test.
TEST_FLAGS="-O1 -g $COVERAGE_FLAGS"
build_objects "$TEST_DIR" "$TEST_FLAGS"
all_libs="$(objs "$TEST_DIR/libmad") $(objs "$TEST_DIR/helix_mp3") $(objs "$TEST_DIR/helix_aac") $(objs "$TEST_DIR/libflac") $(objs "$TEST_DIR/libopus")"
$CXX -std=c++11 $TEST_FLAGS -include Arduino.h -I src -I mayhem/shim -I tests/host -I mayhem mayhem/kat.cpp \
  $(objs "$TEST_DIR/audio") $all_libs -o "$TEST_DIR/kat"
$CXX -std=c++11 $TEST_FLAGS -include Arduino.h -I src -I mayhem/shim -I tests/host tests/host/id3.cpp \
  src/AudioFileSourceSTDIO.cpp src/AudioFileSourceID3.cpp src/AudioLogger.cpp tests/host/Serial.cpp -o "$TEST_DIR/id3"
