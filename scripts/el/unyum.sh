#!/bin/bash -eux

# shellcheck disable=SC1091
. "/etc/os-release"

if [ "$(echo "${VERSION_ID} >= 7" | bc)" -ne 0 ] && [ "$(echo "${VERSION_ID} < 8" | bc)" -ne 0 ]; then
    sed -i -e "s/^baseurl/#baseurl/g" \
        -e "s/^#mirrorlist/mirrorlist/g" \
        -e "s/https:\/\/mirrors.edge.kernel.org\/centos\//http:\/\/mirror.centos.org\/centos\//g" \
        /etc/yum.repos.d/CentOS-Base.repo

    sed -i -e "s/^baseurl/#baseurl/g" \
        -e "s/^#mirrorlist/mirrorlist/g" \
        -e "s/https:\/\/mirrors.kernel.org\/fedora-epel\//http:\/\/download.fedoraproject.org\/pub\/epel\//g" \
        /etc/yum.repos.d/epel.repo
elif [ "$(echo "${VERSION_ID} >= 8" | bc)" -ne 0 ] && [ "$(echo "${VERSION_ID} < 9" | bc)" -ne 0 ]; then

    # Move unchanged repo files back in place
    for item in /etc/yum.repos.d/*.repo.orig; do
        mv --force "${item}" "$(basename "${item}" .orig)"
    done
fi
