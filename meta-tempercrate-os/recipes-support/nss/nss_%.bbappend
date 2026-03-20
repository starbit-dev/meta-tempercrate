# NSS sometimes fails to link with --as-needed (undefined reference to PK11_* ...)
LDFLAGS:remove = "-Wl,--as-needed"
