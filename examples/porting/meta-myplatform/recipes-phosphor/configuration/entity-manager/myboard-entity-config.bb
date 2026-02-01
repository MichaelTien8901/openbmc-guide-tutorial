SUMMARY = "MyBoard Entity Manager Configuration"
DESCRIPTION = "Entity Manager JSON configuration for MyBoard platform"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit allarch

RDEPENDS:${PN} = "entity-manager"

SRC_URI = " \
    file://myboard.json \
"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${datadir}/entity-manager/configurations
    install -m 0644 ${S}/myboard.json \
        ${D}${datadir}/entity-manager/configurations/
}

FILES:${PN} = "${datadir}/entity-manager/configurations/*"
