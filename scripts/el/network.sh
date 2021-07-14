#!/bin/bash -eux

# Ensure a nameserver is being used that won't return an IP for non-existent domain names.
printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\n" >/etc/resolv.conf

# shellcheck disable=SC1091
. "/etc/os-release"

# Set the hostname, and then ensure it will resolve properly.
printf "%s.localdomain\n" "${ID}" >/etc/hostname
printf "\n127.0.0.1   %s.localdomain\n" "${ID}" >>/etc/hosts
