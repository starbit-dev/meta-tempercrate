SUMMARY = "Mount userfs on /app with systemd"
DESCRIPTION = "Creates /app, installs app.mount and removes legacy /usr/local mount"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SRC_URI = " \
    file://app.mount \
    file://usr-local-umount.service \
"

S = "${WORKDIR}"

SYSTEMD_SERVICE:${PN} = "app.mount usr-local-umount.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}/app
    install -d ${D}${systemd_system_unitdir}

    install -m 0644 ${WORKDIR}/app.mount \
        ${D}${systemd_system_unitdir}/app.mount

    install -m 0644 ${WORKDIR}/usr-local-umount.service \
        ${D}${systemd_system_unitdir}/usr-local-umount.service

    install -d ${D}${sysconfdir}/systemd/system
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/usr-local.mount
}

FILES:${PN} += " \
    /app \
    ${systemd_system_unitdir}/app.mount \
    ${systemd_system_unitdir}/usr-local-umount.service \
    ${sysconfdir}/systemd/system/usr-local.mount \
"