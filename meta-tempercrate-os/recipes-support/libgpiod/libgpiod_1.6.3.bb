SUMMARY = "C library for interacting with Linux GPIO character device"
DESCRIPTION = "libgpiod is a C library that provides an API to interact with the Linux GPIO character device"
HOMEPAGE = "https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git/"
LICENSE = "LGPL-2.1-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=2caced0b25dfefd4c601d92bd15116de"

SRC_URI = "git://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git;branch=v1.6.x;protocol=https"
SRCREV = "v1.6.3"

S = "${WORKDIR}/git"

inherit autotools pkgconfig

EXTRA_OECONF = "\
    --enable-tools \
    --enable-bindings-cxx \
    --disable-bindings-python \
"

PACKAGES =+ "${PN}-tools"
FILES:${PN}-tools = "${bindir}/*"

BBCLASSEXTEND = "native nativesdk"


DEPENDS += " autoconf-archive-native"

# Ensure AX_* macros are found during autoreconf
EXTRA_AUTORECONF += "-I ${STAGING_DATADIR_NATIVE}/aclocal"
ACLOCAL_FLAGS:append = " -I ${STAGING_DATADIR_NATIVE}/aclocal"
