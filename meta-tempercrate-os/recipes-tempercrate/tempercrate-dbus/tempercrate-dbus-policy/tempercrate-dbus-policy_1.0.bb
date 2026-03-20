SUMMARY = "D-Bus system policy for Gobbledegook / com.tempercrate"
DESCRIPTION = "Installs /etc/dbus-1/system.d/gobbledegook.conf"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"


SRC_URI = "file://gobbledegook.conf"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${sysconfdir}/dbus-1/system.d
    install -m 0644 ${WORKDIR}/gobbledegook.conf ${D}${sysconfdir}/dbus-1/system.d/gobbledegook.conf
}

FILES:${PN} += "${sysconfdir}/dbus-1/system.d/gobbledegook.conf"

# Optional: ensure dbus exists if you want
RDEPENDS:${PN} += "dbus"
