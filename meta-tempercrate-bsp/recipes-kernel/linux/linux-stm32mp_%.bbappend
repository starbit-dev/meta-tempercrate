# meta-tempercrate-bsp/recipes-kernel/linux/linux-stm32mp_%.bbappend
#
# Purpose:
# - Keep DEV and PROD device-tree sources fully separated.
# - Add a custom DTS for each MACHINE (DEV vs PROD).
# - Copy the DTS into the kernel source tree so the kernel build can compile it.
#
# Assumptions:
# - Your MACHINE .conf files already set:
#     DEV : KERNEL_DEVICETREE = "st/stm32mp135f-tempercrate-dev.dtb"
#     PROD: KERNEL_DEVICETREE = "st/stm32mp135f-tempercrate-prod.dtb"
# - Your custom DTS files are stored in this layer under:
#     recipes-kernel/linux/files/dts/stm32mp13-tempercrate-dev/stm32mp135f-tempercrate-dev.dts
#     recipes-kernel/linux/files/dts/stm32mp13-tempercrate-prod/stm32mp135f-tempercrate-prod.dts

# Make BitBake search our local "files/" folder for file:// entries.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# --- DEV machine: add DEV DTS to SRC_URI ---
SRC_URI:append:stm32mp13-tempercrate-dev = " \
    file://dts/stm32mp13-tempercrate-dev/stm32mp135f-tempercrate-dev.dts \
"

# --- PROD machine: add PROD DTS to SRC_URI ---
SRC_URI:append:stm32mp13-tempercrate-prod = " \
    file://dts/stm32mp13-tempercrate-prod/stm32mp135f-tempercrate-prod.dts \
"

# Kernel config fragment (applies to all machines): enable QCA7000 over SPI support.
SRC_URI += "file://qca7000.cfg"

# Force-merge our kernel config fragment into the final .config
do_configure:append() {
    if [ -f "${WORKDIR}/qca7000.cfg" ]; then
        bbnote "Merging kernel config fragment: ${WORKDIR}/qca7000.cfg"

        # Merge fragment into current config
        ${S}/scripts/kconfig/merge_config.sh -m -r \
            ${B}/.config \
            ${WORKDIR}/qca7000.cfg

        # Regenerate autoconfig headers
        oe_runmake -C ${S} O=${B} olddefconfig
    else
        bbfatal "Missing ${WORKDIR}/qca7000.cfg"
    fi
}

# Copy DEV DTS into the kernel DTS directory before compilation.
# ${WORKDIR} is where file:// artifacts land.
# ${S} is the kernel source tree used for the build.
do_configure:append:stm32mp13-tempercrate-dev() {
    install -d ${S}/arch/arm/boot/dts/st
    install -m 0644 ${WORKDIR}/dts/stm32mp13-tempercrate-dev/stm32mp135f-tempercrate-dev.dts \
        ${S}/arch/arm/boot/dts/st/stm32mp135f-tempercrate-dev.dts
}

# Copy PROD DTS into the kernel DTS directory before compilation.
do_configure:append:stm32mp13-tempercrate-prod() {
    install -d ${S}/arch/arm/boot/dts/st
    install -m 0644 ${WORKDIR}/dts/stm32mp13-tempercrate-prod/stm32mp135f-tempercrate-prod.dts \
        ${S}/arch/arm/boot/dts/st/stm32mp135f-tempercrate-prod.dts
}
