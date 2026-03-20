SUMMARY = "Qualcomm Atheros Open Powerline Toolkit (plctool)"
HOMEPAGE = "https://github.com/qca/open-plc-utils"
LICENSE = "BSD-3-Clause-Clear"

S = "${WORKDIR}"
B = "${S}"

LIC_FILES_CHKSUM = "file://git/LICENSE;md5=7d83a9e9a9788beb9357262af385f6c7"

SRC_URI = "git://github.com/qca/open-plc-utils.git;protocol=https;branch=master"
SRCREV = "${AUTOREV}"

DEPENDS = "libpcap"

# Eseguiamo la fix SUBITO DOPO do_patch (postfunc)
do_patch[postfuncs] += "fix_plctool_makefile"

fix_plctool_makefile() {
    mf="${S}/git/plc/Makefile"

    # forza dipendenze plctool: plctool.o
    sed -i 's/^plctool: .*/plctool: plctool.o/' "$mf"

    # riscrive la riga di link subito sotto al target plctool:
    sed -i '/^plctool: plctool\.o/{n;s|^[[:space:]]*.*|	$(CC) $(LDFLAGS) -o $@ plctool.o $(LIBS)|;}' "$mf"
}

do_compile() {
    oe_runmake -C ${S}/git/plc \
        CC="${CC}" AR="${AR}" LD="${LD}" RANLIB="${RANLIB}" STRIP="${STRIP}" \
        CFLAGS="${CFLAGS} -DAR7x00" \
        CPPFLAGS="${CPPFLAGS}" \
        LDFLAGS="${LDFLAGS}" \
        plctool
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${S}/git/plc/plctool ${D}${bindir}/plctool
}
