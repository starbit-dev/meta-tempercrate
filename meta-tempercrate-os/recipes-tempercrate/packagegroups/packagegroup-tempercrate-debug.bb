SUMMARY = "TemperCrate debug tools packages"
DESCRIPTION = "Debugging tools for development images (gdbserver, strace, etc.)"
LICENSE = "MIT"

# Must be BEFORE inherit packagegroup
ALLARCH_PACKAGEGROUP = "0"
PACKAGE_ARCH = "${MACHINE_ARCH}"

inherit packagegroup
PACKAGE_ARCH = "${MACHINE_ARCH}"

RDEPENDS:${PN} = " \
    gdbserver \
    strace \
    ltrace \
    file \
    procps \
    coreutils \
    glibc-utils \
    ldd \
    dtc \
"
