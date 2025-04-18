#!/usr/bin/env bash

set -x
set -euo pipefail

# shellcheck disable=SC1091
. lib.sh

hide_output() {
    set +x
    trap "
        echo 'ERROR: An error was encountered with the build.'
        cat /tmp/build.log
        exit 1
    " ERR
    bash -c 'while true; do sleep 30; echo $(date) - building ...; done' &
    PING_LOOP_PID=$!
    "${@}" &>/tmp/build.log
    trap - ERR
    kill "${PING_LOOP_PID}"
    set -x
}

main() {
    local binutils_version=2.33.1
    local gcc_version=9.2.0
    local musl_version=1.2.3
    local version=fe91582

    if_ubuntu_ge 24.04 binutils_version=2.44
    if_ubuntu_ge 24.04 gcc_version=13.3.0
    if_ubuntu_ge 24.04 musl_version=1.2.5
    if_ubuntu_ge 24.04 version=fd6be58

    install_packages ca-certificates curl build-essential

    local td
    td="$(mktemp -d)"

    pushd "${td}"
    curl --retry 3 -sSfL "https://github.com/richfelker/musl-cross-make/archive/${version}.tar.gz" -O
    tar --strip-components=1 -xzf "${version}.tar.gz"

    # Don't depend on the mirrors of sabotage linux that musl-cross-make uses.
    local linux_headers_site=https://ci-mirrors.rust-lang.org/rustc/sabotage-linux-tarballs
    local linux_ver=headers-4.19.88

    # Ensure sources directory exists
    mkdir -p ./sources

    # Download gcc
    download_gcc $gcc_version gz
    mv "./gcc-$gcc_version.tar.gz" ./sources/

    # Download binutils
    download_binutils $binutils_version gz
    mv "./binutils-$binutils_version.tar.gz" ./sources/

    # alpine GCC is built with `--enable-default-pie`, so we want to
    # ensure we use that. we want support for shared runtimes except for
    # libstdc++, however, the only way to do that is to simply remove
    # the shared libraries later. on alpine, binaries use static-pie
    # linked, so our behavior has maximum portability, and is consistent
    # with popular musl distros.
    hide_output make install "-j$(nproc)" \
        GCC_VER=$gcc_version \
        MUSL_VER=$musl_version \
        BINUTILS_VER=$binutils_version \
        DL_CMD='curl --retry 3 -sSfL -C - -o' \
        LINUX_HEADERS_SITE="${linux_headers_site}" \
        LINUX_VER="${linux_ver}" \
        OUTPUT=/usr/local/ \
        "GCC_CONFIG += --enable-default-pie --enable-languages=c,c++,fortran" \
        "${@}"

    purge_packages

    popd

    rm /tmp/build.log
    rm -rf "${td}"
    rm "${0}"
}

main "${@}"
