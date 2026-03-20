TEMPERCRATE_FLASHLAYOUT_TSV_SOURCE ?= ""
TEMPERCRATE_FLASHLAYOUT_TSV_DEPLOY ?= "FlashLayout_TemperCrate.tsv"

TEMPERCRATE_RAW_IMAGE_ENABLE ??= "0"
TEMPERCRATE_RAW_IMAGE_ENABLE:stm32mp13-tempercrate-dev = "1"

TEMPERCRATE_RAW_IMAGE_SDCARD_SIZE_MB ??= "1200"
TEMPERCRATE_RAW_IMAGE_SCRIPT ?= "${TEMPERCRATE_META_REPO_DIR}/meta-tempercrate-os/scripts/create_tempercrate_sdcard_image.sh"
TEMPERCRATE_RAW_IMAGE_LINK_NAME ?= "${PN}-sdcard.raw"
TEMPERCRATE_RAW_IMAGE_OUTPUT_NAME ?= "${TEMPERCRATE_FLASHLAYOUT_TSV_DEPLOY:.tsv=.raw}"

python do_tempercrate_prepare_signed_flashlayout_artifacts () {
    import os
    import shutil

    if d.getVar("TEMPERCRATE_SB_ENABLE") != "1":
        bb.note("[TEMPERCRATE] Secure Boot disabled: no flashlayout artifact aliasing needed")
        return

    deploydir = d.getVar('DEPLOY_DIR_IMAGE')

    mappings = [
        (
            os.path.join(deploydir, "arm-trusted-firmware", "tf-a-stm32mp135f-dk-optee-programmer-usb_Signed.stm32"),
            os.path.join(deploydir, "arm-trusted-firmware", "tf-a-stm32mp135f-dk-optee-programmer-usb.stm32"),
        ),
        (
            os.path.join(deploydir, "arm-trusted-firmware", "tf-a-stm32mp135f-dk-optee-programmer-uart_Signed.stm32"),
            os.path.join(deploydir, "arm-trusted-firmware", "tf-a-stm32mp135f-dk-optee-programmer-uart.stm32"),
        ),
        (
            os.path.join(deploydir, "arm-trusted-firmware", "tf-a-stm32mp135f-dk-optee-sdcard_Signed.stm32"),
            os.path.join(deploydir, "arm-trusted-firmware", "tf-a-stm32mp135f-dk-optee-sdcard.stm32"),
        ),
        (
            os.path.join(deploydir, "fip", "fip-stm32mp135f-dk-optee-programmer-usb_Signed.bin"),
            os.path.join(deploydir, "fip", "fip-stm32mp135f-dk-optee-programmer-usb.bin"),
        ),
        (
            os.path.join(deploydir, "fip", "fip-stm32mp135f-dk-optee-sdcard_Signed.bin"),
            os.path.join(deploydir, "fip", "fip-stm32mp135f-dk-optee-sdcard.bin"),
        ),
    ]

    for src, dst in mappings:
        if not os.path.exists(src):
            bb.fatal("[TEMPERCRATE] Secure Boot enabled but signed artifact is missing: %s" % src)

        os.makedirs(os.path.dirname(dst), exist_ok=True)

        if os.path.lexists(dst):
            os.remove(dst)

        try:
            os.symlink(os.path.basename(src), dst)
            bb.note("[TEMPERCRATE] Created symlink: %s -> %s" % (dst, os.path.basename(src)))
        except OSError:
            shutil.copy2(src, dst)
            bb.note("[TEMPERCRATE] Symlink failed, copied instead: %s <= %s" % (dst, src))
}

addtask tempercrate_prepare_signed_flashlayout_artifacts after do_image_complete before do_create_flashlayout_config


python do_tempercrate_override_flashlayout () {
    import os
    import shutil

    rel = d.getVar("TEMPERCRATE_FLASHLAYOUT_TSV_SOURCE")
    if not rel:
        bb.fatal("[TEMPERCRATE] TEMPERCRATE_FLASHLAYOUT_TSV_SOURCE is not set")

    deploy_name = d.getVar("TEMPERCRATE_FLASHLAYOUT_TSV_DEPLOY")
    if not deploy_name:
        bb.fatal("[TEMPERCRATE] TEMPERCRATE_FLASHLAYOUT_TSV_DEPLOY is not set")

    src = None
    for p in d.getVar('BBPATH').split(':'):
        candidate = os.path.join(p, rel)
        if os.path.exists(candidate):
            src = candidate
            break

    if not src:
        bb.fatal("[TEMPERCRATE] Cannot find TSV in BBPATH using: %s" % rel)

    deploydir = d.getVar('DEPLOY_DIR_IMAGE')
    imagename = d.getVar('PN')
    dest = os.path.join(deploydir, "flashlayout_%s" % imagename, "optee", deploy_name)

    bb.note("[TEMPERCRATE] Deploying flashlayout TSV: %s <= %s" % (dest, src))
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    shutil.copy2(src, dest)
}

addtask tempercrate_override_flashlayout after do_create_flashlayout_config before do_build


do_tempercrate_generate_raw_image[depends] += "gptfdisk-native:do_populate_sysroot xz-native:do_populate_sysroot"

do_tempercrate_generate_raw_image() {
    if [ "${TEMPERCRATE_RAW_IMAGE_ENABLE}" != "1" ]; then
        bbnote "[TEMPERCRATE] RAW image generation disabled for MACHINE=${MACHINE}"
        exit 0
    fi

    if [ ! -f "${TEMPERCRATE_RAW_IMAGE_SCRIPT}" ]; then
        bbfatal "[TEMPERCRATE] RAW image helper script not found: ${TEMPERCRATE_RAW_IMAGE_SCRIPT}"
    fi

    install -m 0755 "${TEMPERCRATE_RAW_IMAGE_SCRIPT}" "${WORKDIR}/create_tempercrate_sdcard_image.sh"

    bbnote "[TEMPERCRATE] Generating RAW image for ${PN}"
    bbnote "[TEMPERCRATE] Using TSV: flashlayout_${PN}/optee/${TEMPERCRATE_FLASHLAYOUT_TSV_DEPLOY}"
    bbnote "[TEMPERCRATE] SD card size: ${TEMPERCRATE_RAW_IMAGE_SDCARD_SIZE_MB} MiB"

    cd "${DEPLOY_DIR_IMAGE}"

    rm -f "${TEMPERCRATE_RAW_IMAGE_OUTPUT_NAME}" "${TEMPERCRATE_RAW_IMAGE_LINK_NAME}"

    SDCARD_SIZE="${TEMPERCRATE_RAW_IMAGE_SDCARD_SIZE_MB}" \
        "${WORKDIR}/create_tempercrate_sdcard_image.sh" \
        "flashlayout_${PN}/optee/${TEMPERCRATE_FLASHLAYOUT_TSV_DEPLOY}"

    if [ ! -f "${DEPLOY_DIR_IMAGE}/${TEMPERCRATE_RAW_IMAGE_OUTPUT_NAME}" ]; then
        bbfatal "[TEMPERCRATE] Expected RAW image not found: ${DEPLOY_DIR_IMAGE}/${TEMPERCRATE_RAW_IMAGE_OUTPUT_NAME}"
    fi

    ln -sf "${TEMPERCRATE_RAW_IMAGE_OUTPUT_NAME}" "${DEPLOY_DIR_IMAGE}/${TEMPERCRATE_RAW_IMAGE_LINK_NAME}"

    bbnote "[TEMPERCRATE] RAW image generated:"
    bbnote "[TEMPERCRATE]   ${DEPLOY_DIR_IMAGE}/${TEMPERCRATE_RAW_IMAGE_OUTPUT_NAME}"
    bbnote "[TEMPERCRATE] Alias created:"
    bbnote "[TEMPERCRATE]   ${DEPLOY_DIR_IMAGE}/${TEMPERCRATE_RAW_IMAGE_LINK_NAME}"
}

addtask tempercrate_generate_raw_image after do_tempercrate_override_flashlayout before do_build