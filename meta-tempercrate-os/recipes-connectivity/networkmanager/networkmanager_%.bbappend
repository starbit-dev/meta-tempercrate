FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://10-hostname-mode-none.conf"

do_install:append() {
    install -d ${D}${sysconfdir}/NetworkManager/conf.d
    install -m 0644 ${WORKDIR}/10-hostname-mode-none.conf \
        ${D}${sysconfdir}/NetworkManager/conf.d/10-hostname-mode-none.conf
}
