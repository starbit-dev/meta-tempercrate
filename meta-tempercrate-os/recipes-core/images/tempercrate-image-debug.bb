DESCRIPTION = "TemperCrate debug image (based on tempercrate-image-core)"
LICENSE = "MIT"

require tempercrate-image-core.bb
inherit tempercrate-secureboot

IMAGE_INSTALL:append = " packagegroup-tempercrate-debug "

# Remove warning on LIC file
SDK_POSTPROCESS_COMMAND:remove = " do_write_sdk_license_create_summary;"

# Remove warning on image license summary (IMG LIC SUM) from ST task
do_st_write_license_create_summary[noexec] = "1"
do_st_write_license_create_summary_setscene[noexec] = "1"
