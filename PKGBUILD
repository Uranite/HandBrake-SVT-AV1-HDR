# Maintainer: Holger Obermaier <holgerob@gmx.de>
# Contributor: Evangelos Foutras <evangelos@foutrelis.com>
# Contributor: Giovanni Scafora <giovanni@archlinux.org>
# Contributor: Sebastien Piccand <sebcactus gmail com>

pkgname=(
  'handbrake-svt-av1-hdr-llvm-optimized'
  'handbrake-svt-av1-hdr-llvm-optimized-cli'
)

pkgver=1.10.2
pkgrel=1
arch=('x86_64')
url="https://handbrake.fr/"
license=(GPL-2.0-only)
# Link against the split libgcc/libstdc++ runtime packages directly; the
# gcc-libs metapackage only pulls them in and namcap flags it as unneeded.
_commondeps=(
  'bzip2'
  'jansson'
  'lame'
  'libass'
  'libdrm'
  'libgcc'
  'libjpeg-turbo'
  'libogg'
  'libstdc++'
  'libtheora'
  'libva'
  'libvorbis'
  'libvpx'
  'libxml2'
  'numactl'
  'opus'
  'speex'
  'x264'
  'xz'
  'zlib'
)
_guideps=(
  'at-spi2-core'
  'cairo'
  'fontconfig'
  'freetype2'
  'gdk-pixbuf2'
  'glib2'
  'gst-plugins-base'
  'gst-plugins-base-libs'
  'gstreamer'
  'gtk4'
  'harfbuzz'
  'libgudev'
  'pango'
)
makedepends=(
  'base-devel'
  'intltool'
  'python'
  'nasm'
  'wget'
  'cmake'
  'meson'
  'git'
  'clang'
  'lld'
  'llvm'
  'rust'
  'cargo-c'
  'ffnvcodec-headers'
  # AMD VCE encoding on Linux requires Vulkan
  'vulkan-headers'
  "${_commondeps[@]}"
  "${_guideps[@]}"
)
options=('!lto') # https://bugs.archlinux.org/task/72600
source=("HandBrake::git+https://github.com/HandBrake/HandBrake.git" "HandBrake-SVT-AV1-HDR::git+https://github.com/Uranite/HandBrake-SVT-AV1-HDR.git")
sha256sums=('SKIP' 'SKIP')

pkgver() {
  cd "${srcdir}/HandBrake"
  git describe --long | sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g'
}

setup_compiler() {
  export CC="/usr/bin/clang"
  unset CFLAGS
  export CXX="/usr/bin/clang++"
  unset CXXFLAGS
  export CPP="/usr/bin/clang-cpp"
  export LD="/usr/bin/lld"
  # Keep the hardening flags makepkg normally passes (RELRO/BIND_NOW) and
  # restore --as-needed, which the LLVM toolchain override would otherwise drop.
  export LDFLAGS="-fuse-ld=lld -Wl,--as-needed -Wl,-z,relro,-z,now"
  export AR="/usr/bin/llvm-ar"
  export RANLIB="/usr/bin/llvm-ranlib"
  export NM="/usr/bin/llvm-nm"
  export ADDR2LINE="/usr/bin/llvm-addr2line"
  export OBJCOPY="/usr/bin/llvm-objcopy"
  export OBJDUMP="/usr/bin/llvm-objdump"
  export READELF="/usr/bin/llvm-readelf"
  export STRIP="/usr/bin/llvm-strip"
}

build() {
  ./HandBrake-SVT-AV1-HDR/patch.sh
  setup_compiler

  local -a CONFIGURE_OPTIONS=(
    --launch-jobs=0
    --prefix=/usr
    --cc="${CC}"
    --ar="${AR}"
    --ranlib="${RANLIB}"
    --strip="${STRIP}"
    --lto=on
    --enable-qsv
    --enable-vce
    --enable-nvenc
    --enable-libdovi
  )

  cd "${srcdir}/HandBrake" || exit
  ./configure "${CONFIGURE_OPTIONS[@]}"
  make -C build
}

package_handbrake-svt-av1-hdr-llvm-optimized() {
  pkgdesc="Multithreaded video transcoder optimized with LLVM"
  depends=(
    'hicolor-icon-theme'
    "${_commondeps[@]}"
    "${_guideps[@]}"
  )
  optdepends=(
    'gst-plugins-good: for video previews'
    'gst-libav: for video previews'
    'intel-media-sdk: Intel QuickSync support'
    'nvidia-utils: NVIDIA NVENC support'
    'libdvdcss: for decoding encrypted DVDs'
  )
  provides=(handbrake)
  conflicts=(handbrake)

  make \
    --directory="${srcdir}/HandBrake/build" \
    DESTDIR="${pkgdir}" \
    install
  rm "${pkgdir}/usr/bin/HandBrakeCLI"
}

package_handbrake-svt-av1-hdr-llvm-optimized-cli() {
  pkgdesc="Multithreaded video transcoder optimized with LLVM (CLI)"
  depends=("${_commondeps[@]}")
  optdepends=(
    'intel-media-sdk: Intel QuickSync support'
    'nvidia-utils: NVIDIA NVENC support'
    'libdvdcss: for decoding encrypted DVDs'
  )
  provides=(handbrake-cli)
  conflicts=(handbrake-cli)

  install -D "${srcdir}/HandBrake/build/HandBrakeCLI" "${pkgdir}/usr/bin/HandBrakeCLI"
}
