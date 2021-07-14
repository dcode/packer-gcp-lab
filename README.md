# Packer scripts README
<!-- # spellchecker: disable -->

This directory contains [Packer](https://www.packer.io/) build scripts to creating standardized VM templates.
By using packer, we can ensure that when VMs are loaded they have the specific build steps that we expect to
be present. This becomes particularly important over time.

**Build windows 10 VM**

```
export GCS_BUCKET=my-bucket
export GCP_PROJECT=my-gce-project
./build -d --var-file=variables.json windows-10 
```

-----

## Prereqs

The script should check for these and offer ideas on how to get them, but so there's fewer surprises:


- bash
- packer
- curl
- sha256sum
- git
- yq
- jq
- docopt

## Project Layout

* build - Shell script to make it easier to build these boxes in a meaningfully automated way
* files - contains static files that are copied into VM templates.
* installer-configs - contains files that configure the OS installer such as
  `ks.cfg`, `preseed.cfg`, or `autounattend.xml`.
* isos - placeholder directory for local ISO copies
* output - placeholder directory that will contain all build artifacts except the `manifest.json`
* scripts - provisioner scripts that are copied to the VM post-install and executed
* `*.json` - these are the packer configuration templates and should be kept in this directory

---

## Builds

The builds are executed on a local QEMU instance. I built them primarily using qemu on Mac OS X (`brew install qemu`) with HVM acceleration. Probably better supported by `packer` is building on a Linux host with KVM. I've tested both with success. `qemu` can also run on Windows, but I made no effort to do that here. Should mostly have to just adjust the accelerator engine, maybe.

## Images

The `build` script processes configuration in `images.yml` and wraps `packer`, passing in a number of parameters via stdin as a vars file. You can also override any user variables in the Packer template by using the `--var-file` option.

## Results

I stripped out my production info, but this would feasibly upload to your GCP project and process it as an imported image via a bucket you configure. That's controlled by the environment vars `GCP_PROJECT` and `GCS_BUCKET`. Use the `--skip-import` option to disable importing images.

