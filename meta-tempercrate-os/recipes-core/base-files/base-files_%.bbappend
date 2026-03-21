# Set system hostname
hostname = "temper-crate-os"


FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://issue"

do_install:append() {
    install -m 0644 ${WORKDIR}/issue ${D}${sysconfdir}/issue
}
