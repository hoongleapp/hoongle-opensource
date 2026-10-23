#!/bin/bash
# build_jdk_native.sh — 번들 자바 런타임의 그림·글꼴 네이티브 라이브러리를 OpenJDK 소스로 다시 짓는다.
#
# 무엇을: libjavajpeg · liblcms · libfreetype · libfontmanager · libsplashscreen (.dylib, arm64)
#   Homebrew openjdk@21 의 같은 파일은 Homebrew 의 jpeg-turbo·little-cms2·freetype·harfbuzz·giflib·libpng
#   (/opt/homebrew/…, 팀 서명 없음, minos 26.0)에 기대어, 구매자 맥에는 없고 강화 런타임 라이브러리 검증도
#   "다른 팀"이라 거절한다 → 엔진의 ImageIO.read(JPEG·ICC PNG·CMYK JPEG)가 실패했다.
#   여기서는 OpenJDK 가 소스에 함께 넣어 둔 코덱(IJG jpeg 6b, lcms2, freetype, harfbuzz, giflib, libpng)을
#   그대로 넣어 지어, 바깥 의존이 시스템 라이브러리(/usr/lib, /System)와 같은 런타임의 libjava·libjvm·libawt·
#   libawt_lwawt·libosxapp·libfreetype(@rpath)뿐이 되게 한다.
# 어느 소스로: ~/앱만들기/오픈소스_소스/openjdk-jdk21u-jdk-21.0.12.1-ga.tar.gz (jdk21u 태그 jdk-21.0.12.1-ga,
#   Homebrew openjdk@21 21.0.12.1 과 같은 판, sha256 아래 SRC_SHA256). 소스는 한 글자도 고치지 않는다.
#   내려받지 않는다 — 이미 공개한(GPL 소스 제공) 그 파일만 쓴다.
# 어떤 옵션으로: 소스의 make/modules/java.desktop/lib/Awt2dLibraries.gmk(라이브러리별 소스·제외 파일·define·
#   include·링크 대상)와 make/autoconf/flags-cflags.m4·flags-ldflags.m4·make/common/modules/LibCommon.gmk
#   (macOS·clang·release 의 공통 CFLAGS_JDKLIB: -D_ALLBSD_SOURCE -D_DARWIN_UNLIMITED_SELECT -DMACOSX -DNDEBUG
#   -D_LITTLE_ENDIAN -DARCH="aarch64" -Daarch64 -D_LP64=1 -fvisibility=hidden -std=c11 / -std=c++14)를 그대로 옮겼다.
#   다른 점은 둘: 최소 macOS 를 11.0 대신 앱과 같은 13.0 으로(-mmacosx-version-min=13.0
#   -DMAC_OS_X_VERSION_MIN_REQUIRED=130000), 이 맥 아키텍처 arm64 하나. zlib 은 시스템 것(/usr/lib/libz)을 쓴다
#   (Homebrew 판과 같음). JNI 머리글(javac -h)은 같은 소스의 자바 파일로 이 각본이 만든다.
#   링크 상대 libjava·libjvm·libawt·libawt_lwawt·libosxapp 는 $JAVA_HOME/jmods 에서 꺼낸 것(설치 이름 @rpath/…).
#
# 사용법: tools/build_jdk_native.sh            → build/jdk-native/{lib,legal}/ (캐시: 같은 입력이면 다시 짓지 않음)
#         tools/build_jdk_native.sh --force    → 캐시를 무시하고 다시 지음
#   환경: JAVA_HOME(기본 /opt/homebrew/opt/openjdk@21) · JDK_SRC_TGZ(소스 tar.gz) · JDK_NATIVE_OUT(기본 build/jdk-native)
#         JDK_NATIVE_MINOS(기본 13.0 — build_app.sh 의 MIN_MACOS)
# 결과: build/jdk-native/lib/*.dylib (설치 이름 @rpath/<이름>, rpath @loader_path/. @loader_path/server, 임시 서명 —
#       build_app.sh 가 runtime/lib 에 넣고 팀 서명한다), build/jdk-native/legal/*.md (번들 코덱 고지),
#       build/jdk-native/stamp (캐시 열쇠). 끝에 스스로 검사: 바깥 의존 0 · minos 13.0 · Homebrew 판과 내보내는 기호 견줌.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}"
die() { echo "✗ build_jdk_native: $*" >&2; exit 1; }
JDK_HOME="$JAVA_HOME"; [ -d "$JDK_HOME/libexec/openjdk.jdk/Contents/Home" ] && JDK_HOME="$JDK_HOME/libexec/openjdk.jdk/Contents/Home"
SRC_TGZ="${JDK_SRC_TGZ:-$HOME/앱만들기/오픈소스_소스/openjdk-jdk21u-jdk-21.0.12.1-ga.tar.gz}"
SRC_SHA256="9c719670e7be6080a46ebeb1223a375bd53818ba7c5ae11f11a02907b593775f"
SRC_TOP="jdk21u-jdk-21.0.12.1-ga"
JDK_VERSION="21.0.12.1"
MINOS="${JDK_NATIVE_MINOS:-13.0}"   # build_app.sh 가 MIN_MACOS(= Info.plist LSMinimumSystemVersion)를 넘긴다
[[ "$MINOS" =~ ^([0-9]+)\.([0-9]+)$ ]] || die "최소 macOS 꼴이 이상함: $MINOS (예 13.0)"
MINOS_NODOTS=$(printf '%d%02d00' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")   # 13.0 → 130000 (MAC_OS_X_VERSION_MIN_REQUIRED)
OUT="${JDK_NATIVE_OUT:-build/jdk-native}"
LIBS="libjavajpeg libfreetype liblcms libfontmanager libsplashscreen"
FORCE=""; [ "${1:-}" = "--force" ] && FORCE=1


# ── 입력 확인 (소스 파일은 다시 지을 때만 있으면 됨 — 캐시가 맞으면 소스 없는 맥에서도 그대로 씀) ──────────────
[ -f "$JDK_HOME/release" ] || die "JDK 가 없음: $JDK_HOME"
grep -q "^JAVA_VERSION=\"$JDK_VERSION\"" "$JDK_HOME/release" || die "JDK 판이 $JDK_VERSION 이 아님 ($(grep ^JAVA_VERSION= "$JDK_HOME/release")) — 소스와 같은 판이어야 함"
CC_VER=$(cc --version | head -1)
# 캐시 열쇠: 이 각본 · 소스 · JDK 판 · 컴파일러 · 최소 macOS 가 같으면 그대로 쓴다
KEY="script=$(shasum -a 256 "$0" | cut -c1-64) src=$SRC_SHA256 jdk=$JDK_VERSION cc=$CC_VER minos=$MINOS"
if [ -z "$FORCE" ] && [ -f "$OUT/stamp" ] && [ "$(cat "$OUT/stamp")" = "$KEY" ]; then
  ok=1; for l in $LIBS; do [ -f "$OUT/lib/$l.dylib" ] || ok=""; done
  if [ -n "$ok" ]; then echo "    jdk-native 캐시 그대로 ($OUT)"; exit 0; fi
fi
echo "==> JDK 네이티브 라이브러리 다시 짓기 (소스 $SRC_TOP, minos $MINOS, arm64)"
[ -f "$SRC_TGZ" ] || die "소스가 없음: $SRC_TGZ (내려받지 않음 — 오픈소스_소스 폴더의 공개한 파일을 씀)"
have_sha=$(shasum -a 256 "$SRC_TGZ" | cut -c1-64)
[ "$have_sha" = "$SRC_SHA256" ] || die "소스 sha256 이 다름: $have_sha"

W="$OUT/work"
rm -rf "$W" "$OUT/lib" "$OUT/legal" "$OUT/stamp"
mkdir -p "$W" "$OUT/lib" "$OUT/legal"
tar xzf "$SRC_TGZ" -C "$W" \
  "$SRC_TOP/src/java.desktop/share/native" "$SRC_TOP/src/java.desktop/macosx/native" \
  "$SRC_TOP/src/java.desktop/unix/native" "$SRC_TOP/src/java.desktop/share/legal" \
  "$SRC_TOP/src/java.desktop/share/classes" "$SRC_TOP/src/java.desktop/macosx/classes" \
  "$SRC_TOP/src/java.base/share/native/include" "$SRC_TOP/src/java.base/unix/native/include" \
  "$SRC_TOP/src/java.base/share/native/libjava" "$SRC_TOP/src/java.base/unix/native/libjava" \
  "$SRC_TOP/src/hotspot/share/include" "$SRC_TOP/src/hotspot/os/posix/include"
S="$W/$SRC_TOP/src"
D="$S/java.desktop"

# ── 링크 상대(같은 런타임의 라이브러리) — jmods 에서 꺼냄, 설치 이름이 @rpath/… 인 원본 ──────────────
mkdir -p "$W/jmods/base" "$W/jmods/desktop" "$W/linklib"
"$JDK_HOME/bin/jmod" extract --dir "$W/jmods/base" "$JDK_HOME/jmods/java.base.jmod"
"$JDK_HOME/bin/jmod" extract --dir "$W/jmods/desktop" "$JDK_HOME/jmods/java.desktop.jmod"
cp "$W/jmods/base/lib/libjava.dylib" "$W/jmods/base/lib/server/libjvm.dylib" "$W/linklib/"
cp "$W/jmods/desktop/lib/libawt.dylib" "$W/jmods/desktop/lib/libawt_lwawt.dylib" "$W/jmods/desktop/lib/libosxapp.dylib" "$W/linklib/"

# ── JNI 머리글 (빌드의 support/headers/java.desktop 과 같은 것: javac -h) ─────────────────────────
JH="$W/headers"; mkdir -p "$JH" "$W/hclasses"
# 다섯 라이브러리와 그 머리글 폴더가 #include 하는데 소스 트리에 없는 "a_b_C.h" = 자바 클래스 a.b.C 의 JNI 머리글.
# 그 클래스의 .java 를 찾아(share·macosx 쪽) 모아 둔다 (Outer_00024Inner.h 는 Outer.java 에서 나옴)
find "$S" -name '*.h' -exec basename {} \; | sort -u > "$W/have_h"
INC_DIRS=()
for d in libjavajpeg liblcms libfontmanager libharfbuzz libfreetype libsplashscreen libosxapp \
         common/awt common/awt/utility common/awt/debug common/font libawt/java2d libawt/java2d/pipe libawt/java2d/loops; do
  for os in macosx unix share; do if [ -d "$D/$os/native/$d" ]; then INC_DIRS+=("$D/$os/native/$d"); fi; done
done
JAVA_SRCS=""
grep -rhoE '#[[:space:]]*include[[:space:]]*"[a-z][A-Za-z0-9]*_[A-Za-z0-9_]+\.h"' "${INC_DIRS[@]}" \
  | sed -E 's/.*"([A-Za-z0-9_]+)\.h"/\1.h/' | sort -u | comm -23 - "$W/have_h" > "$W/gen_h"
while read -r h; do
  c=$(printf '%s' "${h%.h}" | sed -e 's/_00024.*//' -e 's|_|/|g')
  found=""
  for os in share macosx; do
    f="$D/$os/classes/$c.java"
    if [ -f "$f" ] && [ ! -f "$W/hsrc/$c.java" ]; then
      mkdir -p "$W/hsrc/$(dirname "$c")"; cp "$f" "$W/hsrc/$c.java"; JAVA_SRCS+=" $W/hsrc/$c.java"; found=1; break
    elif [ -f "$W/hsrc/$c.java" ]; then found=1; break; fi
  done
  # 못 찾은 것(X11TextRenderer 등)은 macOS 에서 빼는 파일 몫 — 정말 모자라면 아래 컴파일이 멈춘다
done < "$W/gen_h"
# 그 파일들만 java.desktop 모듈에 덧대어 컴파일 — 나머지 클래스는 이 JDK 의 java.desktop(같은 판)에서 찾는다
# shellcheck disable=SC2086
"$JDK_HOME/bin/javac" -nowarn -XDsuppressNotes -proc:none --patch-module "java.desktop=$W/hsrc" \
  -implicit:none -d "$W/hclasses" -h "$JH" $JAVA_SRCS

# ── 공통 옵션 (CFLAGS_JDKLIB, macOS·clang·release) ─────────────────────────────────────────────
NCPU=$(sysctl -n hw.ncpu)
TARGET=(-arch arm64 -mmacosx-version-min="$MINOS")
COMMON=("${TARGET[@]}" -DMAC_OS_X_VERSION_MIN_REQUIRED="$MINOS_NODOTS"
  -I"$S/java.base/share/native/include" -I"$S/java.base/unix/native/include"
  -I"$S/java.base/share/native/libjava" -I"$S/java.base/unix/native/libjava"
  -I"$S/hotspot/share/include" -I"$S/hotspot/os/posix/include"
  -D_ALLBSD_SOURCE -D_DARWIN_UNLIMITED_SELECT -DMACOSX -DNDEBUG
  -D_LITTLE_ENDIAN '-DARCH="aarch64"' -Daarch64 -D_LP64=1
  -fvisibility=hidden -I"$JH" -w)
CONLY=(-std=c11)
CXXONLY=(-std=c++14)
LDCOMMON=("${TARGET[@]}" -dynamiclib -Wl,-rpath,@loader_path/. -Wl,-rpath,@loader_path/server
  -Wl,-headerpad_max_install_names -L"$W/linklib" -L"$OUT/lib")

# 상대 경로 하나(예 common/awt)를 macosx·unix·share 쪽에서 있는 것만 -I 로 (ProcessDir 과 같음)
hdirs() { local d os; for d in "$@"; do for os in macosx unix share; do if [ -d "$D/$os/native/$d" ]; then printf -- '-I%s\n' "$D/$os/native/$d"; fi; done; done; }

# compile <obj 폴더> <옵션 파일> <소스 목록 파일> — 소스 하나당 .o 하나, 병렬. 파일별 덧옵션은 FILE_FLAGS_<이름> 로
compile_all() {
  local objdir="$1" flagsfile="$2" listfile="$3"
  mkdir -p "$objdir"
  # shellcheck disable=SC2016
  OBJDIR="$objdir" FLAGSFILE="$flagsfile" xargs -P "$NCPU" -n 1 /bin/bash -c '
    src="$1"; objdir="$OBJDIR"; flagsfile="$FLAGSFILE"; base=$(basename "$src"); obj="$objdir/${base%.*}.o"
    extra=""; [ -f "$flagsfile.$base" ] && extra=$(cat "$flagsfile.$base")
    case "$src" in
      *.cc|*.cpp) set -- clang++ $(cat "$flagsfile.cxx") ;;
      *.m)        set -- clang   $(cat "$flagsfile.c") ;;
      *)          set -- clang   $(cat "$flagsfile.c") ;;
    esac
    # shellcheck disable=SC2086
    "$@" $extra -c "$src" -o "$obj" || { echo "✗ 컴파일 실패: $src" >&2; exit 255; }
  ' _ < "$listfile"
}
# 옵션 묶음을 파일로 (공백 든 경로가 없게 작업 폴더는 ASCII 로 만든다는 전제 — 아래에서 확인)
write_flags() {  # <파일> <C 전용/C++ 전용 옵션 이름: c|cxx> 옵션…
  local f="$1" kind="$2"; shift 2
  printf '%s\n' "$@" > "$f.$kind"
}
case "$ROOT$W" in *" "*) die "작업 경로에 빈칸이 있음: $ROOT/$W";; esac

link_lib() {  # <이름> <링커 clang|clang++> <obj 폴더> 링크 옵션…
  local name="$1" linker="$2" objdir="$3"; shift 3
  "$linker" "${LDCOMMON[@]}" -Wl,-install_name,"@rpath/$name.dylib" -o "$OUT/lib/$name.dylib" "$objdir"/*.o "$@"
}

# ── libjavajpeg: share/native/libjavajpeg 전부(번들 IJG jpeg 6b + imageioJPEG.c·jpegdecoder.c), -O3 ─────────
B="$W/b/javajpeg"; mkdir -p "$B"
find "$D/share/native/libjavajpeg" -name '*.c' | sort > "$B/srcs"
write_flags "$B/fl" c "${COMMON[@]}" "${CONLY[@]}" -O3 $(hdirs libjavajpeg)
compile_all "$B/obj" "$B/fl" "$B/srcs"
link_lib libjavajpeg clang "$B/obj" -ljava -ljvm

# ── libfreetype: share/native/libfreetype(번들 freetype), -DFT2_BUILD_LIBRARY, -O3 (FREETYPE_TO_USE=bundled) ───
B="$W/b/freetype"; mkdir -p "$B"
find "$D/share/native/libfreetype" -name '*.c' | sort > "$B/srcs"
write_flags "$B/fl" c "${COMMON[@]}" "${CONLY[@]}" -O3 -DFT2_BUILD_LIBRARY -I"$D/share/native/libfreetype/include" $(hdirs libfreetype)
compile_all "$B/obj" "$B/fl" "$B/srcs"
link_lib libfreetype clang "$B/obj"

# ── liblcms: share/native/liblcms 전부(번들 lcms2 + LCMS.c), -DCMS_DONT_USE_FAST_FLOOR -DCMS_NO_HALF_SUPPORT, -O3 ──
B="$W/b/lcms"; mkdir -p "$B"
find "$D/share/native/liblcms" -name '*.c' | sort > "$B/srcs"
write_flags "$B/fl" c "${COMMON[@]}" "${CONLY[@]}" -O3 -DCMS_DONT_USE_FAST_FLOOR -DCMS_NO_HALF_SUPPORT \
  $(hdirs liblcms common/awt/debug libawt/java2d)
compile_all "$B/obj" "$B/fl" "$B/srcs"
link_lib liblcms clang "$B/obj" -lawt -ljvm -ljava

# ── libfontmanager: share/native/libfontmanager + 번들 libharfbuzz (제외 파일은 .gmk 대로), -O3, C++ 로 링크 ──────
B="$W/b/fontmanager"; mkdir -p "$B"
FM_EXCLUDE="hb-ft.cc hb-subset-cff-common.cc hb-subset-cff1.cc hb-subset-cff2.cc hb-subset-input.cc hb-subset-plan.cc
  hb-subset.cc hb-subset-instancer-solver.cc gsubgpos-context.cc hb-style.cc X11FontScaler.c X11TextRenderer.c
  fontpath.c lcdglyph.c AccelGlyphCache.c"
{ find "$D/share/native/libfontmanager" "$D/unix/native/libfontmanager" "$D/share/native/libharfbuzz" \
    \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.m' \) ; } | sort | while read -r f; do
  skip=""; for x in $FM_EXCLUDE; do if [ "$(basename "$f")" = "$x" ]; then skip=1; fi; done
  if [ -z "$skip" ]; then echo "$f"; fi
done > "$B/srcs"
HB_CFLAGS=(-DGETPAGESIZE -DHAVE_MPROTECT -DHAVE_PTHREAD -DHAVE_SYSCONF -DHAVE_SYS_MMAN_H -DHAVE_UNISTD_H
  -DHB_NO_PRAGMA_GCC_DIAGNOSTIC -DHAVE_INTEL_ATOMIC_PRIMITIVES -DHB_NO_VISIBILITY)
FM_FLAGS=("${HB_CFLAGS[@]}" -I"$D/share/native/libfreetype/include" -DLE_STANDALONE -DHEADLESS -O3
  $(hdirs libfontmanager libharfbuzz common/awt common/awt/utility common/font libawt/java2d libawt/java2d/pipe libawt/java2d/loops))
write_flags "$B/fl" c "${COMMON[@]}" "${CONLY[@]}" "${FM_FLAGS[@]}"
write_flags "$B/fl" cxx "${COMMON[@]}" "${CXXONLY[@]}" "${FM_FLAGS[@]}"
compile_all "$B/obj" "$B/fl" "$B/srcs"
link_lib libfontmanager clang++ "$B/obj" -lfreetype -lawt -ljava -ljvm -lawt_lwawt \
  -framework CoreText -framework CoreFoundation -framework CoreGraphics

# ── libsplashscreen: share·macosx native/libsplashscreen(번들 giflib·libpng) + 번들 libjavajpeg(imageioJPEG.c·
#    jpegdecoder.c 빼고), /unix/ 제외, -Os, 몇 파일은 -x objective-c -O0 (.gmk 그대로), zlib 은 시스템 ─────────
B="$W/b/splashscreen"; mkdir -p "$B"
{ find "$D/share/native/libsplashscreen" "$D/macosx/native/libsplashscreen" \( -name '*.c' -o -name '*.m' \)
  find "$D/share/native/libjavajpeg" -name '*.c'; } | sort | while read -r f; do
  case "$(basename "$f")" in imageioJPEG.c|jpegdecoder.c|pngtest.c) ;; *) echo "$f";; esac
done > "$B/srcs"
SP_FLAGS=(-DSPLASHSCREEN -DPNG_NO_MMX_CODE -DPNG_ARM_NEON_OPT=0 -DPNG_ARM_NEON_IMPLEMENTATION=0 -DWITH_MACOSX -Os
  $(hdirs libsplashscreen common/awt/utility libsplashscreen/giflib libsplashscreen/libpng libosxapp)
  -I"$D/share/native/libjavajpeg" -I"$S/java.base/share/native/libjava" -I"$S/java.base/unix/native/libjava")
write_flags "$B/fl" c "${COMMON[@]}" "${CONLY[@]}" "${SP_FLAGS[@]}"
for f in java_awt_SplashScreen.c splashscreen_gfx_impl.c splashscreen_gif.c splashscreen_impl.c splashscreen_jpeg.c splashscreen_png.c; do
  echo "-x objective-c -O0" > "$B/fl.$f"
done
echo "-O0" > "$B/fl.splashscreen_sys.m"
compile_all "$B/obj" "$B/fl" "$B/srcs"
link_lib libsplashscreen clang "$B/obj" -ljava -ljvm -lm -lpthread -liconv -losxapp -lz \
  -framework ApplicationServices -framework Foundation -framework Security -framework Cocoa -framework Metal

# ── 번들 코덱 고지 (jlink 가 Homebrew 판에는 넣지 않은 것 — 소스의 같은 파일) ──────────────────────────
for m in jpeg lcms freetype harfbuzz giflib libpng; do cp "$D/share/legal/$m.md" "$OUT/legal/$m.md"; done

# ── 스스로 검사: 바깥 의존 0 · minos · 내보내는 기호가 Homebrew 판의 것을 모두 가짐 ─────────────────────
bad=0
HB_LIB="$JDK_HOME/lib"
for l in $LIBS; do
  f="$OUT/lib/$l.dylib"
  m=$(vtool -show-build "$f" | awk '/minos/{print $2; exit}')
  deps=$(otool -L "$f" | tail -n +3 | awk '{print $1}')
  ext=$(printf '%s\n' "$deps" | grep -vE '^(/usr/lib/|/System/Library/|@rpath/lib(java|jvm|awt|awt_lwawt|osxapp|freetype)\.dylib$)' || true)
  miss="-"
  if [ -f "$HB_LIB/$l.dylib" ]; then
    nm -gU "$HB_LIB/$l.dylib" | awk '{print $NF}' | sort -u > "$W/$l.want"
    nm -gU "$f" | awk '{print $NF}' | sort -u > "$W/$l.have"
    miss=$(comm -23 "$W/$l.want" "$W/$l.have" | wc -l | tr -d ' ')
    [ "$miss" = 0 ] || { echo "    ✗ $l: Homebrew 판에 있는 기호 $miss 개가 없음:"; comm -23 "$W/$l.want" "$W/$l.have" | sed 's/^/        /'; bad=1; }
  fi
  [ "$m" = "$MINOS" ] || { echo "    ✗ $l: minos $m (≠ $MINOS)"; bad=1; }
  [ -z "$ext" ] || { echo "    ✗ $l: 바깥 의존: $ext"; bad=1; }
  echo "    $l.dylib  minos $m  의존 $(printf '%s ' $deps)  빠진 기호 $miss"
done
[ "$bad" = 0 ] || die "검사 실패"
rm -rf "$W"   # 작업 폴더(소스 풀어 둔 것·jmods)는 지움 — 결과와 고지만 남김
echo "$KEY" > "$OUT/stamp"
echo "    완료: $OUT/lib ($(du -sh "$OUT/lib" | cut -f1))"
