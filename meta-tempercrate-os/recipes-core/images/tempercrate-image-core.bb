DESCRIPTION = "TemperCrate core image (based on st-image-core)"
LICENSE = "MIT"
require recipes-st/images/st-image-core.bb
inherit tempercrate-secureboot

# ST adds st-hostname in the base image and its service appends the MAC
# address to /etc/hostname at boot. Remove it to keep the static hostname.
CORE_IMAGE_EXTRA_INSTALL:remove = "st-hostname"

# Add EVSE required package to core image
IMAGE_INSTALL:append = " packagegroup-tempercrate-evse"

# Remove warning on LIC file
SDK_POSTPROCESS_COMMAND:remove = " do_write_sdk_license_create_summary;"
# Remove warning on image license summary (IMG LIC SUM) from ST task
do_st_write_license_create_summary[noexec] = "1"
do_st_write_license_create_summary_setscene[noexec] = "1"

# =============================================================================
# Image Identification Stamp
# -----------------------------------------------------------------------------
# Generates /etc/tempercrate-image-id in the rootfs with build + Git metadata.
# Uses the meta-tempercrate Git repo (parent directory of meta-tempercrate-os layer) and
# records:
#   - Image recipe name (PN)
#   - Build timestamp (DATETIME)
#   - Machine / Distro
#   - meta-tempercrate repo path used at build time (for debugging)
#   - Git branch (or "detached")
#   - Git tag (only if HEAD exactly matches a tag; otherwise "None")
#   - Git commit short hash
#   - Git describe (tag/commit + dirty state)
# =============================================================================
# =============================================================================
# Image Identification Stamp
# -----------------------------------------------------------------------------
# Generates /etc/tempercrate-image-id in the rootfs with build + Git metadata.
#
# Requires: TEMPERCRATE_META_REPO_DIR exported by meta-tempercrate-os/conf/layer.conf, e.g.:
#   TEMPERCRATE_META_REPO_DIR := "${@os.path.abspath(os.path.join(d.getVar('LAYERDIR'), '..'))}"
# =============================================================================

ROOTFS_POSTPROCESS_COMMAND += "create_tempercrate_image_stamp;"

create_tempercrate_image_stamp() {
    install -d "${IMAGE_ROOTFS}/etc"

    out="${IMAGE_ROOTFS}/etc/tempercrate-image-id"

    # meta-tempercrate repository root (working tree root containing meta-tempercrate-os/meta-tempercrate-bsp)
    TEMPERCRATE_REPO="${TEMPERCRATE_META_REPO_DIR}"
    if [ -z "${TEMPERCRATE_REPO}" ]; then
        TEMPERCRATE_REPO="None"
    fi
    
    # Git metadata
    if [ "${TEMPERCRATE_REPO}" != "None" ] && git -C "${TEMPERCRATE_REPO}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        COMMIT="$(git -C "${TEMPERCRATE_REPO}" rev-parse --short HEAD 2>/dev/null || echo "None")"
        BRANCH="$(git -C "${TEMPERCRATE_REPO}" symbolic-ref --short -q HEAD 2>/dev/null || echo "detached")"
        TAG="$(git -C "${TEMPERCRATE_REPO}" describe --tags --exact-match 2>/dev/null || echo "None")"
        DESCRIBE="$(git -C "${TEMPERCRATE_REPO}" describe --tags --always --dirty 2>/dev/null || echo "None")"

        # Optional: explicit dirty flag (even if describe fails)
        if git -C "${TEMPERCRATE_REPO}" diff --quiet >/dev/null 2>&1 && git -C "${TEMPERCRATE_REPO}" diff --cached --quiet >/dev/null 2>&1; then
            DIRTY="no"
        else
            DIRTY="yes"
        fi
    else
        BRANCH="None"
        TAG="None"
        COMMIT="None"
        DESCRIBE="None"
        DIRTY="None"
    fi

    # Basic image/build info
    {
        echo "Image             : ${PN}"
        echo "Machine           : ${MACHINE}"
        echo "Build             : ${DATETIME}"
        echo "meta-tempercrate-repo    : ${TEMPERCRATE_REPO}"
        echo "Distro            : ${DISTRO} ${DISTRO_VERSION}"
        echo "meta-tempercrate-branch  : ${BRANCH}"
        echo "meta-tempercrate-tag     : ${TAG}"
        echo "meta-tempercrate-commit  : ${COMMIT}"
        echo "meta-tempercrate-describe: ${DESCRIBE}"
        echo "meta-tempercrate-dirty   : ${DIRTY}"
    } >> "${out}"
}

# Ensure the custom userfs image is generated during the main image build.
# The resulting ext4 image is referenced by the FlashLayout TSV.
do_image_complete[depends] += "tempercrate-userfs-ext4:do_deploy"

# Remove any legacy /usr/local mount entries from the generated fstab.
# userfs is now mounted on /app via a systemd mount unit.
ROOTFS_POSTPROCESS_COMMAND += "remove_usr_local_from_fstab; "

remove_usr_local_from_fstab() {
    if [ -f ${IMAGE_ROOTFS}${sysconfdir}/fstab ]; then
        sed -i '\|[[:space:]]/usr/local[[:space:]]|d' ${IMAGE_ROOTFS}${sysconfdir}/fstab
    fi
}

# Drop /usr/local from the rootfs to prevent it being reused as a mountpoint.
# The application filesystem is now exposed exclusively at /app.
ROOTFS_POSTPROCESS_COMMAND += "remove_usr_local; "

remove_usr_local() {
    rm -rf ${IMAGE_ROOTFS}/usr/local
}

