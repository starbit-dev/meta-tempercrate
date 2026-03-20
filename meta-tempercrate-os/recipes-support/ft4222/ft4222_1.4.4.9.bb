SUMMARY = "FTDI FT4222 userspace library (prebuilt)"
DESCRIPTION = "Prebuilt vendor userspace library for FTDI FT4222"
LICENSE = "CLOSED"

S = "${WORKDIR}"

SRC_URI = " \
    file://libft4222.so.1.4.4.9 \
    file://libft4222.h \
    file://ftd2xx.h \
"

# Do NOT auto-classify unversioned .so as -dev for this prebuilt vendor blob
SOLIBSDEV = ""
FILES_SOLIBSDEV = ""

# Ensure correct packaging for a prebuilt shared library blob
do_install() {
    install -d ${D}${libdir}
    install -m 0755 ${WORKDIR}/libft4222.so.1.4.4.9 ${D}${libdir}/

    # Runtime / SONAME symlink (loader may need this)
    ln -sf libft4222.so.1.4.4.9 ${D}${libdir}/libft4222.so.1

    # Unversioned linker/dlopen name - REQUIRED at runtime for your app
    ln -sf libft4222.so.1.4.4.9 ${D}${libdir}/libft4222.so

    install -d ${D}${includedir}
    install -m 0644 ${WORKDIR}/libft4222.h ${D}${includedir}/
    install -m 0644 ${WORKDIR}/ftd2xx.h ${D}${includedir}/
}

# --- Packaging ---
# Put the real .so and symlinks into runtime package on purpose (tempercrateboxd loads libft4222.so)
FILES:${PN} += " \
    ${libdir}/libft4222.so.1.4.4.9 \
    ${libdir}/libft4222.so.1 \
    ${libdir}/libft4222.so \
"

# Headers to -dev (fine)
FILES:${PN}-dev += " \
    ${includedir}/libft4222.h \
    ${includedir}/ftd2xx.h \
"

# Prevent default packaging rules from grabbing the unversioned .so into -dev
FILES:${PN}-dev:remove = " ${libdir}/libft4222.so "

# --- QA skips ---
# Prebuilt binary triggers 32bit time API QA check on 32-bit targets
INSANE_SKIP:${PN} += "ldflags 32bit-time dev-so"

