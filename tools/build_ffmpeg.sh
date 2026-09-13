#!/usr/bin/env bash
# Build minimal FFmpeg static libraries for armv7 / iOS 6.0+ with the Theos
# iOS toolchain, so OldEmby can demux and software-decode containers the iOS
# system player cannot open (MKV, AVI, WMV, RMVB, AC3/DTS audio…).
#
# Output layout (consumed by the Makefile):
#   vendor/ffmpeg/include  ->  headers for #include "libavformat/avformat.h"
#   vendor/ffmpeg/lib      ->  libavformat.a libavcodec.a libavutil.a
#                              libswscale.a libswresample.a
#
# Strategy: try a NEON/asm build first; if configure or make fails (new clang
# vs. old asm), retry once with --disable-asm so the app still ships a working
# - if slower - decoder.
set -uo pipefail

FFMPEG_VER="${FFMPEG_VER:-2.8.22}"
PREFIX="$PWD/vendor/ffmpeg"
BUILD="$PWD/.ffmpeg-build"
: "${THEOS:?THEOS must point to the theos tree}"
SDK="$THEOS/sdks/iPhoneOS9.3.sdk"
CC="$THEOS/toolchain/linux/iphone/bin/clang"
export PATH="$THEOS/toolchain/linux/iphone/bin:$PATH"

if [ -f "$PREFIX/lib/libavformat.a" ]; then
  echo "ffmpeg: $PREFIX already built, skipping"
  exit 0
fi
for req in "$CC" "$SDK"; do
  [ -e "$req" ] || { echo "::error::ffmpeg: missing $req (toolchain/SDK step must run first)"; exit 1; }
done

mkdir -p "$BUILD"
cd "$BUILD"
if [ ! -d "ffmpeg-$FFMPEG_VER" ]; then
  echo "Downloading FFmpeg $FFMPEG_VER…"
  curl -fLsS --retry 3 --retry-delay 5 -o src.tar.xz \
    "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VER.tar.xz" \
    || curl -fLsS --retry 3 -o src.tar.gz \
    "https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n$FFMPEG_VER.tar.gz"
  if [ -f src.tar.xz ]; then tar -xJf src.tar.xz; else tar -xzf src.tar.gz; fi
fi
if [ ! -f "ffmpeg-$FFMPEG_VER/configure" ]; then
  echo "::error::ffmpeg: source not available at $BUILD/ffmpeg-$FFMPEG_VER"
  exit 1
fi
cd "ffmpeg-$FFMPEG_VER"

# Sizing strategy: keep every DEMUXER/DECODER/PARSER/PBSF enabled (Emby
# libraries contain MKV/AVI/WMV/RM/TS with arbitrary codec mixes, and a
# missing decoder means "please transcode" for the user), and cut what a
# client never needs: encoders, muxers, filters, programs, devices, postproc.
#
# Toolchain notes (learned the hard way in CI):
#   * The Linux clang here defaults to the HOST triple; like Theos itself we
#     must pass -target armv7-apple-ios6.0 or every link test fails.
#   * Archives go through the toolchain's llvm-ar (Apple ld reads Mach-O
#     archives) and stripping is left to the app link (GNU strip cannot
#     touch Mach-O object files).
AR_BIN="$THEOS/toolchain/linux/iphone/bin/llvm-ar"
[ -x "$AR_BIN" ] || AR_BIN="$(command -v ar)"
common_args=(
  --prefix="$PREFIX"
  --target-os=darwin
  --arch=arm
  --cpu=cortex-a8
  --enable-cross-compile
  --cc="$CC"
  --ar="$AR_BIN"
  --sysroot="$SDK"
  --enable-pic
  --enable-small
  --disable-doc
  --disable-programs
  --disable-stripping
  --disable-avdevice
  --disable-postproc
  --disable-encoders
  --disable-muxers
  --disable-filters
  --disable-hwaccels
  --disable-bzlib
  --disable-lzma
  --disable-iconv
  --extra-cflags="-target armv7-apple-ios6.0 -miphoneos-version-min=6.0 -fno-builtin-memset -Wno-implicit-function-declaration -Wno-int-conversion -Wno-incompatible-pointer-types -Wno-incompatible-function-pointer-types"
  --extra-ldflags="-target armv7-apple-ios6.0 -miphoneos-version-min=6.0 -framework Security -framework CoreFoundation"
)

build_try() {
  local asm_flag="$1"
  echo "=== ffmpeg configure ($asm_flag) ==="
  make distclean >/dev/null 2>&1 || true
  ./configure "${common_args[@]}" $asm_flag > ffbuild.log 2>&1 || { tail -n 30 ffbuild.log; return 1; }
  make -j"$(nproc)" >> ffbuild.log 2>&1 || { tail -n 30 ffbuild.log; return 1; }
  make install > /dev/null 2>> ffbuild.log
}

if build_try "--enable-neon"; then
  echo "ffmpeg: built with NEON asm"
elif build_try "--disable-asm --disable-neon"; then
  echo "ffmpeg: asm build failed; built pure-C fallback (decode will be slower)"
else
  echo "::error::ffmpeg: both asm and no-asm builds failed"
  echo "--- config.log errors ---"
  grep -iE "error|fatal|cannot|undefined" config.log 2>/dev/null | tail -n 40 || true
  echo "--- last compiler invocations ---"
  tail -n 60 ffbuild.log 2>/dev/null || true
  exit 1
fi

ls -lh "$PREFIX/lib" "$PREFIX/include" | head -30
