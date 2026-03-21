SUMMARY = "TemperCrate RAUC OS bundle"
DESCRIPTION = "Signed RAUC bundle containing bootfs and rootfs for TemperCrate OS updates"
LICENSE = "MIT"

inherit bundle

RAUC_BUNDLE_COMPATIBLE = "temper,stm32mp1"
RAUC_BUNDLE_SLOTS = "boot rootfs"

RAUC_SLOT_boot = "st-image-bootfs"
RAUC_SLOT_boot[fstype] = "ext4"
RAUC_SLOT_boot[file] = "st-image-bootfs-tempercrate-linux-stm32mp13-tempercrate-dev.bootfs.ext4"

RAUC_SLOT_rootfs = "tempercrate-image-core"
RAUC_SLOT_rootfs[fstype] = "ext4"
RAUC_SLOT_rootfs[file] = "tempercrate-image-core-tempercrate-linux-stm32mp13-tempercrate-dev.rootfs.ext4"

RAUC_KEY_FILE = "/mnt/yocto/TemperCrateOS/tempercrate-workdir/rauc-dev-ca/development-1.key.pem"
RAUC_CERT_FILE = "/mnt/yocto/TemperCrateOS/tempercrate-workdir/rauc-dev-ca/development-1.cert.pem"