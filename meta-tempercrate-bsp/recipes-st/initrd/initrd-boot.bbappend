FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " file://init-resize.sh"

RDEPENDS:${PN}:append = " gptfdisk parted"